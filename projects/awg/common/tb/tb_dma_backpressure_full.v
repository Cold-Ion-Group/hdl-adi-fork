`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam integer STREAM_USABLE_DEPTH = (1 << TB_STREAM_ADDR_WIDTH) - 1;
  localparam VCD_FILE = "tb_dma_backpressure_full.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  reg [255:0] stalled_dma_event;
  integer i;
  integer timeout;
  integer accepted;

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

  task automatic wait_for_dma_ready;
    input expected;
    integer wait_count;
    begin
      wait_count = 0;
      while ((dma_s_axis_tready !== expected) && (wait_count < 128)) begin
        @(posedge s_axi_aclk);
        wait_count = wait_count + 1;
      end
      expect_eq1("DMA ready wait", dma_s_axis_tready, expected);
    end
  endtask

  initial begin
    reset_dut();

    axi_read(REG_STREAM_DEPTH, read_data);
    expect_eq32("usable depth reflects one-open-slot FIFO", read_data, STREAM_USABLE_DEPTH);

    axi_write(REG_STREAM_CTRL, 32'h00000009, 4'b0001);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);

    accepted = 0;
    for (i = 0; i < STREAM_USABLE_DEPTH + 2; i = i + 1) begin
      if (dma_s_axis_tready !== 1'b1)
        i = STREAM_USABLE_DEPTH + 2;
      else begin
        dma_push_word(pack_event(read_data64[31:0] + 32'd20000 + i*32'd256,
                                  read_data64[63:32],
                                  32'h00000000, i, i+1, i+2, i+3));
        accepted = accepted + 1;
        repeat (8) @(posedge s_axi_aclk);
      end
    end

    wait_for_free_space(32'd0);
    wait_for_dma_ready(1'b0);
    axi_read(REG_FREE_SPACE, read_data);
    expect_eq32("DMA fill exhausted FIFO free space", read_data, 32'd0);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("DMA fill reached usable depth", read_data, STREAM_USABLE_DEPTH);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("DMA pushes counted up to usable depth", read_data, accepted);

    stalled_dma_event = pack_event(read_data64[31:0] + 32'd22000,
                                   read_data64[63:32],
                                   32'h00000002, 32'ha, 32'hb, 32'hc, 32'hd);
    @(negedge s_axi_aclk);
    dma_s_axis_tdata = stalled_dma_event;
    dma_s_axis_tvalid = 1'b1;
    repeat (8) begin
      @(posedge s_axi_aclk);
      expect_eq1("DMA tready stays low while FIFO full", dma_s_axis_tready, 1'b0);
    end

    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("stalled DMA beat not counted", read_data, accepted);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("DMA backpressure does not set software overflow sticky", read_data[1], 1'b0);

    arm_scheduler();
    run_scheduler();

    timeout = 0;
    while ((dma_s_axis_tready !== 1'b1) && (timeout <= 256)) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout > 256)
      test_fail("DMA tready did not recover after scheduler prefetch");

    @(negedge s_axi_aclk);
    dma_s_axis_tvalid = 1'b0;
    dma_s_axis_tdata = 256'h0;
    repeat (8) @(posedge s_axi_aclk);

    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("backpressured DMA beat accepted after free slot", read_data, accepted + 1);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("DMA refill still has no software overflow sticky", read_data[1], 1'b0);

    stop_scheduler();
    finish_test();
  end

endmodule
