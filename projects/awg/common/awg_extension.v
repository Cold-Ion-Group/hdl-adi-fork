// awg_extension.v -- compatible AWGX discovery and C1 descriptor decoder
`timescale 1ns/1ps

module awg_extension #(
  parameter integer C1_IMPLEMENTED = 1,
  parameter integer COMMAND_ADDR_WIDTH = 12
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis:m_axis, ASSOCIATED_RESET s_axi_aresetn" *)
  input  wire         s_axi_aclk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire         s_axi_aresetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR" *) input wire [8:0] s_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWPROT" *) input wire [2:0] s_axi_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *) input wire s_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *) output wire s_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA" *) input wire [31:0] s_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB" *) input wire [3:0] s_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID" *) input wire s_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY" *) output wire s_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP" *) output wire [1:0] s_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID" *) output reg s_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY" *) input wire s_axi_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR" *) input wire [8:0] s_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARPROT" *) input wire [2:0] s_axi_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *) input wire s_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *) output wire s_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA" *) output reg [31:0] s_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP" *) output wire [1:0] s_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID" *) output reg s_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY" *) input wire s_axi_rready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *) input wire [255:0] s_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *) input wire s_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *) output wire s_axis_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *) output wire [255:0] m_axis_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *) output wire m_axis_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *) input wire m_axis_tready,
  (* X_INTERFACE_IGNORE = "true" *) output wire extension_error,
  (* X_INTERFACE_IGNORE = "true" *) output reg extension_error_toggle
);

  localparam [31:0] AWGX_ID = 32'h41574758;
  localparam [31:0] AWGC_ID = 32'h41574743;
  localparam [31:0] VERSION = 32'h00010000;
  localparam [31:0] AWGX_CAPS = 32'h0000000f | (C1_IMPLEMENTED ? 32'h10 : 32'h0);
  localparam [31:0] AWGC_CAPS = {8'h00, 8'd64, 8'd32, 8'd16};
  localparam [31:0] MAX_COMMANDS = (1 << COMMAND_ADDR_WIDTH);

  localparam [3:0] ST_IDLE       = 4'd0;
  localparam [3:0] ST_HEADER1    = 4'd1;
  localparam [3:0] ST_COMMAND_RX = 4'd2;
  localparam [3:0] ST_FETCH      = 4'd3;
  localparam [3:0] ST_DECODE     = 4'd4;
  localparam [3:0] ST_CONT_FETCH = 4'd5;
  localparam [3:0] ST_CONT_DECODE= 4'd6;
  localparam [3:0] ST_LINEAR     = 4'd7;
  localparam [3:0] ST_EMIT       = 4'd8;
  localparam [3:0] ST_SKIP_FETCH = 4'd9;
  localparam [3:0] ST_SKIP_DECODE= 4'd10;
  localparam [3:0] ST_DONE       = 4'd11;
  localparam [3:0] ST_ERROR      = 4'd12;

  localparam [7:0] OP_WAIT         = 8'h01;
  localparam [7:0] OP_FIRE         = 8'h02;
  localparam [7:0] OP_LINEAR       = 8'h03;
  localparam [7:0] OP_LINEAR_CONT  = 8'h04;
  localparam [7:0] OP_REPEAT_BEGIN = 8'h05;
  localparam [7:0] OP_REPEAT_END   = 8'h06;

  localparam integer ERR_BAD_HEADER    = 0;
  localparam integer ERR_BAD_VERSION   = 1;
  localparam integer ERR_BAD_SIZE      = 2;
  localparam integer ERR_BAD_FLAGS     = 3;
  localparam integer ERR_BAD_RESERVED  = 4;
  localparam integer ERR_BAD_CRC       = 5;
  localparam integer ERR_BAD_OPCODE    = 6;
  localparam integer ERR_BAD_STRUCTURE = 7;
  localparam integer ERR_COUNT_MISMATCH= 8;
  localparam integer ERR_RANGE         = 9;

  function [63:0] crc64_word;
    input [63:0] crc_in;
    input [255:0] data;
    integer byte_index;
    integer bit_index;
    reg [63:0] crc;
    begin
      crc = crc_in;
      for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
        crc = crc ^ ({56'h0, data[byte_index*8 +: 8]} << 56);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
          if (crc[63])
            crc = (crc << 1) ^ 64'h42f0e1eba9ea3693;
          else
            crc = crc << 1;
      end
      crc64_word = crc;
    end
  endfunction

  reg c1_enable_reg;
  reg soft_reset_pulse;
  reg control_error_pulse;
  reg [31:0] error_clear_mask;
  reg [31:0] error_reg;
  reg [3:0] state;

  reg [255:0] command_mem [0:MAX_COMMANDS-1];
  reg [255:0] command_word;
  reg [31:0] command_count;
  reg [31:0] rx_index;
  reg [31:0] pc;
  reg [31:0] header_flags;
  reg [63:0] start_timestamp;
  reg [63:0] declared_events;
  reg [63:0] declared_command_bytes;
  reg [63:0] expected_crc;
  reg [63:0] input_crc;
  reg [31:0] declared_depth;

  reg [63:0] cursor;
  reg [63:0] emitted_events;
  reg [63:0] records_accepted;
  reg [63:0] busy_cycles;
  reg [63:0] stall_cycles;
  reg [63:0] output_crc;
  reg [31:0] max_depth_seen;

  reg [31:0] repeat_pc [0:15];
  reg [31:0] repeat_remaining [0:15];
  reg [4:0] stack_depth;
  reg [4:0] skip_depth;

  reg signed [63:0] linear_asf;
  reg signed [63:0] linear_pow;
  reg signed [63:0] linear_ftw;
  reg signed [63:0] linear_start_asf;
  reg signed [63:0] linear_start_pow;
  reg signed [63:0] linear_start_ftw;
  reg signed [63:0] linear_asf_step;
  reg signed [63:0] linear_pow_step;
  reg signed [63:0] linear_ftw_step;
  reg [31:0] linear_remaining;
  reg [31:0] linear_count;
  reg [31:0] linear_dwell;
  reg [15:0] linear_channel;
  reg [15:0] linear_flags;

  reg [31:0] fire_advance;
  reg emit_linear;
  reg [255:0] decoded_data;
  reg decoded_valid;

  wire signed [63:0] linear_asf_next = linear_asf + linear_asf_step;
  wire signed [63:0] linear_pow_next = linear_pow + linear_pow_step;
  wire signed [63:0] linear_ftw_next = linear_ftw + linear_ftw_step;
  wire linear_next_out_of_range =
    linear_asf_next[63] || |linear_asf_next[63:16] ||
    linear_pow_next[63] || |linear_pow_next[63:32] ||
    linear_ftw_next[63] || |linear_ftw_next[63:32];

  wire c1_active = (C1_IMPLEMENTED != 0) && c1_enable_reg;
  wire decoder_busy = (state != ST_IDLE) && (state != ST_DONE) && (state != ST_ERROR);
  wire decoder_input_ready = (state == ST_IDLE) || (state == ST_DONE) ||
                             (state == ST_HEADER1) || (state == ST_COMMAND_RX);
  wire [255:0] header1_crc_data = {s_axis_tdata[255:192], 64'h0, s_axis_tdata[127:0]};
  wire [255:0] crc_data = (state == ST_HEADER1) ? header1_crc_data : s_axis_tdata;
  wire [63:0] input_crc_next = crc64_word(input_crc, crc_data);

  assign s_axis_tready = c1_active ? decoder_input_ready : m_axis_tready;
  assign m_axis_tdata = c1_active ? decoded_data : s_axis_tdata;
  assign m_axis_tvalid = c1_active ? decoded_valid : s_axis_tvalid;
  assign extension_error = |error_reg;

  reg extension_error_d;
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      extension_error_d <= 1'b0;
      extension_error_toggle <= 1'b0;
    end else begin
      extension_error_d <= extension_error;
      if (extension_error && !extension_error_d)
        extension_error_toggle <= ~extension_error_toggle;
    end
  end

  // AXI-Lite: independent address/data holding registers.
  reg aw_pending;
  reg w_pending;
  reg [8:0] awaddr_hold;
  reg [31:0] wdata_hold;
  reg [3:0] wstrb_hold;
  assign s_axi_awready = !aw_pending;
  assign s_axi_wready = !w_pending;
  assign s_axi_bresp = 2'b00;
  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_rresp = 2'b00;

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      aw_pending <= 1'b0;
      w_pending <= 1'b0;
      awaddr_hold <= 9'h0;
      wdata_hold <= 32'h0;
      wstrb_hold <= 4'h0;
      s_axi_bvalid <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata <= 32'h0;
      c1_enable_reg <= 1'b0;
      soft_reset_pulse <= 1'b0;
      control_error_pulse <= 1'b0;
      error_clear_mask <= 32'h0;
    end else begin
      soft_reset_pulse <= 1'b0;
      control_error_pulse <= 1'b0;
      error_clear_mask <= 32'h0;
      if (s_axi_awvalid && s_axi_awready) begin
        aw_pending <= 1'b1;
        awaddr_hold <= s_axi_awaddr;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        w_pending <= 1'b1;
        wdata_hold <= s_axi_wdata;
        wstrb_hold <= s_axi_wstrb;
      end
      if (aw_pending && w_pending && !s_axi_bvalid) begin
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
        s_axi_bvalid <= 1'b1;
        if (awaddr_hold == 9'h00c && wstrb_hold[0]) begin
          if (wdata_hold[1])
            soft_reset_pulse <= 1'b1;
          if (!decoder_busy)
            c1_enable_reg <= C1_IMPLEMENTED ? wdata_hold[0] : 1'b0;
          else if (c1_enable_reg != wdata_hold[0])
            control_error_pulse <= 1'b1;
        end
        if (awaddr_hold == 9'h110)
          error_clear_mask <= wdata_hold & {{8{wstrb_hold[3]}}, {8{wstrb_hold[2]}},
                                           {8{wstrb_hold[1]}}, {8{wstrb_hold[0]}}};
      end
      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;

      if (s_axi_arvalid && s_axi_arready) begin
        s_axi_rvalid <= 1'b1;
        case (s_axi_araddr)
          9'h000: s_axi_rdata <= AWGX_ID;
          9'h004: s_axi_rdata <= VERSION;
          9'h008: s_axi_rdata <= AWGX_CAPS;
          9'h00c: s_axi_rdata <= {31'h0, c1_enable_reg};
          9'h010: s_axi_rdata <= {28'h0, |error_reg, decoded_valid, decoder_busy, c1_active};
          9'h100: s_axi_rdata <= AWGC_ID;
          9'h104: s_axi_rdata <= VERSION;
          9'h108: s_axi_rdata <= AWGC_CAPS;
          9'h10c: s_axi_rdata <= {28'h0, |error_reg, decoded_valid, decoder_busy, c1_active};
          9'h110: s_axi_rdata <= error_reg;
          9'h118: s_axi_rdata <= records_accepted[31:0];
          9'h11c: s_axi_rdata <= records_accepted[63:32];
          9'h120: s_axi_rdata <= emitted_events[31:0];
          9'h124: s_axi_rdata <= emitted_events[63:32];
          9'h128: s_axi_rdata <= busy_cycles[31:0];
          9'h12c: s_axi_rdata <= busy_cycles[63:32];
          9'h130: s_axi_rdata <= stall_cycles[31:0];
          9'h134: s_axi_rdata <= stall_cycles[63:32];
          9'h138: s_axi_rdata <= output_crc[31:0];
          9'h13c: s_axi_rdata <= output_crc[63:32];
          9'h140: s_axi_rdata <= declared_events[31:0];
          9'h144: s_axi_rdata <= declared_events[63:32];
          9'h148: s_axi_rdata <= max_depth_seen;
          9'h14c: s_axi_rdata <= MAX_COMMANDS;
          default: s_axi_rdata <= 32'h0;
        endcase
      end
      if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;
    end
  end

  integer reset_index;
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      state <= ST_IDLE;
      error_reg <= 32'h0;
      command_count <= 32'h0;
      rx_index <= 32'h0;
      pc <= 32'h0;
      header_flags <= 32'h0;
      start_timestamp <= 64'h0;
      declared_events <= 64'h0;
      declared_command_bytes <= 64'h0;
      expected_crc <= 64'h0;
      input_crc <= 64'h0;
      declared_depth <= 32'h0;
      cursor <= 64'h0;
      emitted_events <= 64'h0;
      records_accepted <= 64'h0;
      busy_cycles <= 64'h0;
      stall_cycles <= 64'h0;
      output_crc <= 64'h0;
      max_depth_seen <= 32'h0;
      stack_depth <= 5'h0;
      skip_depth <= 5'h0;
      decoded_data <= 256'h0;
      decoded_valid <= 1'b0;
      emit_linear <= 1'b0;
      for (reset_index = 0; reset_index < 16; reset_index = reset_index + 1) begin
        repeat_pc[reset_index] <= 32'h0;
        repeat_remaining[reset_index] <= 32'h0;
      end
    end else if (soft_reset_pulse) begin
      state <= ST_IDLE;
      error_reg <= 32'h0;
      decoded_valid <= 1'b0;
      emitted_events <= 64'h0;
      records_accepted <= 64'h0;
      busy_cycles <= 64'h0;
      stall_cycles <= 64'h0;
      output_crc <= 64'h0;
      max_depth_seen <= 32'h0;
      stack_depth <= 5'h0;
    end else begin
      error_reg <= error_reg & ~error_clear_mask;
      if (control_error_pulse)
        error_reg[ERR_BAD_STRUCTURE] <= 1'b1;
      if (decoder_busy)
        busy_cycles <= busy_cycles + 1'b1;
      if (decoded_valid && !m_axis_tready)
        stall_cycles <= stall_cycles + 1'b1;

      case (state)
        ST_IDLE, ST_DONE: begin
          decoded_valid <= 1'b0;
          if (c1_active && s_axis_tvalid && s_axis_tready) begin
            error_reg <= 32'h0;
            emitted_events <= 64'h0;
            records_accepted <= 64'h0;
            busy_cycles <= 64'h0;
            stall_cycles <= 64'h0;
            output_crc <= 64'h0;
            max_depth_seen <= 32'h0;
            stack_depth <= 5'h0;
            input_crc <= crc64_word(64'h0, s_axis_tdata);
            header_flags <= s_axis_tdata[127:96];
            start_timestamp <= s_axis_tdata[191:128];
            command_count <= s_axis_tdata[223:192];
            declared_depth <= s_axis_tdata[255:224];
            if (s_axis_tdata[31:0] != 32'h43475741)
              begin error_reg[ERR_BAD_HEADER] <= 1'b1; state <= ST_ERROR; end
            else if (s_axis_tdata[47:32] != 16'd1 || s_axis_tdata[63:48] != 16'd0)
              begin error_reg[ERR_BAD_VERSION] <= 1'b1; state <= ST_ERROR; end
            else if (s_axis_tdata[79:64] != 16'd64 || s_axis_tdata[95:80] != 16'd32 ||
                     s_axis_tdata[223:192] > MAX_COMMANDS)
              begin error_reg[ERR_BAD_SIZE] <= 1'b1; state <= ST_ERROR; end
            else if (s_axis_tdata[127:96] & ~32'h1)
              begin error_reg[ERR_BAD_FLAGS] <= 1'b1; state <= ST_ERROR; end
            else if (s_axis_tdata[255:224] > 32'd16)
              begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
            else
              state <= ST_HEADER1;
          end
        end

        ST_HEADER1: if (c1_active && s_axis_tvalid && s_axis_tready) begin
          declared_events <= s_axis_tdata[63:0];
          declared_command_bytes <= s_axis_tdata[127:64];
          expected_crc <= s_axis_tdata[191:128];
          input_crc <= input_crc_next;
          rx_index <= 32'h0;
          if (s_axis_tdata[255:192] != 64'h0)
            begin error_reg[ERR_BAD_RESERVED] <= 1'b1; state <= ST_ERROR; end
          else if (s_axis_tdata[127:64] != ({32'h0, command_count} << 5))
            begin error_reg[ERR_BAD_SIZE] <= 1'b1; state <= ST_ERROR; end
          else if (command_count == 0) begin
            if (input_crc_next != s_axis_tdata[191:128])
              begin error_reg[ERR_BAD_CRC] <= 1'b1; state <= ST_ERROR; end
            else if (s_axis_tdata[63:0] != 0 || header_flags[0])
              begin error_reg[ERR_COUNT_MISMATCH] <= 1'b1; state <= ST_ERROR; end
            else state <= ST_DONE;
          end else state <= ST_COMMAND_RX;
        end

        ST_COMMAND_RX: if (c1_active && s_axis_tvalid && s_axis_tready) begin
          command_mem[rx_index[COMMAND_ADDR_WIDTH-1:0]] <= s_axis_tdata;
          records_accepted <= records_accepted + 1'b1;
          input_crc <= input_crc_next;
          if (rx_index + 1'b1 == command_count) begin
            if (input_crc_next != expected_crc)
              begin error_reg[ERR_BAD_CRC] <= 1'b1; state <= ST_ERROR; end
            else begin
              pc <= 32'h0;
              cursor <= start_timestamp;
              emitted_events <= 64'h0;
              stack_depth <= 5'h0;
              state <= ST_FETCH;
            end
          end
          rx_index <= rx_index + 1'b1;
        end

        ST_FETCH: begin
          if (pc >= command_count) begin
            if (stack_depth != 0)
              begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
            else if (max_depth_seen != declared_depth)
              begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
            else if (emitted_events != declared_events)
              begin error_reg[ERR_COUNT_MISMATCH] <= 1'b1; state <= ST_ERROR; end
            else state <= ST_DONE;
          end else begin
            command_word <= command_mem[pc[COMMAND_ADDR_WIDTH-1:0]];
            state <= ST_DECODE;
          end
        end

        ST_DECODE: begin
          case (command_word[7:0])
            OP_WAIT: begin
              if (command_word[31:8] != 0 || command_word[255:96] != 0)
                begin error_reg[ERR_BAD_RESERVED] <= 1'b1; state <= ST_ERROR; end
              else if (cursor > (64'hffffffffffffffff - command_word[95:32]))
                begin error_reg[ERR_RANGE] <= 1'b1; state <= ST_ERROR; end
              else begin cursor <= cursor + command_word[95:32]; pc <= pc + 1'b1; state <= ST_FETCH; end
            end
            OP_FIRE: begin
              if (command_word[15:8] != 0 || command_word[63:48] != 0 ||
                  command_word[255:224] != 0 || (command_word[47:32] & ~16'h0001) != 0)
                begin error_reg[ERR_BAD_RESERVED] <= 1'b1; state <= ST_ERROR; end
              else begin
                decoded_data <= {32'h0, command_word[223:96],
                  (command_word[47:32] | ((header_flags[0] &&
                   (emitted_events + 1'b1 == declared_events)) ? 16'h0002 : 16'h0000)),
                  command_word[31:16], cursor};
                decoded_valid <= 1'b1;
                fire_advance <= command_word[95:64];
                emit_linear <= 1'b0;
                state <= ST_EMIT;
              end
            end
            OP_LINEAR: begin
              if (command_word[15:8] != 0 || command_word[63:48] != 0 ||
                  command_word[159:144] != 0 || command_word[255:224] != 0 ||
                  (command_word[47:32] & ~16'h0001) != 0 ||
                  command_word[95:64] == 0 || command_word[127:96] == 0 ||
                  pc + 1'b1 >= command_count)
                begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
              else begin
                linear_channel <= command_word[31:16];
                linear_flags <= command_word[47:32];
                linear_remaining <= command_word[95:64];
                linear_count <= command_word[95:64];
                linear_dwell <= command_word[127:96];
                linear_asf <= $signed({48'h0, command_word[143:128]});
                linear_pow <= $signed({32'h0, command_word[191:160]});
                linear_ftw <= $signed({32'h0, command_word[223:192]});
                linear_start_asf <= $signed({48'h0, command_word[143:128]});
                linear_start_pow <= $signed({32'h0, command_word[191:160]});
                linear_start_ftw <= $signed({32'h0, command_word[223:192]});
                command_word <= command_mem[(pc + 1'b1) & (MAX_COMMANDS-1)];
                state <= ST_CONT_DECODE;
              end
            end
            OP_LINEAR_CONT:
              begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
            OP_REPEAT_BEGIN: begin
              if (command_word[31:8] != 0 || command_word[255:64] != 0)
                begin error_reg[ERR_BAD_RESERVED] <= 1'b1; state <= ST_ERROR; end
              else if (command_word[63:32] == 0) begin
                if (max_depth_seen < stack_depth + 1'b1)
                  max_depth_seen <= stack_depth + 1'b1;
                skip_depth <= 5'd1;
                pc <= pc + 1'b1;
                state <= ST_SKIP_FETCH;
              end else if (stack_depth >= 16) begin
                error_reg[ERR_BAD_STRUCTURE] <= 1'b1;
                state <= ST_ERROR;
              end else begin
                repeat_pc[stack_depth] <= pc + 1'b1;
                repeat_remaining[stack_depth] <= command_word[63:32];
                stack_depth <= stack_depth + 1'b1;
                if (max_depth_seen < stack_depth + 1'b1)
                  max_depth_seen <= stack_depth + 1'b1;
                pc <= pc + 1'b1;
                state <= ST_FETCH;
              end
            end
            OP_REPEAT_END: begin
              if (command_word[255:8] != 0)
                begin error_reg[ERR_BAD_RESERVED] <= 1'b1; state <= ST_ERROR; end
              else if (stack_depth == 0)
                begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
              else if (repeat_remaining[stack_depth-1] > 1) begin
                repeat_remaining[stack_depth-1] <= repeat_remaining[stack_depth-1] - 1'b1;
                pc <= repeat_pc[stack_depth-1];
                state <= ST_FETCH;
              end else begin
                stack_depth <= stack_depth - 1'b1;
                pc <= pc + 1'b1;
                state <= ST_FETCH;
              end
            end
            default: begin error_reg[ERR_BAD_OPCODE] <= 1'b1; state <= ST_ERROR; end
          endcase
        end

        ST_CONT_DECODE: begin
          if (command_word[7:0] != OP_LINEAR_CONT || command_word[31:8] != 0 ||
              command_word[255:224] != 0)
            begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
          else begin
            linear_asf_step <= $signed(command_word[95:32]);
            linear_pow_step <= $signed(command_word[159:96]);
            linear_ftw_step <= $signed(command_word[223:160]);
            state <= ST_LINEAR;
          end
        end

        ST_LINEAR: begin
          if (linear_asf[63] || |linear_asf[63:16] ||
              linear_pow[63] || |linear_pow[63:32] ||
              linear_ftw[63] || |linear_ftw[63:32]) begin
            error_reg[ERR_RANGE] <= 1'b1;
            state <= ST_ERROR;
          end else begin
            decoded_data <= {32'h0, 48'h0, linear_ftw[31:0], linear_pow[31:0],
              linear_asf[15:0],
              (linear_flags | ((header_flags[0] &&
               (emitted_events + 1'b1 == declared_events)) ? 16'h0002 : 16'h0000)),
              linear_channel, cursor};
            decoded_valid <= 1'b1;
            emit_linear <= 1'b1;
            state <= ST_EMIT;
          end
        end

        ST_EMIT: if (decoded_valid && m_axis_tready) begin
          emitted_events <= emitted_events + 1'b1;
          output_crc <= crc64_word(output_crc, decoded_data);
          if (emit_linear) begin
            if (cursor > 64'hffffffffffffffff - linear_dwell)
              begin decoded_valid <= 1'b0; error_reg[ERR_RANGE] <= 1'b1; state <= ST_ERROR; end
            else begin
              cursor <= cursor + linear_dwell;
              if (linear_remaining == 1) begin
                // Fast path for the primary compact-run shape: a repeat body
                // containing one LINEAR command.  Re-seed the generator and
                // replace the accepted final beat without a loop-boundary
                // bubble.
                if (stack_depth != 0 &&
                    repeat_pc[stack_depth-1] == pc &&
                    repeat_remaining[stack_depth-1] > 1 &&
                    command_mem[(pc + 2) & (MAX_COMMANDS-1)][7:0] == OP_REPEAT_END) begin
                  repeat_remaining[stack_depth-1] <= repeat_remaining[stack_depth-1] - 1'b1;
                  linear_remaining <= linear_count;
                  linear_asf <= linear_start_asf;
                  linear_pow <= linear_start_pow;
                  linear_ftw <= linear_start_ftw;
                  decoded_data <= {32'h0, 48'h0, linear_start_ftw[31:0],
                    linear_start_pow[31:0], linear_start_asf[15:0],
                    (linear_flags | ((header_flags[0] &&
                     (emitted_events + 2 == declared_events)) ? 16'h0002 : 16'h0000)),
                    linear_channel, cursor + linear_dwell};
                  decoded_valid <= 1'b1;
                  state <= ST_EMIT;
                end else begin
                  decoded_valid <= 1'b0;
                  pc <= pc + 2;
                  state <= ST_FETCH;
                end
              end else if (linear_next_out_of_range) begin
                decoded_valid <= 1'b0;
                error_reg[ERR_RANGE] <= 1'b1;
                state <= ST_ERROR;
              end else begin
                linear_remaining <= linear_remaining - 1'b1;
                linear_asf <= linear_asf_next;
                linear_pow <= linear_pow_next;
                linear_ftw <= linear_ftw_next;
                // Replace the accepted beat immediately.  With READY held
                // high this emits one expanded event on every AXI cycle.
                decoded_data <= {32'h0, 48'h0, linear_ftw_next[31:0],
                  linear_pow_next[31:0], linear_asf_next[15:0],
                  (linear_flags | ((header_flags[0] &&
                   (emitted_events + 2 == declared_events)) ? 16'h0002 : 16'h0000)),
                  linear_channel, cursor + linear_dwell};
                decoded_valid <= 1'b1;
                state <= ST_EMIT;
              end
            end
          end else begin
            if (cursor > 64'hffffffffffffffff - fire_advance)
              begin decoded_valid <= 1'b0; error_reg[ERR_RANGE] <= 1'b1; state <= ST_ERROR; end
            else begin
              decoded_valid <= 1'b0;
              cursor <= cursor + fire_advance;
              pc <= pc + 1'b1;
              state <= ST_FETCH;
            end
          end
        end

        ST_SKIP_FETCH: begin
          if (pc >= command_count)
            begin error_reg[ERR_BAD_STRUCTURE] <= 1'b1; state <= ST_ERROR; end
          else begin command_word <= command_mem[pc[COMMAND_ADDR_WIDTH-1:0]]; state <= ST_SKIP_DECODE; end
        end
        ST_SKIP_DECODE: begin
          if (command_word[7:0] == OP_REPEAT_BEGIN) begin
            if (stack_depth + skip_depth >= 16) begin
              error_reg[ERR_BAD_STRUCTURE] <= 1'b1;
              state <= ST_ERROR;
            end
            if (max_depth_seen < stack_depth + skip_depth + 1'b1)
              max_depth_seen <= stack_depth + skip_depth + 1'b1;
            skip_depth <= skip_depth + 1'b1;
          end
          else if (command_word[7:0] == OP_REPEAT_END) begin
            if (skip_depth == 1) begin
              skip_depth <= 0;
              pc <= pc + 1'b1;
              state <= ST_FETCH;
            end else skip_depth <= skip_depth - 1'b1;
          end
          if (!(command_word[7:0] == OP_REPEAT_END && skip_depth == 1) &&
              !(command_word[7:0] == OP_REPEAT_BEGIN &&
                stack_depth + skip_depth >= 16)) begin
            pc <= pc + 1'b1;
            state <= ST_SKIP_FETCH;
          end
        end

        ST_ERROR: decoded_valid <= 1'b0;
        default: state <= ST_ERROR;
      endcase
    end
  end
endmodule
