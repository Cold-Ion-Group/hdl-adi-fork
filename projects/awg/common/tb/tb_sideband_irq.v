`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_sideband_irq.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  integer commits;
  integer toggles;
  reg marker_commit_d;
  reg event_toggle_d;
  reg epoch_before;
  reg error_toggle_before;

  always @(posedge sched_clk) begin
    marker_commit_d <= marker_commit;
    event_toggle_d <= event_toggle;
    if (marker_commit && !marker_commit_d)
      commits <= commits + 1;
    if (event_toggle != event_toggle_d) begin
      if (toggles == 0 && event_seq_gray !== 16'h0000)
        test_fail("first event sequence is not Gray zero");
      if (toggles == 1 && event_seq_gray !== 16'h0001)
        test_fail("second event sequence is not Gray one");
      toggles <= toggles + 1;
    end
  end

  initial begin
    commits = 0;
    toggles = 0;
    marker_commit_d = 1'b0;
    event_toggle_d = 1'b0;
    reset_dut();
    event_toggle_d = event_toggle;

    // LOAD_NOW is an applied epoch operation, not merely a software request.
    epoch_before = epoch;
    axi_write(REG_TIME_RELOAD_LO, 32'h00000100, 4'hf);
    axi_write(REG_TIME_RELOAD_HI, 32'h00000000, 4'hf);
    axi_write(REG_TIME_RELOAD_CTRL, 32'h00000002, 4'b0001);
    repeat (16) @(posedge sched_clk);
    expect_true("LOAD_NOW toggles epoch", epoch != epoch_before);
    expect_eq32("epoch resets sequence", {16'h0, event_seq_gray}, 32'h0);

    // CTRL[8] enables every pending source while per-source IRQ_ENABLE is zero.
    axi_write(REG_CTRL, 32'h00000100, 4'b0010);
    axi_read(REG_IRQ_ENABLE, read_data);
    expect_eq32("per-source mask remains zero", read_data, 32'h0);

    set_stream_mode(1'b1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd320, read_data64[63:32],
                      32'h00000000, 32'h1, 32'h2, 32'h3, 32'h4);
    stream_push_event(read_data64[31:0] + 32'd352, read_data64[63:32],
                      32'h00000002, 32'h5, 32'h6, 32'h7, 32'h8);
    arm_scheduler();
    run_scheduler();
    wait_for_done();
    repeat (8) @(posedge sched_clk);

    expect_eq32("one marker per FIRE", commits, 2);
    expect_eq32("one sideband toggle per FIRE", toggles, 2);
    expect_true("legacy global IRQ gate asserts", irq === 1'b1);
    // EOF may coincide with a final low-watermark transition; clear every
    // pending source after the final scheduler snapshot has crossed the CDC.
    repeat (12) @(posedge s_axi_aclk);
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    repeat (8) @(posedge s_axi_aclk);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq32("W1C clears pending sources", read_data, 32'h0);
    expect_eq1("W1C clears global-gated IRQ", irq, 1'b0);

    // An upstream decoder failure is folded into the same held error/toggle
    // bundle used by the measurement appliance.
    error_toggle_before = error_toggle;
    extension_error_in = 1'b1;
    extension_error_toggle_in = ~extension_error_toggle_in;
    repeat (8) @(posedge sched_clk);
    expect_eq1("extension error holds AWG error", awg_error, 1'b1);
    expect_true("extension error toggles sideband", error_toggle != error_toggle_before);
    extension_error_in = 1'b0;
    finish_test();
  end
endmodule
