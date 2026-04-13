// awg_timed_ctrl.v -- AWG timed-control AXI-Lite peripheral
//
// Register map (offset from base, 32-bit aligned):
//   0x00  CTRL          RW  [0]=run(pulse), [1]=arm(pulse), [2]=stop(pulse),
//                           [3]=reset_soft(pulse), [8]=irq_en(sticky)
//   0x04  STATUS        RO  [0]=armed, [1]=running, [2]=done, [3]=error, [15:8]=err_code
//   0x08  EVENT_COUNT   RW  active event count (write only when !armed && !running)
//   0x0C  CUR_EVENT     RO  current read-pointer / execution progress
//   0x10  ERR_REG       RO  STATUS[15:8] mirror for firmware compatibility
//   0x14  IP_ID         RO  0x41574753 ("AWGS")
//   0x18  IP_VERSION    RO  {major[15:0], minor[15:0]} = 0x00010000
//   0x1C  IP_CAPS       RO  {event_depth_log2[7:0], payload_bits[7:0]=128, ts_bits[7:0]=64, rsvd[7:0]}
//   0x20  TIME_NOW_LO   RO  sched_time_counter[31:0]  (best-effort 2-FF CDC, debug)
//   0x24  TIME_NOW_HI   RO  sched_time_counter[63:32] (best-effort 2-FF CDC, debug)
//   0x28  LAST_EXEC_LO  RO  timestamp of last successfully fired event [31:0]
//   0x2C  LAST_EXEC_HI  RO  timestamp of last successfully fired event [63:32]
//   0x30  COMMIT_COUNT  RO  number of events successfully fired
//   0x34  REINIT_COUNT  RO  reserved (0, Step-5 placeholder)
//   0x38  REINIT_REJECT RO  reserved (0, Step-5 placeholder)
//   0x3C  IRQ_STATUS    RW1C [0]=done, [1]=error, [2]=spacing_violation, [3]=underrun
//   0x40  EVT_WADDR     RW  event write address
//   0x44  EVT_WDATA0    RW  event timestamp[31:0]
//   0x48  EVT_WDATA1    RW  event timestamp[63:32]
//   0x4C  EVT_WDATA2    RW  event {channel[15:0], flags[15:0]}
//   0x50  EVT_WDATA3    RW  event payload[31:0]
//   0x54  EVT_WDATA4    RW  event payload[63:32]
//   0x58  EVT_WDATA5    RW  event payload[95:64]
//   0x5C  EVT_WDATA6    RW  event payload[127:96]
//   0x60  EVT_WCTRL     WO  bit0=push (latch WDATA0-6 into event_mem[WADDR])
//   0x64  IRQ_ENABLE    RW  optional per-bit enable mask for IRQ_STATUS
//   0x68  IP_SCRATCH    RW  read-back scratch register
//
// Event word layout (256 bits):
//   [63:0]   timestamp (64b)
//   [79:64]  channel   (16b)
//   [95:80]  flags     (16b)
//   [223:96] payload   (128b)
//   [255:224] reserved (32b, always zero)
//
// Engine state machine (sched_clk domain):
//   IDLE -> (arm)  -> ARMED
//   ARMED -> (run && event_count>0) -> WAIT_FETCH
//   WAIT_FETCH -> (1 cycle BRAM latency) -> COMPARE
//   COMPARE -> (ts > now) -> stay
//   COMPARE -> (ts <= now, no spacing violation) -> FIRE
//   COMPARE -> (ts < now on first check: missed deadline) -> ERROR
//   COMPARE -> (spacing violation) -> ERROR
//   FIRE -> ADVANCE
//   ADVANCE -> (more events) -> WAIT_FETCH
//   ADVANCE -> (last event) -> DONE
//   DONE/ERROR -> (stay until stop/reset_soft)
//
// Deferred (future PRs):
//   Step 3: SYSREF-qualified timebase reset + TIME_RELOAD registers
//   Step 4: TPL DDS scheduled-control port wiring (library/jesd204/)
//   Step 5: PHASE_REINIT binding and REINIT_COUNT registers
//   Step 6: Cocotb tests, SBY liveness, IP-XACT packaging

