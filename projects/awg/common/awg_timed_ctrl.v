// awg_timed_ctrl.v -- AWG timed-control AXI-Lite peripheral
`timescale 1ns/1ps
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
//   0x34  REINIT_COUNT  RO  number of successful PHASE_REINIT events
//   0x38  REINIT_REJECT RO  number of rejected PHASE_REINIT events
//   0x3C  IRQ_STATUS    RW1C [0]=done, [1]=error, [2]=spacing_violation, [3]=underrun,
//                            [4]=low_watermark, [5]=empty_stall
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
//   0x6C  TIME_RELOAD_LO   RW  pending scheduler epoch reload value [31:0]
//   0x70  TIME_RELOAD_HI   RW  pending scheduler epoch reload value [63:32]
//   0x74  TIME_RELOAD_CTRL RW  [0]=load on next SYSREF, [1]=load now (pulse)
//   0x78  STREAM_CTRL    RW  [0]=mode_stream, [1]=write_overflow_sticky (W1C),
//                           [2]=eof_seen (RO), [3]=dma_mode
//   0x7C  OCCUPANCY      RO  stream FIFO occupancy in events
//   0x80  FREE_SPACE     RO  stream FIFO free space in events
//   0x84  LOW_WMARK      RW  stream FIFO low-watermark threshold in events
//   0x88  STREAM_DEPTH   RO  stream FIFO usable depth in events
//   0x8C  STREAM_PUSHES  RO  accepted stream-event pushes
//   0x90  STREAM_STALLS  RO  cycles spent waiting on an empty stream FIFO
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
// Future quality gates:
//   Cocotb directed tests, SBY liveness, IP-XACT packaging

module awg_timed_ctrl #(
  parameter integer EVENT_MEM_ADDR_WIDTH = 8,
  parameter integer STREAM_ADDR_WIDTH    = 9,
  parameter integer MIN_SPACING_TICKS    = 8,
  parameter integer NUM_CHANNELS         = 8,
  parameter integer DDS_PHASE_DW         = 32
) (
  // AXI4-Lite slave
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:dma_s_axis, ASSOCIATED_RESET s_axi_aresetn" *)
  input  wire        s_axi_aclk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire        s_axi_aresetn,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR" *)
  input  wire [7:0]  s_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWPROT" *)
  input  wire [2:0]  s_axi_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *)
  input  wire        s_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *)
  output reg         s_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA" *)
  input  wire [31:0] s_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB" *)
  input  wire [3:0]  s_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID" *)
  input  wire        s_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY" *)
  output reg         s_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP" *)
  output reg  [1:0]  s_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID" *)
  output reg         s_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY" *)
  input  wire        s_axi_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR" *)
  input  wire [7:0]  s_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARPROT" *)
  input  wire [2:0]  s_axi_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *)
  input  wire        s_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *)
  output reg         s_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA" *)
  output reg  [31:0] s_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP" *)
  output reg  [1:0]  s_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID" *)
  output reg         s_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY" *)
  input  wire        s_axi_rready,
  // DMA-backed stream ingress (s_axi_aclk domain)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_s_axis TDATA" *)
  input  wire [255:0] dma_s_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_s_axis TVALID" *)
  input  wire         dma_s_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_s_axis TREADY" *)
  output wire         dma_s_axis_tready,
  // Scheduler clock domain
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sched_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET sched_reset" *)
  input  wire        sched_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 sched_reset RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
  input  wire        sched_reset,
  (* X_INTERFACE_IGNORE = "true" *)
  input  wire        sysref_pulse,
  // Marker outputs (sched_clk domain, 1-cycle active-high pulses)
  (* X_INTERFACE_IGNORE = "true" *)
  output reg         marker_commit,  // pulses once per fired event
  (* X_INTERFACE_IGNORE = "true" *)
  output reg         marker_start,   // pulses when engine begins execution
  (* X_INTERFACE_IGNORE = "true" *)
  output reg         marker_done,    // pulses when all events complete
  (* X_INTERFACE_IGNORE = "true" *)
  output reg  [NUM_CHANNELS*16-1:0]           sched_scale_s,
  (* X_INTERFACE_IGNORE = "true" *)
  output reg  [NUM_CHANNELS*DDS_PHASE_DW-1:0] sched_init_s,
  (* X_INTERFACE_IGNORE = "true" *)
  output reg  [NUM_CHANNELS*DDS_PHASE_DW-1:0] sched_incr_s,
  (* X_INTERFACE_IGNORE = "true" *)
  output reg  [NUM_CHANNELS-1:0]              sched_apply_s,
  (* X_INTERFACE_IGNORE = "true" *)
  output reg                                  sched_phase_reinit,
  // Interrupt (s_axi_aclk domain, level-high while pending & enabled)
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
  (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
  output wire        irq
);

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------
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
  localparam [7:0] REG_TIME_RELOAD_LO   = 8'h6C;
  localparam [7:0] REG_TIME_RELOAD_HI   = 8'h70;
  localparam [7:0] REG_TIME_RELOAD_CTRL = 8'h74;
  localparam [7:0] REG_STREAM_CTRL      = 8'h78;
  localparam [7:0] REG_OCCUPANCY        = 8'h7C;
  localparam [7:0] REG_FREE_SPACE       = 8'h80;
  localparam [7:0] REG_LOW_WMARK        = 8'h84;
  localparam [7:0] REG_STREAM_DEPTH     = 8'h88;
  localparam [7:0] REG_STREAM_PUSHES    = 8'h8C;
  localparam [7:0] REG_STREAM_STALLS    = 8'h90;
  localparam integer TIME_RELOAD_CTRL_ARM_ON_SYSREF = 0;
  localparam integer TIME_RELOAD_CTRL_LOAD_NOW      = 1;
  localparam integer STREAM_CTRL_MODE_STREAM         = 0;
  localparam integer STREAM_CTRL_WRITE_OVERFLOW      = 1;
  localparam integer STREAM_CTRL_EOF_SEEN            = 2;
  localparam integer STREAM_CTRL_DMA_MODE            = 3;
  localparam [31:0] STREAM_DEPTH_USABLE              = ((32'h1 << STREAM_ADDR_WIDTH) - 1);

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
  localparam IRQ_LOW_WATERMARK     = 4;
  localparam IRQ_EMPTY_STALL       = 5;

  // Error codes (placed in STATUS[15:8])
  localparam [7:0] ERR_NONE              = 8'h00;
  localparam [7:0] ERR_MISSED_DEADLINE   = 8'h01;
  localparam [7:0] ERR_SPACING_VIOLATION = 8'h02;
  localparam [7:0] ERR_REINIT_SPACING    = 8'h03;

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
  reg [31:0] time_reload_lo_reg;
  reg [31:0] time_reload_hi_reg;
  reg [31:0] time_reload_ctrl_reg;
  reg        mode_stream_cfg_reg;
  reg        mode_stream_locked_reg;
  reg        dma_mode_cfg_reg;
  reg        dma_mode_locked_reg;
  reg        write_overflow_sticky_reg;
  reg [31:0] low_wmark_reg;
  reg [31:0] stream_pushes_reg;
  reg        aw_captured;
  reg [7:0]  awaddr_captured;
  reg        w_captured;
  reg [31:0] wdata_captured;
  reg [3:0]  wstrb_captured;
  reg [EVENT_MEM_ADDR_WIDTH-1:0] evt_waddr_reg;
  reg [31:0] evt_wdata0_reg, evt_wdata1_reg, evt_wdata2_reg;
  reg [31:0] evt_wdata3_reg, evt_wdata4_reg, evt_wdata5_reg, evt_wdata6_reg;

  // AXI shadow registers (captured from sched status snapshots)
  reg [31:0] status_shadow;
  reg [63:0] last_exec_shadow;
  reg [31:0] commit_count_shadow;
  reg [31:0] reinit_count_shadow;
  reg [31:0] reinit_reject_shadow;
  reg [31:0] stream_stalls_shadow;
  reg [31:0] cur_event_shadow;
  reg        eof_seen_shadow;
  reg        mode_stream_active_shadow;
  reg        stream_hold_valid_sync1;
  reg        stream_hold_valid_shadow;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] commit_count_gray_sync1, commit_count_gray_sync2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] reinit_count_gray_sync1, reinit_count_gray_sync2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] reinit_reject_gray_sync1, reinit_reject_gray_sync2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] stream_stalls_gray_sync1, stream_stalls_gray_sync2;

  // TIME_NOW best-effort 2-FF sync (debug only)
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] time_now_lo_s1, time_now_lo_s2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] time_now_hi_s1, time_now_hi_s2;

  // ---------------------------------------------------------------------------
  // CDC: AXI -> sched (toggle synchronizers)
  // ---------------------------------------------------------------------------
  // Toggle regs toggled by AXI writes; synced in sched domain
  reg arm_req_tgl, run_req_tgl, stop_req_tgl, sreset_req_tgl;
  reg load_sysref_req_tgl, load_now_req_tgl;
  reg stream_flush_req_tgl;
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
  reg [5:0]  irq_snap;
  reg        eof_seen_sched_snap;
  reg        mode_stream_sched_snap;

  // ---------------------------------------------------------------------------
  // AXI-domain CDC sync chains
  // ---------------------------------------------------------------------------
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg status_snap_sync1,   status_snap_sync2;
  reg status_snap_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg event_wr_ack_sync1,  event_wr_ack_sync2;
  reg event_wr_ack_sync2_d;

  // ---------------------------------------------------------------------------
  // Sched-domain CDC sync chains
  // ---------------------------------------------------------------------------
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg arm_req_sync1,    arm_req_sync2;
  reg arm_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg run_req_sync1,    run_req_sync2;
  reg run_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg stop_req_sync1,   stop_req_sync2;
  reg stop_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg sreset_req_sync1, sreset_req_sync2;
  reg sreset_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg load_sysref_req_sync1, load_sysref_req_sync2;
  reg load_sysref_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg load_now_req_sync1, load_now_req_sync2;
  reg load_now_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg stream_flush_req_sync1, stream_flush_req_sync2;
  reg stream_flush_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg event_wr_req_sync1, event_wr_req_sync2;
  reg event_wr_req_sync2_d;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] time_reload_lo_s1, time_reload_lo_s2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] time_reload_hi_s1, time_reload_hi_s2;
  // event_count_cfg 2-FF direct sync to sched domain
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [31:0] event_count_s1, event_count_s2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg mode_stream_cfg_s1, mode_stream_cfg_s2;

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
  reg [31:0] reinit_count_sched;
  reg [31:0] reinit_count_gray_sched;
  reg [31:0] reinit_reject_sched;
  reg [31:0] reinit_reject_gray_sched;
  reg [31:0] stream_stalls_sched;
  reg [31:0] stream_stalls_gray_sched;
  reg [63:0] prev_ts;            // timestamp of previous fired event (spacing check)
  reg        prev_phase_reinit;
  reg [7:0]  error_code;
  reg [5:0]  irq_sched;          // sticky IRQ bits in sched domain
  reg        compare_first;      // high on the first cycle in ENGINE_COMPARE
  reg        time_reload_arm_sched;
  reg        mode_stream_sched;
  reg        stream_empty_waiting;
  reg        stream_below_wmark_sched;
  reg        eof_seen_sched;
  reg        stream_hold_valid;
  reg [1:0]  stream_fifo_m_reset_hold;
  reg [31:0] low_wmark_s1, low_wmark_s2;

  // BRAM: no synchronous reset; relies on power-up initialisation.
  // The (* ram_style = "block" *) attribute prevents Vivado inferring a
  // synchronous-reset for-loop over BRAM outputs (UltraScale BRAM does not
  // support a synchronous reset on the data output).
  (* ram_style = "block" *) reg [255:0] event_mem [0:(1 << EVENT_MEM_ADDR_WIDTH)-1];
  reg [255:0] fetch_data;   // registered BRAM output (1-cycle read latency)
  reg [255:0] stream_fetch_data; // latched stream event held across compare/fire/advance
  reg [1:0]   stream_fifo_s_reset_hold;

  wire [255:0] stream_event_word =
    {32'h0,
     evt_wdata6_reg,
     evt_wdata5_reg,
     evt_wdata4_reg,
     evt_wdata3_reg,
     {evt_wdata2_reg[15:0], evt_wdata2_reg[31:16]},
     evt_wdata1_reg,
     evt_wdata0_reg};

  wire        stream_fifo_s_aresetn = s_axi_aresetn && !stream_fifo_s_reset_hold[1];
  wire        stream_fifo_m_aresetn = !sched_reset && !stream_fifo_m_reset_hold[1];
  wire        stream_fifo_s_ready;
  wire        stream_fifo_s_full;
  wire        stream_fifo_s_almost_full;
  wire [STREAM_ADDR_WIDTH-1:0] stream_fifo_s_room;
  wire        stream_fifo_m_valid;
  wire        stream_fifo_m_empty;
  wire        stream_fifo_m_almost_empty;
  wire [STREAM_ADDR_WIDTH-1:0] stream_fifo_m_level;
  wire [255:0] stream_fifo_m_data;

  wire [31:0] stream_fifo_free_space_axi = {{(32-STREAM_ADDR_WIDTH){1'b0}}, stream_fifo_s_room};
  wire [31:0] stream_occupancy_axi = STREAM_DEPTH_USABLE - stream_fifo_free_space_axi;
  wire [31:0] low_wmark_eff = (low_wmark_reg > STREAM_DEPTH_USABLE) ? STREAM_DEPTH_USABLE : low_wmark_reg;
  wire [31:0] low_wmark_eff_sched = (low_wmark_s2 > STREAM_DEPTH_USABLE) ? STREAM_DEPTH_USABLE : low_wmark_s2;
  wire [31:0] stream_buffered_sched = {{(32-STREAM_ADDR_WIDTH){1'b0}}, stream_fifo_m_level} +
                                      {{31{1'b0}}, stream_hold_valid};
  wire        stream_prefetch_en =
    mode_stream_sched &&
    ((engine_state == ENGINE_WAIT_FETCH) ||
     (engine_state == ENGINE_COMPARE) ||
     (engine_state == ENGINE_FIRE) ||
     (engine_state == ENGINE_ADVANCE));
  wire        stream_fifo_m_ready = stream_prefetch_en && !stream_hold_valid;

  // ---------------------------------------------------------------------------
  // Combinational helpers
  // ---------------------------------------------------------------------------
  wire aw_fire = s_axi_awvalid && s_axi_awready;
  wire w_fire  = s_axi_wvalid && s_axi_wready;
  wire write_have_addr = aw_captured || aw_fire;
  wire write_have_data = w_captured || w_fire;
  wire write_issue = write_have_addr && write_have_data && !s_axi_bvalid;
  wire [7:0]  write_addr = aw_captured ? awaddr_captured : s_axi_awaddr;
  wire [31:0] write_data = w_captured ? wdata_captured : s_axi_wdata;
  wire [3:0]  write_strb = w_captured ? wstrb_captured : s_axi_wstrb;
  wire read_fire  = s_axi_arvalid && s_axi_arready;
  wire        stream_mode_write_sel =
    (status_shadow[0] || status_shadow[1]) ? mode_stream_locked_reg : mode_stream_cfg_reg;
  wire        dma_mode_write_sel =
    (status_shadow[0] || status_shadow[1]) ? dma_mode_locked_reg : dma_mode_cfg_reg;
  wire        dma_stream_write_sel = stream_mode_write_sel && dma_mode_write_sel;
  wire        stream_push_attempt =
    write_issue && (write_addr == REG_EVT_WCTRL) && write_strb[0] && write_data[0] &&
    stream_mode_write_sel && !dma_stream_write_sel;
  wire        legacy_push_attempt =
    write_issue && (write_addr == REG_EVT_WCTRL) && write_strb[0] && write_data[0] && !stream_mode_write_sel;
  wire        stream_fifo_s_accept = stream_fifo_s_aresetn && stream_fifo_s_ready;
  wire [255:0] stream_fifo_s_data = dma_stream_write_sel ? dma_s_axis_tdata : stream_event_word;
  wire        stream_fifo_s_valid = dma_stream_write_sel ? dma_s_axis_tvalid : stream_push_attempt;
  wire        dma_push_fire = dma_stream_write_sel && dma_s_axis_tvalid && stream_fifo_s_accept;
  wire        stream_push_fire = stream_push_attempt && stream_fifo_s_accept;

  assign dma_s_axis_tready = dma_stream_write_sel && stream_fifo_s_accept;

  wire [255:0] active_fetch_data = mode_stream_sched ? stream_fetch_data : fetch_data;

  // Current event fields decoded from the active fetch word.
  wire [63:0]  ev_ts      = active_fetch_data[63:0];
  wire [15:0]  ev_ch      = active_fetch_data[79:64];
  wire [15:0]  ev_flags   = active_fetch_data[95:80];
  wire [127:0] ev_payload = active_fetch_data[223:96];
  wire [31:0]  cur_event_next = read_ptr + 1'b1;
  wire [31:0]  commit_count_next = commit_count_sched + 1'b1;
  wire [31:0]  commit_count_next_gray = commit_count_next ^ (commit_count_next >> 1);
  wire [31:0]  reinit_count_next = reinit_count_sched + 1'b1;
  wire [31:0]  reinit_count_next_gray = reinit_count_next ^ (reinit_count_next >> 1);
  wire [31:0]  reinit_reject_next = reinit_reject_sched + 1'b1;
  wire [31:0]  reinit_reject_next_gray = reinit_reject_next ^ (reinit_reject_next >> 1);
  wire         reinit_spacing_violation = ev_flags[0] && prev_phase_reinit;
  wire [7:0]   spacing_error_code = reinit_spacing_violation ? 8'h03 : 8'h02;
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

  util_axis_fifo #(
    .DATA_WIDTH(256),
    .ADDRESS_WIDTH(STREAM_ADDR_WIDTH),
    .ASYNC_CLK(1),
    .M_AXIS_REGISTERED(1),
    .TLAST_EN(0),
    .TKEEP_EN(0)
  ) i_stream_fifo (
    .m_axis_aclk(sched_clk),
    .m_axis_aresetn(stream_fifo_m_aresetn),
    .m_axis_ready(stream_fifo_m_ready),
    .m_axis_valid(stream_fifo_m_valid),
    .m_axis_data(stream_fifo_m_data),
    .m_axis_tkeep(),
    .m_axis_tlast(),
    .m_axis_level(stream_fifo_m_level),
    .m_axis_empty(stream_fifo_m_empty),
    .m_axis_almost_empty(stream_fifo_m_almost_empty),
    .s_axis_aclk(s_axi_aclk),
    .s_axis_aresetn(stream_fifo_s_aresetn),
    .s_axis_ready(stream_fifo_s_ready),
    .s_axis_valid(stream_fifo_s_valid),
    .s_axis_data(stream_fifo_s_data),
    .s_axis_tkeep({32{1'b1}}),
    .s_axis_tlast(1'b0),
    .s_axis_room(stream_fifo_s_room),
    .s_axis_full(stream_fifo_s_full),
    .s_axis_almost_full(stream_fifo_s_almost_full)
  );

  // Interrupt: level-high while any enabled IRQ bit is pending
  assign irq = |(irq_status_axi[5:0] & irq_enable_reg[5:0]);

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
      time_reload_lo_reg <= 32'h0;
      time_reload_hi_reg <= 32'h0;
      time_reload_ctrl_reg <= 32'h0;
      mode_stream_cfg_reg <= 1'b0;
      mode_stream_locked_reg <= 1'b0;
      dma_mode_cfg_reg <= 1'b0;
      dma_mode_locked_reg <= 1'b0;
      write_overflow_sticky_reg <= 1'b0;
      low_wmark_reg      <= (STREAM_DEPTH_USABLE >> 2);
      stream_pushes_reg  <= 32'h0;
      aw_captured        <= 1'b0;
      awaddr_captured    <= 8'h0;
      w_captured         <= 1'b0;
      wdata_captured     <= 32'h0;
      wstrb_captured     <= 4'h0;
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
      load_sysref_req_tgl <= 1'b0;
      load_now_req_tgl   <= 1'b0;
      stream_flush_req_tgl <= 1'b0;
      event_wr_req_tgl   <= 1'b0;
      event_wr_addr_cfg  <= {EVENT_MEM_ADDR_WIDTH{1'b0}};
      event_wr_data_cfg  <= 256'h0;
      status_shadow      <= 32'h0;
      last_exec_shadow   <= 64'h0;
      commit_count_shadow <= 32'h0;
      reinit_count_shadow <= 32'h0;
      reinit_reject_shadow <= 32'h0;
      stream_stalls_shadow <= 32'h0;
      cur_event_shadow   <= 32'h0;
      eof_seen_shadow    <= 1'b0;
      mode_stream_active_shadow <= 1'b0;
      stream_hold_valid_sync1 <= 1'b0;
      stream_hold_valid_shadow <= 1'b0;
      commit_count_gray_sync1 <= 32'h0;
      commit_count_gray_sync2 <= 32'h0;
      reinit_count_gray_sync1 <= 32'h0;
      reinit_count_gray_sync2 <= 32'h0;
      reinit_reject_gray_sync1 <= 32'h0;
      reinit_reject_gray_sync2 <= 32'h0;
      stream_stalls_gray_sync1 <= 32'h0;
      stream_stalls_gray_sync2 <= 32'h0;
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
      stream_fifo_s_reset_hold <= 2'b11;
    end else begin
      if (stream_fifo_s_reset_hold != 2'b00)
        stream_fifo_s_reset_hold <= {stream_fifo_s_reset_hold[0], 1'b0};
      if (dma_push_fire)
        stream_pushes_reg <= stream_pushes_reg + 1'b1;

      // AXI B-channel drain
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid  <= 1'b0;
        s_axi_awready <= 1'b1;
        s_axi_wready  <= 1'b1;
      end
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      // -----------------------------------------------------------------------
      // Write path
      // -----------------------------------------------------------------------
      if (aw_fire) begin
        aw_captured     <= 1'b1;
        awaddr_captured <= s_axi_awaddr;
        s_axi_awready   <= 1'b0;
      end

      if (w_fire) begin
        w_captured     <= 1'b1;
        wdata_captured <= s_axi_wdata;
        wstrb_captured <= s_axi_wstrb;
        s_axi_wready   <= 1'b0;
      end

      if (write_issue) begin
        s_axi_bvalid <= 1'b1;
        aw_captured  <= 1'b0;
        w_captured   <= 1'b0;
        case (write_addr)
          REG_IP_SCRATCH: begin
            if (write_strb[0]) scratch_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) scratch_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) scratch_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) scratch_reg[31:24] <= write_data[31:24];
          end
          REG_CTRL: begin
            // [3:0] are write-1-to-pulse command bits (auto-clear on readback)
            if (write_strb[0]) begin
              if (write_data[0]) run_req_tgl    <= ~run_req_tgl;
              if (write_data[1]) begin
                arm_req_tgl <= ~arm_req_tgl;
                mode_stream_locked_reg <= mode_stream_cfg_reg;
                dma_mode_locked_reg <= dma_mode_cfg_reg;
              end
              if (write_data[2]) stop_req_tgl   <= ~stop_req_tgl;
              if (write_data[3]) sreset_req_tgl <= ~sreset_req_tgl;
            end
            // [8] = irq_en is sticky RW
            if (write_strb[1]) irq_en_reg <= write_data[8];
          end
          REG_EVENT_COUNT: begin
            // Only accept writes when engine is idle (not armed/running)
            if (!status_shadow[0] && !status_shadow[1]) begin
              if (write_strb[0]) event_count_cfg[7:0]   <= write_data[7:0];
              if (write_strb[1]) event_count_cfg[15:8]  <= write_data[15:8];
              if (write_strb[2]) event_count_cfg[23:16] <= write_data[23:16];
              if (write_strb[3]) event_count_cfg[31:24] <= write_data[31:24];
            end
          end
          REG_TIME_RELOAD_LO: begin
            if (write_strb[0]) time_reload_lo_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) time_reload_lo_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) time_reload_lo_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) time_reload_lo_reg[31:24] <= write_data[31:24];
          end
          REG_TIME_RELOAD_HI: begin
            if (write_strb[0]) time_reload_hi_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) time_reload_hi_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) time_reload_hi_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) time_reload_hi_reg[31:24] <= write_data[31:24];
          end
          REG_TIME_RELOAD_CTRL: begin
            if (write_strb[0]) begin
              time_reload_ctrl_reg[TIME_RELOAD_CTRL_ARM_ON_SYSREF] <= write_data[TIME_RELOAD_CTRL_ARM_ON_SYSREF];
            end
            // Re-arm is intentionally level-insensitive: each write-1 issues a
            // fresh arm request even if software previously left CTRL[0]=1.
            if (write_strb[0] && write_data[TIME_RELOAD_CTRL_ARM_ON_SYSREF])
              load_sysref_req_tgl <= ~load_sysref_req_tgl;
            if (write_strb[0] && write_data[TIME_RELOAD_CTRL_LOAD_NOW])
              load_now_req_tgl    <= ~load_now_req_tgl;
          end
          REG_IRQ_STATUS: begin
            // RW1C: writing a 1 to a bit clears it
            if (write_strb[0]) irq_status_axi[7:0] <= irq_status_axi[7:0] & ~write_data[7:0];
          end
          REG_IRQ_ENABLE: begin
            if (write_strb[0]) irq_enable_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) irq_enable_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) irq_enable_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) irq_enable_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WADDR: begin
            evt_waddr_reg <= write_data[EVENT_MEM_ADDR_WIDTH-1:0];
          end
          REG_EVT_WDATA0: begin
            if (write_strb[0]) evt_wdata0_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata0_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata0_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata0_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA1: begin
            if (write_strb[0]) evt_wdata1_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata1_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata1_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata1_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA2: begin
            if (write_strb[0]) evt_wdata2_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata2_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata2_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata2_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA3: begin
            if (write_strb[0]) evt_wdata3_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata3_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata3_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata3_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA4: begin
            if (write_strb[0]) evt_wdata4_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata4_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata4_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata4_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA5: begin
            if (write_strb[0]) evt_wdata5_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata5_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata5_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata5_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WDATA6: begin
            if (write_strb[0]) evt_wdata6_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) evt_wdata6_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) evt_wdata6_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) evt_wdata6_reg[31:24] <= write_data[31:24];
          end
          REG_EVT_WCTRL: begin
            if (legacy_push_attempt) begin
              event_wr_addr_cfg <= evt_waddr_reg;
              event_wr_data_cfg <= stream_event_word;
              event_wr_req_tgl <= ~event_wr_req_tgl;
            end else if (stream_push_attempt && !stream_push_fire) begin
              write_overflow_sticky_reg <= 1'b1;
            end else if (stream_push_fire) begin
              stream_pushes_reg <= stream_pushes_reg + 1'b1;
            end
          end
          REG_STREAM_CTRL: begin
            if (write_strb[0]) begin
              mode_stream_cfg_reg <= write_data[STREAM_CTRL_MODE_STREAM];
              dma_mode_cfg_reg <= write_data[STREAM_CTRL_DMA_MODE];
              if (write_data[STREAM_CTRL_WRITE_OVERFLOW])
                write_overflow_sticky_reg <= 1'b0;
            end
          end
          REG_LOW_WMARK: begin
            if (write_strb[0]) low_wmark_reg[7:0]   <= write_data[7:0];
            if (write_strb[1]) low_wmark_reg[15:8]  <= write_data[15:8];
            if (write_strb[2]) low_wmark_reg[23:16] <= write_data[23:16];
            if (write_strb[3]) low_wmark_reg[31:24] <= write_data[31:24];
          end
          default: ;
        endcase

        if (write_addr == REG_CTRL && write_strb[0] && write_data[3]) begin
          stream_flush_req_tgl <= ~stream_flush_req_tgl;
          stream_fifo_s_reset_hold <= 2'b11;
          write_overflow_sticky_reg <= 1'b0;
          stream_pushes_reg <= 32'h0;
        end
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
          REG_REINIT_COUNT: s_axi_rdata <= reinit_count_shadow;
          REG_REINIT_REJECT:s_axi_rdata <= reinit_reject_shadow;
          REG_IRQ_STATUS:   s_axi_rdata <= irq_status_axi;
          REG_IP_SCRATCH:   s_axi_rdata <= scratch_reg;
          REG_IRQ_ENABLE:   s_axi_rdata <= irq_enable_reg;
          REG_TIME_RELOAD_LO:   s_axi_rdata <= time_reload_lo_reg;
          REG_TIME_RELOAD_HI:   s_axi_rdata <= time_reload_hi_reg;
          // CTRL[1] is a write-only write-1 pulse command (load-now), so it reads 0.
          REG_TIME_RELOAD_CTRL: s_axi_rdata <= {31'h0,
                                                time_reload_ctrl_reg[TIME_RELOAD_CTRL_ARM_ON_SYSREF]};
          REG_EVT_WADDR:    s_axi_rdata <= {{(32-EVENT_MEM_ADDR_WIDTH){1'b0}}, evt_waddr_reg};
          REG_EVT_WDATA0:   s_axi_rdata <= evt_wdata0_reg;
          REG_EVT_WDATA1:   s_axi_rdata <= evt_wdata1_reg;
          REG_EVT_WDATA2:   s_axi_rdata <= evt_wdata2_reg;
          REG_EVT_WDATA3:   s_axi_rdata <= evt_wdata3_reg;
          REG_EVT_WDATA4:   s_axi_rdata <= evt_wdata4_reg;
          REG_EVT_WDATA5:   s_axi_rdata <= evt_wdata5_reg;
          REG_EVT_WDATA6:   s_axi_rdata <= evt_wdata6_reg;
          REG_STREAM_CTRL:  s_axi_rdata <= {28'h0, dma_mode_cfg_reg, eof_seen_shadow,
                                            write_overflow_sticky_reg, mode_stream_cfg_reg};
          REG_OCCUPANCY:    s_axi_rdata <= stream_occupancy_axi;
          REG_FREE_SPACE:   s_axi_rdata <= stream_fifo_free_space_axi;
          REG_LOW_WMARK:    s_axi_rdata <= low_wmark_eff;
          REG_STREAM_DEPTH: s_axi_rdata <= STREAM_DEPTH_USABLE;
          REG_STREAM_PUSHES:s_axi_rdata <= stream_pushes_reg;
          REG_STREAM_STALLS:s_axi_rdata <= stream_stalls_shadow;
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
        eof_seen_shadow     <= eof_seen_sched_snap;
        mode_stream_active_shadow <= mode_stream_sched_snap;
        // OR in new IRQ bits (accumulate; AXI clears via RW1C write)
        irq_status_axi      <= irq_status_axi | {28'h0, irq_snap};
      end

      // Commit-count CDC via Gray-coded synchronizer chain.
      // This avoids lost updates when status_snap_tgl edges coalesce.
      commit_count_gray_sync1 <= commit_count_gray_sched;
      commit_count_gray_sync2 <= commit_count_gray_sync1;
      commit_count_shadow     <= gray2bin32(commit_count_gray_sync2);
      reinit_count_gray_sync1 <= reinit_count_gray_sched;
      reinit_count_gray_sync2 <= reinit_count_gray_sync1;
      reinit_count_shadow     <= gray2bin32(reinit_count_gray_sync2);
      reinit_reject_gray_sync1 <= reinit_reject_gray_sched;
      reinit_reject_gray_sync2 <= reinit_reject_gray_sync1;
      reinit_reject_shadow     <= gray2bin32(reinit_reject_gray_sync2);
      stream_stalls_gray_sync1 <= stream_stalls_gray_sched;
      stream_stalls_gray_sync2 <= stream_stalls_gray_sync1;
      stream_stalls_shadow     <= gray2bin32(stream_stalls_gray_sync2);
      stream_hold_valid_sync1  <= stream_hold_valid;
      stream_hold_valid_shadow <= stream_hold_valid_sync1;

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
      load_sysref_req_sync1 <= 1'b0;
      load_sysref_req_sync2 <= 1'b0;
      load_sysref_req_sync2_d <= 1'b0;
      load_now_req_sync1 <= 1'b0;
      load_now_req_sync2 <= 1'b0;
      load_now_req_sync2_d <= 1'b0;
      stream_flush_req_sync1 <= 1'b0;
      stream_flush_req_sync2 <= 1'b0;
      stream_flush_req_sync2_d <= 1'b0;
      event_wr_req_sync1   <= 1'b0;
      event_wr_req_sync2   <= 1'b0;
      event_wr_req_sync2_d <= 1'b0;
      time_reload_lo_s1 <= 32'h0;
      time_reload_lo_s2 <= 32'h0;
      time_reload_hi_s1 <= 32'h0;
      time_reload_hi_s2 <= 32'h0;
      event_count_s1   <= 32'h0;
      event_count_s2   <= 32'h0;
      mode_stream_cfg_s1 <= 1'b0;
      mode_stream_cfg_s2 <= 1'b0;
      status_snap_tgl  <= 1'b0;
      event_wr_ack_tgl <= 1'b0;
      sched_time_counter  <= 64'h0;
      engine_state        <= ENGINE_IDLE;
      event_count_sched   <= 32'h0;
      read_ptr            <= 32'h0;
      last_exec_sched     <= 64'h0;
      commit_count_sched  <= 32'h0;
      commit_count_gray_sched <= 32'h0;
      reinit_count_sched <= 32'h0;
      reinit_count_gray_sched <= 32'h0;
      reinit_reject_sched <= 32'h0;
      reinit_reject_gray_sched <= 32'h0;
      stream_stalls_sched <= 32'h0;
      stream_stalls_gray_sched <= 32'h0;
      prev_ts             <= 64'h0;
      prev_phase_reinit   <= 1'b0;
      error_code          <= ERR_NONE;
      irq_sched           <= 6'h0;
      compare_first       <= 1'b0;
      time_reload_arm_sched <= 1'b0;
      mode_stream_sched   <= 1'b0;
      stream_empty_waiting <= 1'b0;
      stream_below_wmark_sched <= 1'b0;
      eof_seen_sched      <= 1'b0;
      stream_hold_valid   <= 1'b0;
      stream_fifo_m_reset_hold <= 2'b11;
      stream_fetch_data   <= 256'h0;
      low_wmark_s1        <= 32'h0;
      low_wmark_s2        <= 32'h0;
      marker_commit       <= 1'b0;
      marker_start        <= 1'b0;
      marker_done         <= 1'b0;
      sched_scale_s       <= {(NUM_CHANNELS*16){1'b0}};
      sched_init_s        <= {(NUM_CHANNELS*DDS_PHASE_DW){1'b0}};
      sched_incr_s        <= {(NUM_CHANNELS*DDS_PHASE_DW){1'b0}};
      sched_apply_s       <= {NUM_CHANNELS{1'b0}};
      sched_phase_reinit  <= 1'b0;
      status_sched_snap   <= 32'h0;
      last_exec_sched_snap <= 64'h0;
      cur_event_snap      <= 32'h0;
      irq_snap            <= 6'h0;
      eof_seen_sched_snap <= 1'b0;
      mode_stream_sched_snap <= 1'b0;
    end else begin
      sched_time_counter <= sched_time_counter + 1'b1;
      if (stream_fifo_m_reset_hold != 2'b00)
        stream_fifo_m_reset_hold <= {stream_fifo_m_reset_hold[0], 1'b0};

      // Clear one-cycle pulse outputs
      marker_commit <= 1'b0;
      marker_start  <= 1'b0;
      marker_done   <= 1'b0;
      sched_phase_reinit <= 1'b0;
      if (!stream_hold_valid && stream_prefetch_en && stream_fifo_m_valid) begin
        stream_fetch_data <= stream_fifo_m_data;
        stream_hold_valid <= 1'b1;
      end

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
      load_sysref_req_sync1   <= load_sysref_req_tgl;
      load_sysref_req_sync2   <= load_sysref_req_sync1;
      load_sysref_req_sync2_d <= load_sysref_req_sync2;
      load_now_req_sync1   <= load_now_req_tgl;
      load_now_req_sync2   <= load_now_req_sync1;
      load_now_req_sync2_d <= load_now_req_sync2;
      stream_flush_req_sync1 <= stream_flush_req_tgl;
      stream_flush_req_sync2 <= stream_flush_req_sync1;
      stream_flush_req_sync2_d <= stream_flush_req_sync2;

      event_wr_req_sync1   <= event_wr_req_tgl;
      event_wr_req_sync2   <= event_wr_req_sync1;
      event_wr_req_sync2_d <= event_wr_req_sync2;

      time_reload_lo_s1 <= time_reload_lo_reg;
      time_reload_lo_s2 <= time_reload_lo_s1;
      time_reload_hi_s1 <= time_reload_hi_reg;
      time_reload_hi_s2 <= time_reload_hi_s1;

      // event_count_cfg 2-FF direct sync (stable well before ARM fires)
      event_count_s1 <= event_count_cfg;
      event_count_s2 <= event_count_s1;
      mode_stream_cfg_s1 <= mode_stream_cfg_reg;
      mode_stream_cfg_s2 <= mode_stream_cfg_s1;
      low_wmark_s1 <= low_wmark_reg;
      low_wmark_s2 <= low_wmark_s1;
      if (stream_buffered_sched > low_wmark_eff_sched)
        stream_below_wmark_sched <= 1'b0;

      if (stream_flush_req_sync2 ^ stream_flush_req_sync2_d) begin
        stream_fifo_m_reset_hold <= 2'b11;
        stream_fetch_data <= 256'h0;
      end

      if (load_now_req_sync2 ^ load_now_req_sync2_d) begin
        sched_time_counter <= {time_reload_hi_s2, time_reload_lo_s2};
      end
      if (load_sysref_req_sync2 ^ load_sysref_req_sync2_d) begin
        time_reload_arm_sched <= 1'b1;
      end
      if (time_reload_arm_sched && sysref_pulse) begin
        sched_time_counter <= {time_reload_hi_s2, time_reload_lo_s2};
        time_reload_arm_sched <= 1'b0;
      end

      // -------------------------------------------------------------------
      // Command edge detection (priority: sreset > stop > arm/run > engine)
      // -------------------------------------------------------------------
      if (sreset_req_sync2 ^ sreset_req_sync2_d) begin
        // Soft reset: clear engine and all counters
        engine_state       <= ENGINE_IDLE;
        read_ptr           <= 32'h0;
        commit_count_sched <= 32'h0;
        commit_count_gray_sched <= 32'h0;
        reinit_count_sched <= 32'h0;
        reinit_count_gray_sched <= 32'h0;
        reinit_reject_sched <= 32'h0;
        reinit_reject_gray_sched <= 32'h0;
        stream_stalls_sched <= 32'h0;
        stream_stalls_gray_sched <= 32'h0;
        irq_sched          <= 6'h0;
        error_code         <= ERR_NONE;
        prev_ts            <= 64'h0;
        prev_phase_reinit  <= 1'b0;
        time_reload_arm_sched <= 1'b0;
        stream_empty_waiting <= 1'b0;
        stream_below_wmark_sched <= 1'b0;
        eof_seen_sched     <= 1'b0;
        stream_hold_valid  <= 1'b0;
        sched_apply_s      <= {NUM_CHANNELS{1'b0}};
        stream_fifo_m_reset_hold <= 2'b11;
        stream_fetch_data  <= 256'h0;
        // Send cleared status snapshot to AXI domain
        status_sched_snap   <= 32'h0;
        cur_event_snap      <= 32'h0;
        irq_snap            <= 6'h0;
        last_exec_sched_snap <= last_exec_sched;
        eof_seen_sched_snap <= 1'b0;
        mode_stream_sched_snap <= mode_stream_sched;
        status_snap_tgl     <= ~status_snap_tgl;

      end else if (stop_req_sync2 ^ stop_req_sync2_d) begin
        // Stop: abort execution, return to IDLE (does not clear counters)
        engine_state        <= ENGINE_IDLE;
        stream_empty_waiting <= 1'b0;
        stream_below_wmark_sched <= 1'b0;
        status_sched_snap   <= 32'h0;
        cur_event_snap      <= read_ptr;
        irq_snap            <= irq_sched;
        last_exec_sched_snap <= last_exec_sched;
        eof_seen_sched_snap <= eof_seen_sched;
        mode_stream_sched_snap <= mode_stream_sched;
        sched_apply_s       <= {NUM_CHANNELS{1'b0}};
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
            mode_stream_sched <= mode_stream_cfg_s2;
            sched_apply_s     <= {NUM_CHANNELS{1'b0}};
            if (mode_stream_cfg_s2 || (event_count_s2 > 0)) begin
              read_ptr       <= 32'h0;
              prev_ts        <= 64'h0;
              prev_phase_reinit <= 1'b0;
              stream_empty_waiting <= 1'b0;
              stream_below_wmark_sched <= 1'b0;
              engine_state   <= ENGINE_WAIT_FETCH;
              marker_start   <= 1'b1;
              // Snapshot: running=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b1, 1'b0};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              eof_seen_sched_snap <= eof_seen_sched;
              mode_stream_sched_snap <= mode_stream_cfg_s2;
              status_snap_tgl     <= ~status_snap_tgl;
            end else begin
              engine_state      <= ENGINE_ARMED;
              // Snapshot: armed=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b0, 1'b1};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              eof_seen_sched_snap <= eof_seen_sched;
              mode_stream_sched_snap <= mode_stream_cfg_s2;
              status_snap_tgl     <= ~status_snap_tgl;
            end
          end
        end else begin
          if (arm_edge) begin
            if (engine_state == ENGINE_IDLE) begin
              event_count_sched <= event_count_s2;
              mode_stream_sched <= mode_stream_cfg_s2;
              sched_apply_s     <= {NUM_CHANNELS{1'b0}};
              engine_state      <= ENGINE_ARMED;
              // Snapshot: armed=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b0, 1'b1};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              eof_seen_sched_snap <= eof_seen_sched;
              mode_stream_sched_snap <= mode_stream_cfg_s2;
              status_snap_tgl     <= ~status_snap_tgl;
            end
          end

          // -------------------------------------------------------------------
          // RUN edge: ARMED -> WAIT_FETCH (starts execution)
          // -------------------------------------------------------------------
          if (run_edge) begin
            if (engine_state == ENGINE_ARMED &&
                (mode_stream_sched || (event_count_sched > 0))) begin
              read_ptr       <= 32'h0;
              prev_ts        <= 64'h0;
              prev_phase_reinit <= 1'b0;
              stream_empty_waiting <= 1'b0;
              stream_below_wmark_sched <= 1'b0;
              engine_state   <= ENGINE_WAIT_FETCH;
              marker_start   <= 1'b1;
              // Snapshot: running=1
              status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b1, 1'b0};
              cur_event_snap      <= 32'h0;
              irq_snap            <= irq_sched;
              last_exec_sched_snap <= last_exec_sched;
              eof_seen_sched_snap <= eof_seen_sched;
              mode_stream_sched_snap <= mode_stream_sched;
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
            if (mode_stream_sched) begin
              if (stream_hold_valid) begin
                compare_first <= 1'b1;
                stream_empty_waiting <= 1'b0;
                engine_state  <= ENGINE_COMPARE;
              end else begin
                stream_stalls_sched <= stream_stalls_sched + 1'b1;
                stream_stalls_gray_sched <= (stream_stalls_sched + 1'b1) ^ ((stream_stalls_sched + 1'b1) >> 1);
                if (!stream_empty_waiting) begin
                  stream_empty_waiting <= 1'b1;
                  irq_sched[IRQ_EMPTY_STALL] <= 1'b1;
                  status_sched_snap   <= {16'h0, ERR_NONE, 12'h0, 1'b0, 1'b0, 1'b1, 1'b0};
                  cur_event_snap      <= read_ptr;
                  irq_snap            <= irq_sched | (6'b1 << IRQ_EMPTY_STALL);
                  last_exec_sched_snap <= last_exec_sched;
                  eof_seen_sched_snap <= eof_seen_sched;
                  mode_stream_sched_snap <= mode_stream_sched;
                  status_snap_tgl     <= ~status_snap_tgl;
                end
              end
            end else begin
              // Present read_ptr to BRAM; fetch_data valid next cycle (COMPARE).
              compare_first <= 1'b1;
              engine_state  <= ENGINE_COMPARE;
            end
          end

          ENGINE_COMPARE: begin
            compare_first <= 1'b0;
            // Priority: missed-deadline check (first cycle only) > fire-or-wait.
            // compare_first gates this check so we only classify "already late at
            // fetch time", not while waiting for a future due timestamp.
            if (compare_first && ev_ts < sched_time_counter) begin
              // Missed deadline: timestamp was already in the past on arrival
              error_code          <= ERR_MISSED_DEADLINE;
              if (ev_flags[0]) begin
                reinit_reject_sched <= reinit_reject_next;
                reinit_reject_gray_sched <= reinit_reject_next_gray;
              end
              irq_sched[IRQ_ERROR]  <= 1'b1;
              irq_sched[IRQ_UNDERRUN] <= 1'b1;
              engine_state        <= ENGINE_ERROR;
              status_sched_snap   <= {16'h0, ERR_MISSED_DEADLINE, 12'h0,
                                      1'b1, 1'b0, 1'b0, 1'b0};
              cur_event_snap      <= read_ptr;
              irq_snap            <= irq_sched | ((6'b1 << IRQ_UNDERRUN) | (6'b1 << IRQ_ERROR));
              last_exec_sched_snap <= last_exec_sched;
              eof_seen_sched_snap <= eof_seen_sched;
              mode_stream_sched_snap <= mode_stream_sched;
              status_snap_tgl     <= ~status_snap_tgl;

            end else if (ev_ts <= sched_time_counter) begin
              // Timestamp reached: check spacing before firing
              if (read_ptr > 0 &&
                  (ev_ts - prev_ts) < MIN_SPACING_VAL) begin
                error_code          <= spacing_error_code;
                if (ev_flags[0]) begin
                  reinit_reject_sched <= reinit_reject_next;
                  reinit_reject_gray_sched <= reinit_reject_next_gray;
                end
                irq_sched[IRQ_ERROR]             <= 1'b1;
                irq_sched[IRQ_SPACING_VIOLATION] <= 1'b1;
                engine_state        <= ENGINE_ERROR;
                status_sched_snap   <= {16'h0,
                                        spacing_error_code,
                                        12'h0,
                                        1'b1, 1'b0, 1'b0, 1'b0};
                cur_event_snap      <= read_ptr;
                irq_snap            <= irq_sched | ((6'b1 << IRQ_SPACING_VIOLATION) | (6'b1 << IRQ_ERROR));
                last_exec_sched_snap <= last_exec_sched;
                eof_seen_sched_snap <= eof_seen_sched;
                mode_stream_sched_snap <= mode_stream_sched;
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
            if (ev_flags[0]) begin
              reinit_count_sched <= reinit_count_next;
              reinit_count_gray_sched <= reinit_count_next_gray;
              sched_phase_reinit <= 1'b1;
            end
            if (ev_ch < NUM_CHANNELS) begin
              sched_scale_s[16*ev_ch +: 16] <= ev_payload[15:0];
              sched_init_s[DDS_PHASE_DW*ev_ch +: DDS_PHASE_DW] <= ev_payload[16 +: DDS_PHASE_DW];
              sched_incr_s[DDS_PHASE_DW*ev_ch +: DDS_PHASE_DW] <= ev_payload[16 + DDS_PHASE_DW +: DDS_PHASE_DW];
              sched_apply_s[ev_ch] <= 1'b1;
            end
            last_exec_sched    <= ev_ts;
            prev_ts            <= ev_ts;
            prev_phase_reinit  <= ev_flags[0];
            // Snapshot every FIRE so firmware polling sees progress before DONE.
            status_sched_snap    <= {16'h0, ERR_NONE, 12'h0,
                                     1'b0, 1'b0, 1'b1, 1'b0};
            cur_event_snap       <= cur_event_next;
            irq_snap             <= irq_sched;
            last_exec_sched_snap <= ev_ts;
            eof_seen_sched_snap  <= eof_seen_sched;
            mode_stream_sched_snap <= mode_stream_sched;
            status_snap_tgl      <= ~status_snap_tgl;
            engine_state       <= ENGINE_ADVANCE;
          end

          ENGINE_ADVANCE: begin
            if (mode_stream_sched) begin
              stream_hold_valid <= 1'b0;
              if (stream_fifo_m_level <= low_wmark_eff_sched)
                stream_below_wmark_sched <= 1'b1;
              else
                stream_below_wmark_sched <= 1'b0;
              if (!stream_below_wmark_sched && (stream_fifo_m_level <= low_wmark_eff_sched))
                irq_sched[IRQ_LOW_WATERMARK] <= 1'b1;
              if (ev_flags[1]) begin
                irq_sched[IRQ_DONE] <= 1'b1;
                eof_seen_sched <= 1'b1;
                engine_state        <= ENGINE_DONE;
                marker_done         <= 1'b1;
                status_sched_snap   <= {16'h0, ERR_NONE, 12'h0,
                                        1'b0, 1'b1, 1'b0, 1'b0};
                cur_event_snap      <= cur_event_next;
                irq_snap            <= irq_sched | (6'b1 << IRQ_DONE);
                last_exec_sched_snap <= last_exec_sched;
                eof_seen_sched_snap <= 1'b1;
                mode_stream_sched_snap <= mode_stream_sched;
                status_snap_tgl     <= ~status_snap_tgl;
              end else begin
                read_ptr     <= read_ptr + 1'b1;
                engine_state <= ENGINE_WAIT_FETCH;
              end
            end else begin
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
                irq_snap            <= irq_sched | (6'b1 << IRQ_DONE);
                last_exec_sched_snap <= last_exec_sched;
                eof_seen_sched_snap <= eof_seen_sched;
                mode_stream_sched_snap <= mode_stream_sched;
                status_snap_tgl     <= ~status_snap_tgl;
              end else begin
                read_ptr     <= read_ptr + 1'b1;
                engine_state <= ENGINE_WAIT_FETCH;
              end
            end
          end

          ENGINE_DONE: begin
            status_sched_snap   <= {16'h0, ERR_NONE, 12'h0,
                                    1'b0, 1'b1, 1'b0, 1'b0};
            cur_event_snap      <= cur_event_next;
            irq_snap            <= 6'h0;
            last_exec_sched_snap <= last_exec_sched;
            eof_seen_sched_snap <= eof_seen_sched;
            mode_stream_sched_snap <= mode_stream_sched;
            status_snap_tgl     <= ~status_snap_tgl;
          end

          ENGINE_ERROR: begin
            status_sched_snap   <= {16'h0, error_code, 12'h0,
                                    1'b1, 1'b0, 1'b0, 1'b0};
            cur_event_snap      <= read_ptr;
            irq_snap            <= 6'h0;
            last_exec_sched_snap <= last_exec_sched;
            eof_seen_sched_snap <= eof_seen_sched;
            mode_stream_sched_snap <= mode_stream_sched;
            status_snap_tgl     <= ~status_snap_tgl;
          end

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
