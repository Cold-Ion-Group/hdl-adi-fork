`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam integer STREAM_USABLE_DEPTH = (1 << TB_STREAM_ADDR_WIDTH) - 1;
  localparam VCD_FILE = "tb_dma_stop_soft_reset.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  task automatic wait_for_occupancy;
    input [31:0] expected;
    integer wait_count;
    begin
      wait_count = 0;
      axi_read(REG_OCCUPANCY, read_data);
      while ((read_data !== expected) && (wait_count < 128)) begin
        repeat (2) @(posedge s_axi_aclk);
        axi_read(REG_OCCUPANCY, read_data);
        wait_count = wait_count + 1;
      end
      expect_eq32("occupancy wait", read_data, expected);
    end
  endtask

  initial begin
    reset_dut();

    axi_write(REG_STREAM_CTRL, 32'h00000009, 4'b0001);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);

    dma_push_word(pack_event(read_data64[31:0] + 32'd10000, read_data64[63:32],
                             32'h00000000, 32'h1, 32'h2, 32'h3, 32'h4));
    dma_push_word(pack_event(read_data64[31:0] + 32'd11000, read_data64[63:32],
                             32'h00000002, 32'h5, 32'h6, 32'h7, 32'h8));

    wait_for_occupancy(32'd2);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("DMA preload before ARM", read_data, 32'd2);

    arm_scheduler();
    stop_scheduler();
    repeat (24) @(posedge s_axi_aclk);

    axi_read(REG_STATUS, read_data);
    expect_eq32("stop returns scheduler to idle", read_data, 32'h00000000);
    axi_read(REG_OCCUPANCY, read_data);
    expect_true("stop leaves stream data buffered", read_data > 0);
    axi_read(REG_FREE_SPACE, read_data);
    expect_true("stop does not restore all free space", read_data < STREAM_USABLE_DEPTH);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("stop does not clear DMA push counter", read_data, 32'd2);

    soft_reset_scheduler();
    repeat (24) @(posedge s_axi_aclk);

    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("soft reset flushes DMA stream FIFO", read_data, 32'd0);
    axi_read(REG_FREE_SPACE, read_data);
    expect_eq32("soft reset restores all free space", read_data, STREAM_USABLE_DEPTH);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("soft reset clears DMA push counter", read_data, 32'd0);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("soft reset clears EOF sticky", read_data[2], 1'b0);

    finish_test();
  end

endmodule