module awg_timed_ctrl #(
  parameter integer EVENT_MEM_ADDR_WIDTH = 8,
  parameter integer MIN_SPACING_TICKS    = 8
) (
  // AXI4-Lite slave
  input  wire        s_axi_aclk,
  input  wire        s_axi_aresetn,
  input  wire [7:0]  s_axi_awaddr,
  input  wire        s_axi_awvalid,
  output reg         s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output reg         s_axi_wready,
  output reg  [1:0]  s_axi_bresp,
  output reg         s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [7:0]  s_axi_araddr,
  input  wire        s_axi_arvalid,
  output reg         s_axi_arready,
  output reg  [31:0] s_axi_rdata,
  output reg  [1:0]  s_axi_rresp,
  output reg         s_axi_rvalid,
  input  wire        s_axi_rready,
  // Scheduler clock domain
  input  wire        sched_clk,
  input  wire        sched_reset,
  // Marker outputs (sched_clk domain, 1-cycle active-high pulses)
  output reg         marker_commit,  // pulses once per fired event
  output reg         marker_start,   // pulses when engine begins execution
  output reg         marker_done,    // pulses when all events complete
  // Interrupt (s_axi_aclk domain, level-high while pending & enabled)
  output wire        irq
);

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------
  localparam integer EVENT_MEM_DEPTH = (1 << EVENT_MEM_ADDR_WIDTH);

  // IP identification
  localparam [31:0] IP_ID_VAL      = 32'h41574753;  // "AWGS"
  localparam [31:0] IP_VERSION_VAL = 32'h00010000;  // major=1, minor=0
  // IP_CAPS: {event_depth_log2[7:0], payload_bits[7:0]=128, ts_bits[7:0]=64, rsvd[7:0]=0}
  localparam [31:0] IP_CAPS_VAL    = {EVENT_MEM_ADDR_WIDTH[7:0], 8'd128, 8'd64, 8'h00};

  // Register offsets
  localparam [7:0] REG_CTRL         = 8'h00;
  localparam [7:0] REG_STATUS       = 8'h04;
  localparam [7:0] REG_EVENT_COUNT  = 8'h08;
  localparam [7:0] REG_CUR_EVENT    = 8'h0C;
  localparam [7:0] REG_ERR_REG      = 8'h10;
  localparam [7:0] REG_IP_ID        = 8'h14;
  localparam [7:0] REG_IP_VERSION   = 8'h18;
  localparam [7:0] REG_IP_CAPS      = 8'h1C;
  localparam [7:0] REG_TIME_NOW_LO  = 8'h20;
  localparam [7:0] REG_TIME_NOW_HI  = 8'h24;
  localparam [7:0] REG_LAST_EXEC_LO = 8'h28;
  localparam [7:0] REG_LAST_EXEC_HI = 8'h2C;
  localparam [7:0] REG_COMMIT_COUNT = 8'h30;
  localparam [7:0] REG_REINIT_COUNT = 8'h34;
  localparam [7:0] REG_REINIT_REJECT= 8'h38;
  localparam [7:0] REG_IRQ_STATUS   = 8'h3C;
  localparam [7:0] REG_EVT_WADDR    = 8'h40;
  localparam [7:0] REG_EVT_WDATA0   = 8'h44;
  localparam [7:0] REG_EVT_WDATA1   = 8'h48;
  localparam [7:0] REG_EVT_WDATA2   = 8'h4C;
  localparam [7:0] REG_EVT_WDATA3   = 8'h50;
  localparam [7:0] REG_EVT_WDATA4   = 8'h54;
  localparam [7:0] REG_EVT_WDATA5   = 8'h58;
  localparam [7:0] REG_EVT_WDATA6   = 8'h5C;
  localparam [7:0] REG_EVT_WCTRL    = 8'h60;
  localparam [7:0] REG_IRQ_ENABLE   = 8'h64;
  localparam [7:0] REG_IP_SCRATCH   = 8'h68;

  // Engine states
  localparam [2:0] ENGINE_IDLE       = 3'd0;
  localparam [2:0] ENGINE_ARMED      = 3'd1;
  localparam [2:0] ENGINE_WAIT_FETCH = 3'd2;
  localparam [2:0] ENGINE_COMPARE    = 3'd3;
  localparam [2:0] ENGINE_FIRE       = 3'd4;
  localparam [2:0] ENGINE_ADVANCE    = 3'd5;
  localparam [2:0] ENGINE_DONE       = 3'd6;
  localparam [2:0] ENGINE_ERROR      = 3'd7;

  // IRQ_STATUS bit positions
  localparam IRQ_DONE              = 0;
  localparam IRQ_ERROR             = 1;
  localparam IRQ_SPACING_VIOLATION = 2;
  localparam IRQ_UNDERRUN          = 3;

  // Error codes (placed in STATUS[15:8])
  localparam [7:0] ERR_NONE              = 8'h00;
  localparam [7:0] ERR_MISSED_DEADLINE   = 8'h01;
  localparam [7:0] ERR_SPACING_VIOLATION = 8'h02;

  // Minimum spacing as a 64-bit constant for safe comparison
  localparam [63:0] MIN_SPACING_VAL = MIN_SPACING_TICKS;

  // ---------------------------------------------------------------------------
  // AXI-domain registers
  // ---------------------------------------------------------------------------
  reg [31:0] scratch_reg;
  reg        irq_en_reg;
  reg [31:0] irq_enable_reg;
  reg [31:0] irq_status_axi;    // RW1C; bits OR'd in from sched snapshots
  reg [31:0] event_count_cfg;   // writable only when !armed && !running
  reg [EVENT_MEM_ADDR_WIDTH-1:0] evt_waddr_reg;
  reg [31:0] evt_wdata0_reg, evt_wdata1_reg, evt_wdata2_reg;
  reg [31:0] evt_wdata3_reg, evt_wdata4_reg, evt_wdata5_reg, evt_wdata6_reg;

  // AXI shadow registers (captured from sched status snapshots)
  reg [31:0] status_shadow;
  reg [63:0] last_exec_shadow;
  reg [31:0] commit_count_shadow;
  reg [31:0] cur_event_shadow;
  reg [31:0] commit_count_gray_sync1, commit_count_gray_sync2;

  // TIME_NOW best-effort 2-FF sync (debug only)
  reg [31:0] time_now_lo_s1, time_now_lo_s2;
  reg [31:0] time_now_hi_s1, time_now_hi_s2;

  // ---------------------------------------------------------------------------
  // CDC: AXI -> sched (toggle synchronizers)
  // ---------------------------------------------------------------------------
  // Toggle regs toggled by AXI writes; synced in sched domain
  reg arm_req_tgl, run_req_tgl, stop_req_tgl, sreset_req_tgl;
  reg event_wr_req_tgl;
  // Data transferred alongside event_wr_req_tgl
  reg [EVENT_MEM_ADDR_WIDTH-1:0] event_wr_addr_cfg;
  reg [255:0]                    event_wr_data_cfg;

  // ---------------------------------------------------------------------------
  // CDC: sched -> AXI (toggle synchronizers + snapshot)
  // ---------------------------------------------------------------------------
  reg status_snap_tgl;    // toggled when engine state/counters change
  reg event_wr_ack_tgl;   // toggled when each event write completes

  // Snapshot data (written in sched_clk, read in s_axi_aclk after toggle edge)
  reg [31:0] status_sched_snap;
  reg [63:0] last_exec_sched_snap;
  reg [31:0] cur_event_snap;
  reg [3:0]  irq_snap;

  // ---------------------------------------------------------------------------
  // AXI-domain CDC sync chains
  // ---------------------------------------------------------------------------
  reg status_snap_sync1,   status_snap_sync2,   status_snap_sync2_d;
  reg event_wr_ack_sync1,  event_wr_ack_sync2,  event_wr_ack_sync2_d;

  // ---------------------------------------------------------------------------
  // Sched-domain CDC sync chains
  // ---------------------------------------------------------------------------
  reg arm_req_sync1,    arm_req_sync2,    arm_req_sync2_d;
  reg run_req_sync1,    run_req_sync2,    run_req_sync2_d;
  reg stop_req_sync1,   stop_req_sync2,   stop_req_sync2_d;
  reg sreset_req_sync1, sreset_req_sync2, sreset_req_sync2_d;
  reg event_wr_req_sync1, event_wr_req_sync2, event_wr_req_sync2_d;
  // event_count_cfg 2-FF direct sync to sched domain
  reg [31:0] event_count_s1, event_count_s2;

  // ---------------------------------------------------------------------------
  // Sched-domain engine state
  // ---------------------------------------------------------------------------
  reg [63:0] sched_time_counter;
  reg [2:0]  engine_state;
  reg [31:0] event_count_sched;  // captured at ARM time from event_count_s2
  reg [31:0] read_ptr;
  reg [63:0] last_exec_sched;
  reg [31:0] commit_count_sched;
  reg [31:0] commit_count_gray_sched;
  reg [63:0] prev_ts;            // timestamp of previous fired event (spacing check)
  reg [7:0]  error_code;
  reg [3:0]  irq_sched;          // sticky IRQ bits in sched domain
  reg        compare_first;      // high on the first cycle in ENGINE_COMPARE

  // BRAM: no synchronous reset; relies on power-up initialisation.
  // The (* ram_style = "block" *) attribute prevents Vivado inferring a
  // synchronous-reset for-loop over BRAM outputs (UltraScale BRAM does not
  // support a synchronous reset on the data output).
  (* ram_style = "block" *) reg [255:0] event_mem [0:EVENT_MEM_DEPTH-1];
  reg [255:0] fetch_data;   // registered BRAM output (1-cycle read latency)

  // ---------------------------------------------------------------------------
  // Combinational helpers
  // ---------------------------------------------------------------------------
  wire write_fire = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
  wire read_fire  = s_axi_arvalid && s_axi_arready;

  // Current event fields decoded from fetch_data
  wire [63:0]  ev_ts      = fetch_data[63:0];
  wire [15:0]  ev_ch      = fetch_data[79:64];
  wire [15:0]  ev_flags   = fetch_data[95:80];
  wire [127:0] ev_payload = fetch_data[223:96];
  wire [31:0]  cur_event_next = read_ptr + 1'b1;
  wire [31:0]  commit_count_next = commit_count_sched + 1'b1;
  wire [31:0]  commit_count_next_gray = commit_count_next ^ (commit_count_next >> 1);
  wire         arm_edge = arm_req_sync2 ^ arm_req_sync2_d;
  wire         run_edge = run_req_sync2 ^ run_req_sync2_d;

  // Gray-to-binary conversion for AXI-domain COMMIT_COUNT CDC decode.
  // COMMIT_COUNT increments in sched_clk domain; its Gray-coded image crosses
  // into s_axi_aclk through a 2-FF synchronizer chain and is decoded here.
  // Algorithm: copy the MSB directly, then recover each lower bit as XOR of
  // the next higher decoded bit and the current Gray bit.
  function [31:0] gray2bin32;
    input [31:0] g;
    integer i;
    begin
      gray2bin32[31] = g[31];
      for (i = 30; i >= 0; i = i - 1)
        gray2bin32[i] = gray2bin32[i+1] ^ g[i];
    end
  endfunction

  // Interrupt: level-high while any enabled IRQ bit is pending
  assign irq = |(irq_status_axi[3:0] & irq_enable_reg[3:0]);

  // ---------------------------------------------------------------------------
  // AXI-Lite register interface (s_axi_aclk domain)
  // ---------------------------------------------------------------------------
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_awready      <= 1'b1;
      s_axi_wready       <= 1'b1;
      s_axi_bresp        <= 2'b00;
      s_axi_bvalid       <= 1'b0;
      s_axi_arready      <= 1'b1;
      s_axi_rdata        <= 32'h0;
      s_axi_rresp        <= 2'b00;
      s_axi_rvalid       <= 1'b0;
      scratch_reg        <= 32'h0;
      irq_en_reg         <= 1'b0;
      irq_enable_reg     <= 32'h0;
      irq_status_axi     <= 32'h0;
      event_count_cfg    <= 32'h0;
      evt_waddr_reg      <= {EVENT_MEM_ADDR_WIDTH{1'b0}};
      evt_wdata0_reg     <= 32'h0;
      evt_wdata1_reg     <= 32'h0;
      evt_wdata2_reg     <= 32'h0;
      evt_wdata3_reg     <= 32'h0;
      evt_wdata4_reg     <= 32'h0;
      evt_wdata5_reg     <= 32'h0;
      evt_wdata6_reg     <= 32'h0;
      arm_req_tgl        <= 1'b0;
      run_req_tgl        <= 1'b0;
      stop_req_tgl       <= 1'b0;
      sreset_req_tgl     <= 1'b0;
      event_wr_req_tgl   <= 1'b0;
      event_wr_addr_cfg  <= {EVENT_MEM_ADDR_WIDTH{1'b0}};
      event_wr_data_cfg  <= 256'h0;
      status_shadow      <= 32'h0;
      last_exec_shadow   <= 64'h0;
      commit_count_shadow <= 32'h0;
      cur_event_shadow   <= 32'h0;
      commit_count_gray_sync1 <= 32'h0;
      commit_count_gray_sync2 <= 32'h0;
      status_snap_sync1  <= 1'b0;
      status_snap_sync2  <= 1'b0;
      status_snap_sync2_d <= 1'b0;
      event_wr_ack_sync1 <= 1'b0;
      event_wr_ack_sync2 <= 1'b0;
      event_wr_ack_sync2_d <= 1'b0;
      time_now_lo_s1     <= 32'h0;
      time_now_lo_s2     <= 32'h0;
      time_now_hi_s1     <= 32'h0;
      time_now_hi_s2     <= 32'h0;
    end else begin
      // AXI B-channel drain
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      // -----------------------------------------------------------------------
      // Write path
      // -----------------------------------------------------------------------
      if (write_fire && !s_axi_bvalid) begin
        s_axi_bvalid <= 1'b1;
        case (s_axi_awaddr)
          REG_IP_SCRATCH: begin
            if (s_axi_wstrb[0]) scratch_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) scratch_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) scratch_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) scratch_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_CTRL: begin
            // [3:0] are write-1-to-pulse command bits (auto-clear on readback)
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) run_req_tgl    <= ~run_req_tgl;
              if (s_axi_wdata[1]) arm_req_tgl    <= ~arm_req_tgl;
              if (s_axi_wdata[2]) stop_req_tgl   <= ~stop_req_tgl;
              if (s_axi_wdata[3]) sreset_req_tgl <= ~sreset_req_tgl;
            end
            // [8] = irq_en is sticky RW
            if (s_axi_wstrb[1]) irq_en_reg <= s_axi_wdata[8];
          end
          REG_EVENT_COUNT: begin
            // Only accept writes when engine is idle (not armed/running)
            if (!status_shadow[0] && !status_shadow[1]) begin
              if (s_axi_wstrb[0]) event_count_cfg[7:0]   <= s_axi_wdata[7:0];
              if (s_axi_wstrb[1]) event_count_cfg[15:8]  <= s_axi_wdata[15:8];
              if (s_axi_wstrb[2]) event_count_cfg[23:16] <= s_axi_wdata[23:16];
              if (s_axi_wstrb[3]) event_count_cfg[31:24] <= s_axi_wdata[31:24];
            end
          end
          REG_IRQ_STATUS: begin
            // RW1C: writing a 1 to a bit clears it
            if (s_axi_wstrb[0]) irq_status_axi[7:0] <= irq_status_axi[7:0] & ~s_axi_wdata[7:0];
          end
          REG_IRQ_ENABLE: begin
            if (s_axi_wstrb[0]) irq_enable_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) irq_enable_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) irq_enable_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) irq_enable_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WADDR: begin
            evt_waddr_reg <= s_axi_wdata[EVENT_MEM_ADDR_WIDTH-1:0];
          end
          REG_EVT_WDATA0: begin
            if (s_axi_wstrb[0]) evt_wdata0_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata0_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata0_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata0_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA1: begin
            if (s_axi_wstrb[0]) evt_wdata1_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata1_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata1_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata1_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA2: begin
            if (s_axi_wstrb[0]) evt_wdata2_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata2_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata2_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata2_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA3: begin
            if (s_axi_wstrb[0]) evt_wdata3_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata3_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata3_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata3_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA4: begin
            if (s_axi_wstrb[0]) evt_wdata4_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata4_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata4_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata4_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA5: begin
            if (s_axi_wstrb[0]) evt_wdata5_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata5_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata5_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata5_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WDATA6: begin
            if (s_axi_wstrb[0]) evt_wdata6_reg[7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) evt_wdata6_reg[15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) evt_wdata6_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) evt_wdata6_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVT_WCTRL: begin
            if (s_axi_wstrb[0] && s_axi_wdata[0]) begin
              event_wr_addr_cfg <= evt_waddr_reg;
              // Pack 256-bit event word:
              //  [31:0]   = EVT_WDATA0 = timestamp[31:0]
              //  [63:32]  = EVT_WDATA1 = timestamp[63:32]
              //  [95:64]  = EVT_WDATA2 (event RAM) = {flags[15:0], channel[15:0]}
              //             AXI write view: WDATA2[31:16]=channel, WDATA2[15:0]=flags
              //             Event RAM view: [95:80]=flags, [79:64]=channel
              //             Swap halves here to convert AXI write ordering into
              //             event RAM ordering.
              //  [127:96] = EVT_WDATA3 = payload[31:0]
              //  [159:128]= EVT_WDATA4 = payload[63:32]
              //  [191:160]= EVT_WDATA5 = payload[95:64]
              //  [223:192]= EVT_WDATA6 = payload[127:96]
              //  [255:224]= 0 (reserved)
              event_wr_data_cfg <= {32'h0,
                                    evt_wdata6_reg,
                                    evt_wdata5_reg,
                                    evt_wdata4_reg,
                                    evt_wdata3_reg,
                                    {evt_wdata2_reg[15:0], evt_wdata2_reg[31:16]},
                                    evt_wdata1_reg,
                                    evt_wdata0_reg};
              event_wr_req_tgl <= ~event_wr_req_tgl;
            end
          end
          default: ;
        endcase
      end

      // -----------------------------------------------------------------------
      // Read path
      // -----------------------------------------------------------------------
      if (read_fire && !s_axi_rvalid) begin
        s_axi_rvalid <= 1'b1;
        case (s_axi_araddr)
          // CTRL: pulse bits always read 0; only irq_en is sticky
          REG_CTRL:         s_axi_rdata <= {23'h0, irq_en_reg, 8'h0};
          REG_STATUS:       s_axi_rdata <= status_shadow;
          REG_EVENT_COUNT:  s_axi_rdata <= event_count_cfg;
          REG_CUR_EVENT:    s_axi_rdata <= cur_event_shadow;
          REG_ERR_REG:      s_axi_rdata <= {24'h0, status_shadow[15:8]};
          REG_IP_ID:        s_axi_rdata <= IP_ID_VAL;
          REG_IP_VERSION:   s_axi_rdata <= IP_VERSION_VAL;
          REG_IP_CAPS:      s_axi_rdata <= IP_CAPS_VAL;
          REG_TIME_NOW_LO:  s_axi_rdata <= time_now_lo_s2;
          REG_TIME_NOW_HI:  s_axi_rdata <= time_now_hi_s2;
          REG_LAST_EXEC_LO: s_axi_rdata <= last_exec_shadow[31:0];
          REG_LAST_EXEC_HI: s_axi_rdata <= last_exec_shadow[63:32];
          REG_COMMIT_COUNT: s_axi_rdata <= commit_count_shadow;
          REG_REINIT_COUNT: s_axi_rdata <= 32'h0;
          REG_REINIT_REJECT:s_axi_rdata <= 32'h0;
          REG_IRQ_STATUS:   s_axi_rdata <= irq_status_axi;
          REG_IP_SCRATCH:   s_axi_rdata <= scratch_reg;
          REG_IRQ_ENABLE:   s_axi_rdata <= irq_enable_reg;
          REG_EVT_WADDR:    s_axi_rdata <= {{(32-EVENT_MEM_ADDR_WIDTH){1'b0}}, evt_waddr_reg};
          REG_EVT_WDATA0:   s_axi_rdata <= evt_wdata0_reg;
          REG_EVT_WDATA1:   s_axi_rdata <= evt_wdata1_reg;
          REG_EVT_WDATA2:   s_axi_rdata <= evt_wdata2_reg;
          REG_EVT_WDATA3:   s_axi_rdata <= evt_wdata3_reg;
          REG_EVT_WDATA4:   s_axi_rdata <= evt_wdata4_reg;
          REG_EVT_WDATA5:   s_axi_rdata <= evt_wdata5_reg;
          REG_EVT_WDATA6:   s_axi_rdata <= evt_wdata6_reg;
          default:          s_axi_rdata <= 32'h0;
        endcase
      end

      // -----------------------------------------------------------------------
      // CDC: sched -> AXI
      // -----------------------------------------------------------------------
      // Status snapshot toggle sync
      status_snap_sync1   <= status_snap_tgl;
      status_snap_sync2   <= status_snap_sync1;
      status_snap_sync2_d <= status_snap_sync2;
      if (status_snap_sync2 ^ status_snap_sync2_d) begin
        status_shadow       <= status_sched_snap;
        last_exec_shadow    <= last_exec_sched_snap;
        cur_event_shadow    <= cur_event_snap;
        // OR in new IRQ bits (accumulate; AXI clears via RW1C write)
        irq_status_axi      <= irq_status_axi | {28'h0, irq_snap};
      end

      // Commit-count CDC via Gray-coded synchronizer chain.
      // This avoids lost updates when status_snap_tgl edges coalesce.
      commit_count_gray_sync1 <= commit_count_gray_sched;
      commit_count_gray_sync2 <= commit_count_gray_sync1;
      commit_count_shadow     <= gray2bin32(commit_count_gray_sync2);

      // Event-write ack (only used for future event_count tracking)
      event_wr_ack_sync1   <= event_wr_ack_tgl;
      event_wr_ack_sync2   <= event_wr_ack_sync1;
      event_wr_ack_sync2_d <= event_wr_ack_sync2;

      // TIME_NOW best-effort sync (debug readback, potential 1-count glitch at wrap)
      time_now_lo_s1 <= sched_time_counter[31:0];
      time_now_lo_s2 <= time_now_lo_s1;
      time_now_hi_s1 <= sched_time_counter[63:32];
      time_now_hi_s2 <= time_now_hi_s1;
    end
  end

  // ---------------------------------------------------------------------------
  // Scheduler engine (sched_clk domain)
  // ---------------------------------------------------------------------------

  // BRAM registered read: 1-cycle latency.
  // fetch_data always tracks event_mem[read_ptr]; WAIT_FETCH absorbs the latency.
  always @(posedge sched_clk) begin
    fetch_data <= event_mem[read_ptr[EVENT_MEM_ADDR_WIDTH-1:0]];
  end

  // Convenience task-like macro for the common "snapshot and toggle" operation.
  // (Implemented inline below as it is not a large repeated body.)

  always @(posedge sched_clk) begin
    if (sched_reset) begin
      // Sched-domain synchronous reset
      // (event_mem is NOT reset here; BRAM relies on power-up initialisation)
      arm_req_sync1    <= 1'b0;
      arm_req_sync2    <= 1'b0;
      arm_req_sync2_d  <= 1'b0;
      run_req_sync1    <= 1'b0;
      run_req_sync2    <= 1'b0;
      run_req_sync2_d  <= 1'b0;
      stop_req_sync1   <= 1'b0;
      stop_req_sync2   <= 1'b0;
      stop_req_sync2_d <= 1'b0;
      sreset_req_sync1   <= 1'b0;
      sreset_req_sync2   <= 1'b0;
      sreset_req_sync2_d <= 1'b0;
      event_wr_req_sync1   <= 1'b0;
      event_wr_req_sync2   <= 1'b0;
      event_wr_req_sync2_d <= 1'b0;
      event_count_s1   <= 32'h0;
      event_count_s2   <= 32'h0;
      status_snap_tgl  <= 1'b0;
      event_wr_ack_tgl <= 1'b0;
      sched_time_counter  <= 64'h0;
      engine_state        <= ENGINE_IDLE;
      event_count_sched   <= 32'h0;
      read_ptr            <= 32'h0;
      last_exec_sched     <= 64'h0;
      commit_count_sched  <= 32'h0;
      commit_count_gray_sched <= 32'h0;
      prev_ts             <= 64'h0;
      error_code          <= ERR_NONE;
      irq_sched           <= 4'h0;
      compare_first       <= 1'b0;
      marker_commit       <= 1'b0;
      marker_start        <= 1'b0;
      marker_done         <= 1'b0;
      status_sched_snap   <= 32'h0;
      last_exec_sched_snap <= 64'h0;
      cur_event_snap      <= 32'h0;
      irq_snap            <= 4'h0;
    end else begin
      sched_time_counter <= sched_time_counter + 1'b1;

      // Clear one-cycle pulse outputs
      marker_commit <= 1'b0;
      marker_start  <= 1'b0;
      marker_done   <= 1'b0;

      // -------------------------------------------------------------------
      // CDC sync chains: AXI -> sched
      // -------------------------------------------------------------------
      arm_req_sync1    <= arm_req_tgl;
      arm_req_sync2    <= arm_req_sync1;
      arm_req_sync2_d  <= arm_req_sync2;

      run_req_sync1    <= run_req_tgl;
      run_req_sync2    <= run_req_sync1;
      run_req_sync2_d  <= run_req_sync2;

      stop_req_sync1   <= stop_req_tgl;
      stop_req_sync2   <= stop_req_sync1;
      stop_req_sync2_d <= stop_req_sync2;

      sreset_req_sync1   <= sreset_req_tgl;
      sreset_req_sync2   <= sreset_req_sync1;
      sreset_req_sync2_d <= sreset_req_sync2;

      event_wr_req_sync1   <= event_wr_req_tgl;
      event_wr_req_sync2   <= event_wr_req_sync1;
      event_wr_req_sync2_d <= event_wr_req_sync2;

      // event_count_cfg 2-FF direct sync (stable well before ARM fires)
      event_count_s1 <= event_count_cfg;
      event_count_s2 <= event_count_s1;

      // -------------------------------------------------------------------
      // Command edge detection (priority: sreset > stop > arm/run > engine)
      // -------------------------------------------------------------------
      if (sreset_req_sync2 ^ sreset_req_sync2_d) begin
        // Soft reset: clear engine and all counters
        engine_state       <= ENGINE_IDLE;
        read_ptr           <= 32'h0;
        commit_count_sched <= 32'h0;
        commit_count_gray_sched <= 32'h0;
        irq_sched          <= 4'h0;
        error_code         <= ERR_NONE;
        prev_ts            <= 64'h0;
        // Send cleared status snapshot to AXI domain
        status_sched_snap   <= 32'h0;
        cur_event_snap      <= 32'h0;
        irq_snap            <= 4'h0;
        last_exec_sched_snap <= last_exec_sched;
        status_snap_tgl     <= ~status_snap_tgl;

      end else if (stop_req_sync2 ^ stop_req_sync2_d) begin
        // Stop: abort execution, return to IDLE (does not clear counters)
        engine_state        <= ENGINE_IDLE;
        status_sched_snap   <= 32'h0;
        cur_event_snap      <= read_ptr;
        irq_snap            <= irq_sched;
        last_exec_sched_snap <= last_exec_sched;
        status_snap_tgl     <= ~status_snap_tgl;

      end else begin
        // -------------------------------------------------------------------
        // ARM/RUN edge handling.
        // If both edges arrive in the same cycle while IDLE, transition
        // directly to WAIT_FETCH (or ARMED if event_count is zero).
        // -------------------------------------------------------------------
        if (arm_edge && run_edge) begin
          if (engine_state == ENGINE_IDLE) begin
            event_count_sched <= event_count_s2;
            if (event_count_s2 > 0) begin
              read_ptr       <= 32'h0;
              prev_ts        <= 64'h0;
              engine_state   <= ENGINE_WAIT_FETCH;
              marker_start   <= 1'b1;
              // Snapshot: running=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b1, 1'b0};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;
            end else begin
              engine_state      <= ENGINE_ARMED;
              // Snapshot: armed=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b0, 1'b1};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;
            end
          end
        end else begin
          if (arm_edge) begin
            if (engine_state == ENGINE_IDLE) begin
              event_count_sched <= event_count_s2;
              engine_state      <= ENGINE_ARMED;
              // Snapshot: armed=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b0, 1'b1};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;
            end
          end

          // -------------------------------------------------------------------
          // RUN edge: ARMED -> WAIT_FETCH (starts execution)
          // -------------------------------------------------------------------
          if (run_edge) begin
            if (engine_state == ENGINE_ARMED && event_count_sched > 0) begin
              read_ptr       <= 32'h0;
              prev_ts        <= 64'h0;
              engine_state   <= ENGINE_WAIT_FETCH;
              marker_start   <= 1'b1;
              // Snapshot: running=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b1, 1'b0};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;
            end
          end
        end

        // -------------------------------------------------------------------
        // Engine state machine
        // -------------------------------------------------------------------
        case (engine_state)
          ENGINE_IDLE:  ;   // waiting for ARM

          ENGINE_ARMED: ;   // waiting for RUN

          ENGINE_WAIT_FETCH: begin
            // Present read_ptr to BRAM; fetch_data valid next cycle (COMPARE).
            compare_first <= 1'b1;
            engine_state  <= ENGINE_COMPARE;
          end

          ENGINE_COMPARE: begin
            compare_first <= 1'b0;
            // Priority: missed-deadline check (first cycle only) > fire-or-wait.
            // compare_first gates this check so we only classify "already late at
            // fetch time", not while waiting for a future due timestamp.
            if (compare_first && ev_ts < sched_time_counter) begin
              // Missed deadline: timestamp was already in the past on arrival
              error_code          <= ERR_MISSED_DEADLINE;
              irq_sched[IRQ_ERROR]  <= 1'b1;
              irq_sched[IRQ_UNDERRUN] <= 1'b1;
              engine_state        <= ENGINE_ERROR;
              status_sched_snap   <= {16'h0, ERR_MISSED_DEADLINE, 12'h0,
                                      1'b1, 1'b0, 1'b0, 1'b0};
              cur_event_snap      <= read_ptr;
              // IRQ_UNDERRUN=bit3, IRQ_ERROR=bit1  -> 4'b1010
              irq_snap            <= irq_sched | 4'b1010;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;

            end else if (ev_ts <= sched_time_counter) begin
              // Timestamp reached: check spacing before firing
              if (read_ptr > 0 &&
                  (ev_ts - prev_ts) < MIN_SPACING_VAL) begin
                error_code          <= ERR_SPACING_VIOLATION;
                irq_sched[IRQ_ERROR]             <= 1'b1;
                irq_sched[IRQ_SPACING_VIOLATION] <= 1'b1;
                engine_state        <= ENGINE_ERROR;
                status_sched_snap   <= {16'h0, ERR_SPACING_VIOLATION, 12'h0,
                                        1'b1, 1'b0, 1'b0, 1'b0};
                cur_event_snap      <= read_ptr;
                irq_snap            <= irq_sched | 4'b0110;
                last_exec_sched_snap <= last_exec_sched;
                status_snap_tgl     <= ~status_snap_tgl;
              end else begin
                engine_state <= ENGINE_FIRE;
              end
            end
            // else: ev_ts > sched_time_counter -> keep waiting
          end

          ENGINE_FIRE: begin
            // Apply the event: pulse marker_commit, record telemetry
            marker_commit      <= 1'b1;
            commit_count_sched <= commit_count_next;
            commit_count_gray_sched <= commit_count_next_gray;
            last_exec_sched    <= ev_ts;
            prev_ts            <= ev_ts;
            // Snapshot every FIRE so firmware polling sees progress before DONE.
            status_sched_snap    <= {16'h0, ERR_NONE, 12'h0,
                                     1'b0, 1'b0, 1'b1, 1'b0};
            cur_event_snap       <= cur_event_next;
            irq_snap             <= irq_sched;
            last_exec_sched_snap <= ev_ts;
            status_snap_tgl      <= ~status_snap_tgl;
            engine_state       <= ENGINE_ADVANCE;
          end

          ENGINE_ADVANCE: begin
            if (read_ptr >= event_count_sched - 1) begin
              // All events have been fired
              irq_sched[IRQ_DONE] <= 1'b1;
              engine_state        <= ENGINE_DONE;
              marker_done         <= 1'b1;
              // Final snapshot: done=1.
              // commit_count_sched already carries the post-FIRE increment;
              // last_exec_sched was updated to ev_ts in ENGINE_FIRE.
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0,
                                      1'b0, 1'b1, 1'b0, 1'b0};
              cur_event_snap      <= cur_event_next;
              irq_snap            <= irq_sched | 4'b0001;
              last_exec_sched_snap <= last_exec_sched;
              status_snap_tgl     <= ~status_snap_tgl;
            end else begin
              read_ptr     <= read_ptr + 1'b1;
              engine_state <= ENGINE_WAIT_FETCH;
            end
          end

          ENGINE_DONE:  ;   // terminal; firmware must stop/reset to reuse

          ENGINE_ERROR: ;   // terminal; firmware must stop/reset to recover

          default: engine_state <= ENGINE_IDLE;
        endcase
      end  // !stop and !sreset

      // -------------------------------------------------------------------
      // Event write (independent of engine state; any time not in flight)
      // -------------------------------------------------------------------
      if (event_wr_req_sync2 ^ event_wr_req_sync2_d) begin
        event_mem[event_wr_addr_cfg] <= event_wr_data_cfg;
        event_wr_ack_tgl <= ~event_wr_ack_tgl;
      end

    end  // !sched_reset
  end

endmodule
