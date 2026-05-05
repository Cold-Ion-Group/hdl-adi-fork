`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_soft_reset_flush.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    reset_dut();
    set_stream_mode(1'b1);
    stream_push_event(32'd50, 32'd0, 32'h0, 32'h1, 32'h2, 32'h3, 32'h4);
    stream_push_event(32'd60, 32'd0, 32'h00000002, 32'h5, 32'h6, 32'h7, 32'h8);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("occupancy before soft reset", read_data, 32'd2);
    soft_reset_scheduler();
    repeat (16) @(posedge s_axi_aclk);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("FIFO flushed on soft reset", read_data, 32'd0);
    axi_read(REG_FREE_SPACE, read_data);
    expect_eq32("free space restored", read_data, 32'd8);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("EOF cleared on soft reset", read_data[2], 1'b0);
    expect_eq1("overflow sticky cleared on soft reset", read_data[1], 1'b0);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("stream push counter cleared on soft reset", read_data, 32'd0);
    axi_read(REG_STATUS, read_data);
    expect_eq32("status idle after soft reset", read_data, 32'h00000000);
    finish_test();
  end

endmodule
