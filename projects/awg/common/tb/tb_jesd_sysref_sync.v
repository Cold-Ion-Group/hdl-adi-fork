`timescale 1ns/1ps

module tb_jesd_sysref_sync;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg reset0 = 1'b1;
  reg sysref0 = 1'b0;
  reg [1:0] sync0 = 2'b11;
  wire pulse0;
  wire [1:0] sync0_out;

  reg reset_delay = 1'b1;
  reg sysref_delay = 1'b0;
  wire pulse_delay;

  integer failures = 0;
  integer pulse_count0 = 0;
  integer pulse_count_delay = 0;
  reg pulse0_d = 1'b0;
  reg pulse_delay_d = 1'b0;
  integer baseline_count;

  jesd_sysref_sync #(
    .SYNC_WIDTH(2),
    .ARM_DELAY_CYCLES(0)
  ) dut0 (
    .device_clk(clk),
    .reset(reset0),
    .sysref_in(sysref0),
    .sync_in(sync0),
    .sysref_pulse(pulse0),
    .sync_out(sync0_out));

  jesd_sysref_sync #(
    .SYNC_WIDTH(1),
    .ARM_DELAY_CYCLES(3)
  ) dut_delay (
    .device_clk(clk),
    .reset(reset_delay),
    .sysref_in(sysref_delay),
    .sync_in(1'b1),
    .sysref_pulse(pulse_delay),
    .sync_out());

  task fail;
    input [255:0] label;
    begin
      failures = failures + 1;
      $display("FAIL: %0s", label);
    end
  endtask

  task drive0;
    input level;
    input integer cycles;
    begin
      @(negedge clk);
      sysref0 = level;
      repeat (cycles) @(posedge clk);
    end
  endtask

  always @(posedge clk) begin
    if (pulse0) begin
      pulse_count0 = pulse_count0 + 1;
      if (pulse0_d)
        fail("zero-delay SYSREF pulse wider than one clock");
    end
    if (pulse_delay) begin
      pulse_count_delay = pulse_count_delay + 1;
      if (pulse_delay_d)
        fail("delayed-arm SYSREF pulse wider than one clock");
    end
    pulse0_d <= pulse0;
    pulse_delay_d <= pulse_delay;
  end

  initial begin
    // Establish a low baseline.  Falling transitions must never be events.
    repeat (4) @(posedge clk);
    reset0 = 1'b0;
    repeat (6) @(posedge clk);
    if (pulse_count0 != 0) fail("pulse while low after reset");

    drive0(1'b1, 5);
    if (pulse_count0 != 1) fail("first physical rising edge not captured once");
    drive0(1'b0, 5);
    if (pulse_count0 != 1) fail("physical falling edge generated a pulse");
    drive0(1'b1, 8);
    if (pulse_count0 != 2) fail("second physical rising edge not captured once");

    // Reset-high is a baseline, not an edge.  A new low-to-high transition is
    // required after the synchronizer has filled.
    @(negedge clk);
    reset0 = 1'b1;
    sysref0 = 1'b1;
    repeat (4) @(posedge clk);
    baseline_count = pulse_count0;
    reset0 = 1'b0;
    repeat (10) @(posedge clk);
    if (pulse_count0 != baseline_count)
      fail("reset release while SYSREF high generated a false event");
    drive0(1'b0, 5);
    if (pulse_count0 != baseline_count)
      fail("fall after reset-high generated an event");
    drive0(1'b1, 5);
    if (pulse_count0 != baseline_count + 1)
      fail("first real rise after reset-high was not captured");

    // SYNC~ remains an ordinary two-flop synchronizer.
    @(negedge clk);
    sync0 = 2'b00;
    repeat (3) @(posedge clk);
    if (sync0_out !== 2'b00) fail("SYNC input did not synchronize low");

    // ARM_DELAY_CYCLES is applied only after baseline qualification.  A rise
    // during that extra delay is ignored; a subsequent physical rise is kept.
    repeat (3) @(posedge clk);
    @(negedge clk);
    reset_delay = 1'b0;
    sysref_delay = 1'b1;
    repeat (5) @(posedge clk);
    if (pulse_count_delay != 0)
      fail("delayed arm accepted an early rise");
    @(negedge clk); sysref_delay = 1'b0;
    while (!dut_delay.arm) @(posedge clk);
    repeat (3) @(posedge clk);
    @(negedge clk); sysref_delay = 1'b1;
    repeat (5) @(posedge clk);
    if (pulse_count_delay != 1)
      fail("delayed arm did not accept the next physical rise");

    if (failures == 0) $display("SUCCESS");
    else $display("FAILED: %0d", failures);
    $finish;
  end
endmodule
