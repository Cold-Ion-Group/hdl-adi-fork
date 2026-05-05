`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_hard_underrun.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    reset_dut();
    set_stream_mode(1'b1);
    arm_scheduler();
    run_scheduler();
    repeat (40) @(posedge sched_clk);
    stream_push_event(32'd10, 32'd0, 32'h00000002, 32'h1, 32'h2, 32'h3, 32'h4);
    wait_for_error();
    expect_eq32("missed-deadline error code", dut.error_code, 32'h00000001);
    expect_eq1("IRQ_ERROR set", dut.irq_sched[1], 1'b1);
    expect_eq1("IRQ_UNDERRUN set", dut.irq_sched[3], 1'b1);
    finish_test();
  end

endmodule
