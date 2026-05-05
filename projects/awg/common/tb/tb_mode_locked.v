`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_mode_locked.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    reset_dut();
    set_stream_mode(1'b1);
    arm_scheduler();
    set_stream_mode(1'b0);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd320, 32'd0, 32'h00000002, 32'h1, 32'h2, 32'h3, 32'h4);
    run_scheduler();
    wait_for_done();
    axi_read(REG_COMMIT_COUNT, read_data);
    expect_eq32("stream mode stayed locked after ARM", read_data, 32'd1);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("config bit writable while active mode stays stream", read_data[0], 1'b0);
    expect_eq1("EOF still consumed in locked stream mode", read_data[2], 1'b1);
    finish_test();
  end

endmodule
