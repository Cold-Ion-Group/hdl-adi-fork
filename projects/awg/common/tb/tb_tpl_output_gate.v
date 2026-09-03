`timescale 1ns/1ps

module testbench;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [1:0] output_valid = 2'b00;
  reg offset_binary = 1'b0;
  reg [63:0] data_in = 64'h4444333322221111;
  wire [63:0] data_out;
  integer failures = 0;

  ad_ip_jesd204_tpl_dac_output_gate #(
    .NUM_CHANNELS(2),
    .SAMPLES_PER_CHANNEL(2),
    .SAMPLE_WIDTH(16),
    .UNMUTE_DELAY_CYCLES(2)
  ) dut (
    .clk(clk),
    .output_valid(output_valid),
    .offset_binary(offset_binary),
    .data_in(data_in),
    .data_out(data_out));

  task expect64;
    input [255:0] label;
    input [63:0] got;
    input [63:0] expected;
    begin
      if (got !== expected) begin
        failures = failures + 1;
        $display("FAIL: %0s got=%016x expected=%016x", label, got, expected);
      end
    end
  endtask

  initial begin
    #1;
    expect64("two's-complement closed gate", data_out, 64'h0);
    offset_binary = 1'b1;
    #1;
    expect64("offset-binary closed gate", data_out, 64'h8000800080008000);

    // Opening channel 0 is delayed long enough for a scheduled DDS pipeline
    // to replace pre-FIRE samples.  Channel 1 remains independently muted.
    @(negedge clk); output_valid = 2'b01;
    @(posedge clk); #1;
    expect64("first unmute delay cycle", data_out, 64'h8000800080008000);
    // Model stale pre-FIRE samples being replaced while the gate is closed.
    // Only the post-FIRE value may appear on the first unmuted cycle.
    @(negedge clk); data_in = 64'h8888777766665555;
    @(posedge clk); #1;
    expect64("channel 0 unmuted, channel 1 closed",
             data_out, 64'h8000800066665555);

    @(negedge clk); output_valid = 2'b11;
    @(posedge clk); #1;
    expect64("channel 1 first delay cycle",
             data_out, 64'h8000800066665555);
    @(posedge clk); #1;
    expect64("both channels unmuted", data_out, data_in);

    // Falling validity is combinationally fail-closed and does not wait for
    // the unmute-delay pipeline.
    @(negedge clk); output_valid = 2'b10; #1;
    expect64("channel 0 immediate fatal mute",
             data_out, 64'h8888777780008000);
    offset_binary = 1'b0; #1;
    expect64("format-correct two's-complement zero",
             data_out, 64'h8888777700000000);
    output_valid = 2'b00; #1;
    expect64("all sources muted", data_out, 64'h0);

    if (failures == 0) $display("SUCCESS");
    else $display("FAILED: %0d", failures);
    $finish;
  end
endmodule
