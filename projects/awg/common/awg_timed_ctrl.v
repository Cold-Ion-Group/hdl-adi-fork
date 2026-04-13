module awg_timed_ctrl #(
  parameter integer EVENT_MEM_ADDR_WIDTH = 8
) (
  input  wire                       s_axi_aclk,
  input  wire                       s_axi_aresetn,
  input  wire [7:0]                 s_axi_awaddr,
  input  wire                       s_axi_awvalid,
  output reg                        s_axi_awready,
  input  wire [31:0]                s_axi_wdata,
  input  wire [3:0]                 s_axi_wstrb,
  input  wire                       s_axi_wvalid,
  output reg                        s_axi_wready,
  output reg  [1:0]                 s_axi_bresp,
  output reg                        s_axi_bvalid,
  input  wire                       s_axi_bready,
  input  wire [7:0]                 s_axi_araddr,
  input  wire                       s_axi_arvalid,
  output reg                        s_axi_arready,
  output reg  [31:0]                s_axi_rdata,
  output reg  [1:0]                 s_axi_rresp,
  output reg                        s_axi_rvalid,
  input  wire                       s_axi_rready,
  input  wire                       sched_clk,
  input  wire                       sched_reset,
  output reg                        marker_commit,
  output reg                        marker_start,
  output reg                        marker_done
);

  localparam integer EVENT_MEM_DEPTH = (1 << EVENT_MEM_ADDR_WIDTH);

  localparam [7:0] REG_CTRL         = 8'h00;
  localparam [7:0] REG_STATUS       = 8'h04;
  localparam [7:0] REG_TIME_LO      = 8'h08;
  localparam [7:0] REG_TIME_HI      = 8'h0C;
  localparam [7:0] REG_LAST_EXEC_LO = 8'h10;
  localparam [7:0] REG_LAST_EXEC_HI = 8'h14;
  localparam [7:0] REG_LAST_APPLY_LO= 8'h18;
  localparam [7:0] REG_LAST_APPLY_HI= 8'h1C;
  localparam [7:0] REG_COMMIT_COUNT = 8'h20;
  localparam [7:0] REG_EVENT_COUNT  = 8'h24;
  localparam [7:0] REG_LATE_EVENT_COUNT = 8'h28;
  localparam [7:0] REG_LAST_LATE_EVENT_ID = 8'h2C;
  localparam [7:0] REG_EVENT_WDATA0 = 8'h40;
  localparam [7:0] REG_EVENT_WDATA1 = 8'h44;
  localparam [7:0] REG_EVENT_WDATA2 = 8'h48;
  localparam [7:0] REG_EVENT_WDATA3 = 8'h4C;
  localparam [7:0] REG_EVENT_WADDR  = 8'h50;
  localparam [7:0] REG_EVENT_WCTRL  = 8'h54;

  reg [31:0] ctrl_reg;
  reg [63:0] time_reg;
  reg [31:0] event_wdata0_reg, event_wdata1_reg, event_wdata2_reg, event_wdata3_reg;
  reg [EVENT_MEM_ADDR_WIDTH-1:0] event_waddr_reg;
  reg [EVENT_MEM_ADDR_WIDTH-1:0] event_wr_addr_cfg;
  reg [127:0] event_wr_data_cfg;

  reg commit_req_tgl, event_wr_req_tgl;
  reg commit_ack_sync1, commit_ack_sync2, commit_ack_sync2_d;
  reg event_wr_ack_sync1, event_wr_ack_sync2, event_wr_ack_sync2_d;

  reg [31:0] commit_count_shadow, event_count_shadow;
  reg [31:0] late_event_count_shadow, last_late_event_id_shadow;
  reg late_event_shadow, late_event_seen_shadow;
  reg [63:0] last_exec_shadow, last_apply_shadow;

  reg [31:0] commit_count_sched, event_count_sched;
  reg [31:0] late_event_count_sched, last_late_event_id_sched;
  reg late_event_sched, late_event_seen_sched;
  reg [63:0] sched_time_counter, last_exec_sched, last_apply_sched;
  reg [127:0] event_mem [0:EVENT_MEM_DEPTH-1];

  reg commit_req_sync1, commit_req_sync2, commit_req_sync2_d;
  reg event_wr_req_sync1, event_wr_req_sync2, event_wr_req_sync2_d;
  reg commit_ack_tgl, event_wr_ack_tgl;
  reg commit_pending;
  reg [63:0] commit_target_time;

  localparam [1:0] COMMIT_FSM_IDLE = 2'd0;
  localparam [1:0] COMMIT_FSM_WAIT = 2'd1;
  reg [1:0] awg_commit_fsm;

  wire write_fire = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
  wire read_fire  = s_axi_arvalid && s_axi_arready;

  integer i;

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_awready <= 1'b1;
      s_axi_wready <= 1'b1;
      s_axi_bresp <= 2'b00;
      s_axi_bvalid <= 1'b0;
      s_axi_arready <= 1'b1;
      s_axi_rdata <= 32'h0;
      s_axi_rresp <= 2'b00;
      s_axi_rvalid <= 1'b0;
      ctrl_reg <= 32'h0;
      time_reg <= 64'h0;
      event_wdata0_reg <= 32'h0;
      event_wdata1_reg <= 32'h0;
      event_wdata2_reg <= 32'h0;
      event_wdata3_reg <= 32'h0;
      event_waddr_reg <= 'h0;
      event_wr_addr_cfg <= 'h0;
      event_wr_data_cfg <= 128'h0;
      commit_req_tgl <= 1'b0;
      event_wr_req_tgl <= 1'b0;
      commit_ack_sync1 <= 1'b0;
      commit_ack_sync2 <= 1'b0;
      commit_ack_sync2_d <= 1'b0;
      event_wr_ack_sync1 <= 1'b0;
      event_wr_ack_sync2 <= 1'b0;
      event_wr_ack_sync2_d <= 1'b0;
      commit_count_shadow <= 32'h0;
      event_count_shadow <= 32'h0;
      late_event_count_shadow <= 32'h0;
      last_late_event_id_shadow <= 32'h0;
      late_event_shadow <= 1'b0;
      late_event_seen_shadow <= 1'b0;
      last_exec_shadow <= 64'h0;
      last_apply_shadow <= 64'h0;
    end else begin
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      if (write_fire && !s_axi_bvalid) begin
        s_axi_bvalid <= 1'b1;
        case (s_axi_awaddr)
          REG_CTRL: if (s_axi_wstrb[0]) begin
            ctrl_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wdata[0]) commit_req_tgl <= ~commit_req_tgl;
          end
          REG_TIME_LO: begin
            if (s_axi_wstrb[0]) time_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) time_reg[15:8] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) time_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) time_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_TIME_HI: begin
            if (s_axi_wstrb[0]) time_reg[39:32] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) time_reg[47:40] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) time_reg[55:48] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) time_reg[63:56] <= s_axi_wdata[31:24];
          end
          REG_EVENT_WDATA0: begin
            if (s_axi_wstrb[0]) event_wdata0_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) event_wdata0_reg[15:8] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) event_wdata0_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) event_wdata0_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVENT_WDATA1: begin
            if (s_axi_wstrb[0]) event_wdata1_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) event_wdata1_reg[15:8] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) event_wdata1_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) event_wdata1_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVENT_WDATA2: begin
            if (s_axi_wstrb[0]) event_wdata2_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) event_wdata2_reg[15:8] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) event_wdata2_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) event_wdata2_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVENT_WDATA3: begin
            if (s_axi_wstrb[0]) event_wdata3_reg[7:0] <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) event_wdata3_reg[15:8] <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) event_wdata3_reg[23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) event_wdata3_reg[31:24] <= s_axi_wdata[31:24];
          end
          REG_EVENT_WADDR: event_waddr_reg <= s_axi_wdata[EVENT_MEM_ADDR_WIDTH-1:0];
          REG_EVENT_WCTRL: if (s_axi_wstrb[0] && s_axi_wdata[0]) begin
            event_wr_addr_cfg <= event_waddr_reg;
            event_wr_data_cfg <= {event_wdata3_reg, event_wdata2_reg, event_wdata1_reg, event_wdata0_reg};
            event_wr_req_tgl <= ~event_wr_req_tgl;
          end
          default: ;
        endcase
      end

      if (read_fire && !s_axi_rvalid) begin
        s_axi_rvalid <= 1'b1;
        case (s_axi_araddr)
          REG_CTRL: s_axi_rdata <= ctrl_reg;
          REG_STATUS: s_axi_rdata <= {28'h0, late_event_seen_shadow, late_event_shadow, commit_ack_sync2 ^ commit_ack_sync2_d, ctrl_reg[1]};
          REG_TIME_LO: s_axi_rdata <= time_reg[31:0];
          REG_TIME_HI: s_axi_rdata <= time_reg[63:32];
          REG_LAST_EXEC_LO: s_axi_rdata <= last_exec_shadow[31:0];
          REG_LAST_EXEC_HI: s_axi_rdata <= last_exec_shadow[63:32];
          REG_LAST_APPLY_LO: s_axi_rdata <= last_apply_shadow[31:0];
          REG_LAST_APPLY_HI: s_axi_rdata <= last_apply_shadow[63:32];
          REG_COMMIT_COUNT: s_axi_rdata <= commit_count_shadow;
          REG_EVENT_COUNT: s_axi_rdata <= event_count_shadow;
          REG_LATE_EVENT_COUNT: s_axi_rdata <= late_event_count_shadow;
          REG_LAST_LATE_EVENT_ID: s_axi_rdata <= last_late_event_id_shadow;
          REG_EVENT_WDATA0: s_axi_rdata <= event_wdata0_reg;
          REG_EVENT_WDATA1: s_axi_rdata <= event_wdata1_reg;
          REG_EVENT_WDATA2: s_axi_rdata <= event_wdata2_reg;
          REG_EVENT_WDATA3: s_axi_rdata <= event_wdata3_reg;
          REG_EVENT_WADDR: s_axi_rdata <= {{(32-EVENT_MEM_ADDR_WIDTH){1'b0}}, event_waddr_reg};
          default: s_axi_rdata <= 32'h0;
        endcase
      end

      commit_ack_sync1 <= commit_ack_tgl;
      commit_ack_sync2 <= commit_ack_sync1;
      commit_ack_sync2_d <= commit_ack_sync2;
      if (commit_ack_sync2 ^ commit_ack_sync2_d) begin
        commit_count_shadow <= commit_count_sched;
        last_exec_shadow <= last_exec_sched;
        last_apply_shadow <= last_apply_sched;
        late_event_shadow <= late_event_sched;
        late_event_seen_shadow <= late_event_seen_sched;
        late_event_count_shadow <= late_event_count_sched;
        last_late_event_id_shadow <= last_late_event_id_sched;
      end

      event_wr_ack_sync1 <= event_wr_ack_tgl;
      event_wr_ack_sync2 <= event_wr_ack_sync1;
      event_wr_ack_sync2_d <= event_wr_ack_sync2;
      if (event_wr_ack_sync2 ^ event_wr_ack_sync2_d) event_count_shadow <= event_count_sched;
    end
  end

  always @(posedge sched_clk) begin
    if (sched_reset) begin
      commit_req_sync1 <= 1'b0;
      commit_req_sync2 <= 1'b0;
      commit_req_sync2_d <= 1'b0;
      event_wr_req_sync1 <= 1'b0;
      event_wr_req_sync2 <= 1'b0;
      event_wr_req_sync2_d <= 1'b0;
      commit_ack_tgl <= 1'b0;
      event_wr_ack_tgl <= 1'b0;
      commit_count_sched <= 32'h0;
      event_count_sched <= 32'h0;
      late_event_count_sched <= 32'h0;
      last_late_event_id_sched <= 32'h0;
      late_event_sched <= 1'b0;
      late_event_seen_sched <= 1'b0;
      sched_time_counter <= 64'h0;
      last_exec_sched <= 64'h0;
      last_apply_sched <= 64'h0;
      commit_pending <= 1'b0;
      commit_target_time <= 64'h0;
      awg_commit_fsm <= COMMIT_FSM_IDLE;
      marker_commit <= 1'b0;
      marker_start <= 1'b0;
      marker_done <= 1'b0;
      for (i = 0; i < EVENT_MEM_DEPTH; i = i + 1) event_mem[i] <= 128'h0;
    end else begin
      sched_time_counter <= sched_time_counter + 1'b1;
      marker_commit <= 1'b0;
      marker_start <= 1'b0;
      marker_done <= 1'b0;

      commit_req_sync1 <= commit_req_tgl;
      commit_req_sync2 <= commit_req_sync1;
      commit_req_sync2_d <= commit_req_sync2;
      if (commit_req_sync2 ^ commit_req_sync2_d) begin
        commit_target_time <= time_reg;
        commit_pending <= 1'b1;
        late_event_sched <= 1'b0;
        awg_commit_fsm <= COMMIT_FSM_WAIT;
      end

      case (awg_commit_fsm)
        COMMIT_FSM_IDLE: begin
        end
        COMMIT_FSM_WAIT: begin
          if (commit_pending) begin
            if (sched_time_counter < commit_target_time) begin
              // Early event: wait for due cycle.
            end else begin
              commit_count_sched <= commit_count_sched + 1'b1;
              last_exec_sched <= commit_target_time;
              last_apply_sched <= sched_time_counter;
              commit_ack_tgl <= ~commit_ack_tgl;
              marker_commit <= 1'b1;
              marker_start <= 1'b1;
              marker_done <= 1'b1;
              if (sched_time_counter > commit_target_time) begin
                // Late policy (v1): commit immediately and record late-event telemetry.
                late_event_sched <= 1'b1;
                late_event_seen_sched <= 1'b1;
                late_event_count_sched <= late_event_count_sched + 1'b1;
                last_late_event_id_sched <= commit_count_sched + 1'b1;
              end
              commit_pending <= 1'b0;
              awg_commit_fsm <= COMMIT_FSM_IDLE;
            end
          end
        end
        default: awg_commit_fsm <= COMMIT_FSM_IDLE;
      end

      event_wr_req_sync1 <= event_wr_req_tgl;
      event_wr_req_sync2 <= event_wr_req_sync1;
      event_wr_req_sync2_d <= event_wr_req_sync2;
      if (event_wr_req_sync2 ^ event_wr_req_sync2_d) begin
        event_mem[event_wr_addr_cfg] <= event_wr_data_cfg;
        event_count_sched <= event_count_sched + 1'b1;
        event_wr_ack_tgl <= ~event_wr_ack_tgl;
      end
    end
  end

endmodule
