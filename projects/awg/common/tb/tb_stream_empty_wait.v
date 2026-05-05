`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_empty_wait.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    reset_dut();
    set_stream_mode(1'b1);
    set_low_wmark(32'd2);
    arm_scheduler();
    run_scheduler();

    repeat (8) @(posedge sched_clk);
    axi_read(REG_STREAM_STALLS, read_data);
    expect_true("empty-wait stalls increment", read_data > 0);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("empty-wait IRQ set", read_data[5], 1'b1);

    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd400, 32'd0, 32'h00000000, 32'h00000011, 32'h00000022, 32'h00000033, 32'h00000044);
    stream_push_event(read_data64[31:0] + 32'd520, 32'd0, 32'h00000002, 32'h00000055, 32'h00000066, 32'h00000077, 32'h00000088);

    wait_for_done();
    axi_read(REG_COMMIT_COUNT, read_data);
    expect_eq32("two stream events committed", read_data, 32'd2);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("EOF seen after done", read_data[2], 1'b1);
    finish_test();
  end

endmodule
