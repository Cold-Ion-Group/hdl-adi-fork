`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam integer STREAM_USABLE_DEPTH = (1 << TB_STREAM_ADDR_WIDTH) - 1;
  localparam VCD_FILE = "tb_stream_occupancy_rollover.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  integer round_idx;
  integer push_idx;
  integer guard;

  task automatic wait_for_free_space;
    input [31:0] expected;
    integer wait_count;
    begin
      wait_count = 0;
      axi_read(REG_FREE_SPACE, read_data);
      while ((read_data !== expected) && (wait_count < 128)) begin
        repeat (2) @(posedge s_axi_aclk);
        axi_read(REG_FREE_SPACE, read_data);
        wait_count = wait_count + 1;
      end
      expect_eq32("free-space wait", read_data, expected);
    end
  endtask

  task automatic expect_empty_fifo;
    begin
      wait_for_free_space(STREAM_USABLE_DEPTH);
      axi_read(REG_OCCUPANCY, read_data);
      expect_eq32("empty FIFO occupancy", read_data, 32'd0);
      axi_read(REG_STREAM_PUSHES, read_data);
      expect_eq32("empty FIFO push counter", read_data, 32'd0);
    end
  endtask

  initial begin
    reset_dut();
    set_stream_mode(1'b1);

    axi_read(REG_STREAM_DEPTH, read_data);
    expect_eq32("stream depth is usable FIFO depth", read_data, STREAM_USABLE_DEPTH);
    expect_empty_fifo();

    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);

    for (round_idx = 0; round_idx < 3; round_idx = round_idx + 1) begin
      push_idx = 0;
      guard = 0;
      axi_read(REG_FREE_SPACE, read_data);
      while ((read_data != 32'd0) && (guard < STREAM_USABLE_DEPTH + 4)) begin
        stream_push_event(read_data64[31:0] + 32'd20000 + round_idx*32'd4096 + push_idx*32'd256,
                          read_data64[63:32],
                          32'h00000000, push_idx, push_idx+1, push_idx+2, push_idx+3);
        push_idx = push_idx + 1;
        guard = guard + 1;
        repeat (4) @(posedge s_axi_aclk);
        axi_read(REG_FREE_SPACE, read_data);
      end

      wait_for_free_space(32'd0);
      axi_read(REG_OCCUPANCY, read_data);
      expect_eq32("full FIFO occupancy equals usable depth", read_data, STREAM_USABLE_DEPTH);
      axi_read(REG_STREAM_PUSHES, read_data);
      expect_true("fill accepted at least usable depth pushes", read_data >= STREAM_USABLE_DEPTH);

      soft_reset_scheduler();
      repeat (24) @(posedge s_axi_aclk);
      expect_empty_fifo();
    end

    finish_test();
  end

endmodule
