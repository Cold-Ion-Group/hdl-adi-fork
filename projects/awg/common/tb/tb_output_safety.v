`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam integer STREAM_USABLE_DEPTH = (1 << TB_STREAM_ADDR_WIDTH) - 1;
  localparam VCD_FILE = "tb_output_safety.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  integer i;
  integer timeout;
  reg reinit_seen = 1'b0;

  always @(posedge sched_clk) begin
    if (sched_phase_reinit)
      reinit_seen <= 1'b1;
  end

  task automatic wait_for_commit;
    begin
      timeout = 0;
      while (!marker_commit && timeout < 1024) begin
        @(posedge sched_clk);
        timeout = timeout + 1;
      end
      if (timeout >= 1024)
        test_fail("marker_commit timeout");
      @(negedge sched_clk);
    end
  endtask

  initial begin
    reset_dut();
    expect_eq32("reset closes every output gate",
                {24'h0, sched_output_valid}, 32'h0);

    set_stream_mode(1'b1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    // Event v1 channel 1: scale=-0.5 sign magnitude, init=0x11223344,
    // increment=0x55667788, EOF and phase-reinitialise set.
    stream_push_event(read_data64[31:0] + 32'd768,
                      read_data64[63:32],
                      32'h00010003,
                      32'h3344a000,
                      32'h77881122,
                      32'h00005566,
                      32'h00000000);
    arm_scheduler();
    repeat (12) @(posedge sched_clk);
    expect_eq32("ARMED keeps every output gate closed",
                {24'h0, sched_output_valid}, 32'h0);
    run_scheduler();
    repeat (12) @(posedge sched_clk);
    expect_eq32("pre-FIRE RUNNING keeps every output gate closed",
                {24'h0, sched_output_valid}, 32'h0);
    expect_eq1("phase-reinit is inactive before FIRE", sched_phase_reinit, 1'b0);

    wait_for_commit();
    expect_eq1("event-v1 phase-reinit pulses with FIRE", reinit_seen, 1'b1);
    expect_eq1("selected channel opens on FIRE", sched_output_valid[1], 1'b1);
    expect_eq1("unselected channel remains closed", sched_output_valid[0], 1'b0);
    expect_eq1("selected channel owns DDS", sched_apply_s[1], 1'b1);
    expect_eq1("unselected channel does not own DDS", sched_apply_s[0], 1'b0);
    expect_eq32("event-v1 scale maps to selected channel",
                {16'h0, sched_scale_s[16 +: 16]}, 32'h0000a000);
    expect_eq32("event-v1 phase init maps once",
                sched_init_s[32 +: 32], 32'h11223344);
    expect_eq32("event-v1 increment maps once",
                sched_incr_s[32 +: 32], 32'h55667788);

    wait_for_done();
    expect_eq1("DONE holds selected channel output", sched_output_valid[1], 1'b1);
    expect_eq1("DONE holds scheduler ownership", sched_apply_s[1], 1'b1);

    // A fatal extension event overrides DONE hold immediately in the scheduler
    // domain and uses the explicit extension error code.
    @(negedge sched_clk);
    extension_error_toggle_in = ~extension_error_toggle_in;
    timeout = 0;
    while ((sched_output_valid !== 8'h00) && timeout < 32) begin
      @(posedge sched_clk);
      timeout = timeout + 1;
    end
    expect_eq32("extension fault closes all output gates",
                {24'h0, sched_output_valid}, 32'h0);
    wait_for_error();
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("extension fault code", read_data, 32'h00000004);

    stop_scheduler();
    repeat (12) @(posedge sched_clk);
    expect_eq32("STOP keeps output closed", {24'h0, sched_output_valid}, 32'h0);
    expect_eq32("STOP releases scheduler ownership", {24'h0, sched_apply_s}, 32'h0);
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);

    // DONE intentionally holds output validity.  A final explicit zero-scale
    // event is how software requests a silent held DONE waveform.
    set_stream_mode(1'b1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd512,
                      read_data64[63:32],
                      32'h00000002,
                      32'h00000000, 32'h0, 32'h0, 32'h0);
    arm_scheduler();
    run_scheduler();
    wait_for_commit();
    wait_for_done();
    expect_eq1("zero EOF retains DONE output validity", sched_output_valid[0], 1'b1);
    expect_eq1("zero EOF retains scheduler ownership", sched_apply_s[0], 1'b1);
    expect_eq32("zero EOF programs explicit silence",
                {16'h0, sched_scale_s[15:0]}, 32'h00000000);
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);

    // A refused software-stream push is fatal, reports code 5, and cannot
    // accidentally open output even though the staged AXI DDS may be nonzero.
    set_stream_mode(1'b1);
    for (i = 0; i < STREAM_USABLE_DEPTH + 2; i = i + 1) begin
      axi_read(REG_FREE_SPACE, read_data);
      if (read_data == 32'd0)
        i = STREAM_USABLE_DEPTH + 2;
      else
        stream_push_event(32'd10000 + i*32'd64, 32'd0, 32'h0,
                          32'h00004000, 32'h0, 32'h0, 32'h0);
    end
    axi_read(REG_FREE_SPACE, read_data);
    expect_eq32("FIFO full before refused push", read_data, 32'h0);
    stream_push_event(32'd20000, 32'd0, 32'h00000002,
                      32'h00004000, 32'h0, 32'h0, 32'h0);
    wait_for_error();
    axi_read(REG_STATUS, read_data);
    expect_eq32("overflow STATUS packing", read_data, 32'h00000508);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("overflow error code", read_data, 32'h00000005);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("overflow raises sticky ERROR IRQ", read_data[1], 1'b1);
    expect_eq32("overflow leaves all output gates closed",
                {24'h0, sched_output_valid}, 32'h0);

    finish_test();
  end
endmodule
