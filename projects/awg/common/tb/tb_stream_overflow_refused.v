`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_overflow_refused.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    integer i;
    reset_dut();
    set_stream_mode(1'b1);
    for (i = 0; i < 8; i = i + 1)
      stream_push_event((200 + i), 32'd0, 32'h0, i, i, i, i);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("usable depth accepted", read_data, 32'd8);
    stream_push_event(32'd300, 32'd0, 32'h00000002, 32'h9, 32'ha, 32'hb, 32'hc);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("overflow push rejected", read_data, 32'd8);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("overflow sticky set", read_data[1], 1'b1);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("occupancy unchanged at full", read_data, 32'd8);
    finish_test();
  end

endmodule
