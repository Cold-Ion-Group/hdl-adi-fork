`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_dma_mode_mux.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  reg [255:0] dma_event0;
  reg [255:0] dma_event1;

  initial begin
    reset_dut();

    expect_eq1("DMA ready low while stream mode disabled", dma_s_axis_tready, 1'b0);

    set_stream_mode(1'b1);
    stream_push_event(32'd2000, 32'd0, 32'h0, 32'h1, 32'h2, 32'h3, 32'h4);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("software stream push accepted when DMA disabled", read_data, 32'd1);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("software stream push reached FIFO", read_data, 32'd1);

    dma_s_axis_tdata = pack_event(32'd2100, 32'd0, 32'h0,
                                  32'h5, 32'h6, 32'h7, 32'h8);
    dma_s_axis_tvalid = 1'b1;
    repeat (4) @(posedge s_axi_aclk);
    expect_eq1("DMA ready remains low when DMA mode disabled", dma_s_axis_tready, 1'b0);
    @(negedge s_axi_aclk);
    dma_s_axis_tvalid = 1'b0;
    dma_s_axis_tdata = 256'h0;

    soft_reset_scheduler();
    repeat (16) @(posedge s_axi_aclk);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("push counter cleared before DMA-mode phase", read_data, 32'd0);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("FIFO empty before DMA-mode phase", read_data, 32'd0);

    axi_write(REG_STREAM_CTRL, 32'h00000009, 4'b0001);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("stream mode config bit set", read_data[0], 1'b1);
    expect_eq1("DMA mode config bit set", read_data[3], 1'b1);

    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    dma_event0 = pack_event(read_data64[31:0] + 32'd512, read_data64[63:32],
                            32'h00000000, 32'h11, 32'h12, 32'h13, 32'h14);
    dma_event1 = pack_event(read_data64[31:0] + 32'd640, read_data64[63:32],
                            32'h00000002, 32'h21, 32'h22, 32'h23, 32'h24);

    dma_push_word(dma_event0);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("DMA beat counted as stream push", read_data, 32'd1);
    axi_read(REG_OCCUPANCY, read_data);
    expect_eq32("DMA beat reached FIFO", read_data, 32'd1);

    stream_push_event(read_data64[31:0] + 32'd2064, read_data64[63:32],
                      32'h00000002, 32'h31, 32'h32, 32'h33, 32'h34);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("AXI-Lite stream push ignored in DMA mode", read_data, 32'd1);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("software overflow not set in DMA mode", read_data[1], 1'b0);

    arm_scheduler();
    axi_write(REG_STREAM_CTRL, 32'h00000001, 4'b0001);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("DMA config bit writable after ARM", read_data[3], 1'b0);

    dma_push_word(dma_event1);
    axi_read(REG_STREAM_PUSHES, read_data);
    expect_eq32("DMA source stayed locked after ARM", read_data, 32'd2);

    run_scheduler();
    wait_for_done();
    axi_read(REG_COMMIT_COUNT, read_data);
    expect_eq32("DMA-fed stream fired both events", read_data, 32'd2);
    axi_read(REG_STREAM_CTRL, read_data);
    expect_eq1("DMA-fed EOF consumed", read_data[2], 1'b1);

    finish_test();
  end

endmodule
