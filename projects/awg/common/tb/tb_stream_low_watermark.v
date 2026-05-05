`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_low_watermark.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    integer i;
    reset_dut();
    set_stream_mode(1'b1);
    set_low_wmark(32'd2);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    for (i = 0; i < 4; i = i + 1)
      stream_push_event((read_data64[31:0] + 32'd320 + i*32'd128), 32'd0,
                        (i == 3) ? 32'h00000002 : 32'h00000000,
                        i, i+1, i+2, i+3);

    arm_scheduler();
    run_scheduler();

    wait_for_done();
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("low watermark IRQ asserted", read_data[4], 1'b1);
    axi_write(REG_IRQ_STATUS, 32'h00000010, 4'b0001);
    repeat (20) @(posedge s_axi_aclk);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("low watermark does not retrigger without new crossing", read_data[4], 1'b0);
    finish_test();
  end

endmodule
