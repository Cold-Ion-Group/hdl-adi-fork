`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_stream_eof.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  initial begin
    reset_dut();
    set_stream_mode(1'b1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd320, 32'd0, 32'h00000000, 32'h00000111, 32'h00000222, 32'h00000333, 32'h00000444);
    stream_push_event(read_data64[31:0] + 32'd448, 32'd0, 32'h00000002, 32'h00000555, 32'h00000666, 32'h00000777, 32'h00000888);
    arm_scheduler();
    run_scheduler();
    wait_for_done();
    axi_read(REG_STATUS, read_data);
    expect_eq32("legacy-style DONE snapshot", read_data, 32'h00000004);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("EOF sticky set", read_data[2], 1'b1);
    finish_test();
  end

endmodule
