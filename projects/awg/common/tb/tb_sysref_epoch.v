`timescale 1ns/1ps

// Integration regression for the single reviewed SYSREF capture event.  The
// exact pulse which would be fanned to JESD is also consumed by the scheduler
// TIME_RELOAD_CTRL.ARM_ON_SYSREF path here.
module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_sysref_epoch.vcd";
`define TB_EXTERNAL_SYSREF_PULSE
`include "awg_timed_ctrl_tb_env.vh"

  reg raw_sysref = 1'b1;
  wire captured_sysref;
  integer epoch_edges;
  reg epoch_d;

  jesd_sysref_sync #(
    .SYNC_WIDTH(1),
    .ARM_DELAY_CYCLES(0)
  ) i_sysref_capture (
    .device_clk(sched_clk),
    .reset(sched_reset),
    .sysref_in(raw_sysref),
    .sync_in(1'b1),
    .sysref_pulse(captured_sysref),
    .sync_out());

  assign sysref_pulse = captured_sysref;

  always @(posedge sched_clk) begin
    epoch_d <= epoch;
    if (epoch != epoch_d)
      epoch_edges <= epoch_edges + 1;
  end

  task automatic drive_raw_sysref;
    input level;
    input integer cycles;
    begin
      @(negedge sched_clk);
      raw_sysref = level;
      repeat (cycles) @(posedge sched_clk);
    end
  endtask

  task automatic arm_reload;
    input [31:0] reload_lo;
    begin
      axi_write(REG_TIME_RELOAD_LO, reload_lo, 4'hf);
      axi_write(REG_TIME_RELOAD_HI, 32'h0, 4'hf);
      axi_write(REG_TIME_RELOAD_CTRL, 32'h1, 4'b0001);
      // Cover the configuration and request synchronizers before the edge.
      repeat (8) @(posedge sched_clk);
    end
  endtask

  initial begin
    epoch_edges = 0;
    epoch_d = 1'b0;

    // SYSREF is high throughout reset release.  Baseline qualification must
    // prevent the reset value from masquerading as a physical rising edge.
    raw_sysref = 1'b1;
    reset_dut();
    epoch_d = epoch;
    arm_reload(32'h00010000);
    repeat (12) @(posedge sched_clk);
    expect_eq32("reset-high baseline does not reload epoch", epoch_edges, 0);

    // Falling is not an event.  The following physical rise creates exactly
    // one captured pulse and one scheduler epoch transition.
    drive_raw_sysref(1'b0, 8);
    expect_eq32("physical falling edge does not reload epoch", epoch_edges, 0);
    drive_raw_sysref(1'b1, 10);
    expect_eq32("one physical rise creates one epoch", epoch_edges, 1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    expect_true("public TIME_NOW reloaded from first SYSREF",
                (read_data64 >= 64'h0000000000010000) &&
                (read_data64 <  64'h0000000000010200));
    repeat (12) @(posedge sched_clk);
    expect_eq32("held-high SYSREF does not double reload", epoch_edges, 1);

    // Each write-one is a fresh one-shot scheduler arm even though CTRL[0]
    // remains readable as one.  A second isolated rise must work once only.
    drive_raw_sysref(1'b0, 8);
    arm_reload(32'h00020000);
    drive_raw_sysref(1'b1, 10);
    expect_eq32("second arm accepts exactly one new rise", epoch_edges, 2);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    expect_true("public TIME_NOW reloaded from second SYSREF",
                (read_data64 >= 64'h0000000000020000) &&
                (read_data64 <  64'h0000000000020200));
    repeat (12) @(posedge sched_clk);
    expect_eq32("second held-high interval has no duplicate", epoch_edges, 2);

    finish_test();
  end
endmodule
