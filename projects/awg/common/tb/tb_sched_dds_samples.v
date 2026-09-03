`timescale 1ns/1ps

// Behavioural model of the Xilinx primitive used by ad_mul.  All datapath RTL
// around the primitive is the production implementation; this model preserves
// the configured signed multiply and latency for simulator portability.
module MULT_MACRO #(
  parameter DEVICE = "7SERIES",
  parameter integer LATENCY = 3,
  parameter integer WIDTH_A = 17,
  parameter integer WIDTH_B = 17
) (
  output wire [WIDTH_A+WIDTH_B-1:0] P,
  input  wire [WIDTH_A-1:0] A,
  input  wire [WIDTH_B-1:0] B,
  input  wire CE,
  input  wire CLK,
  input  wire RST
);
  reg signed [WIDTH_A+WIDTH_B-1:0] pipe [0:LATENCY-1];
  integer i;
  always @(posedge CLK) begin
    if (RST) begin
      for (i = 0; i < LATENCY; i = i + 1)
        pipe[i] <= 'sd0;
    end else if (CE) begin
      pipe[0] <= $signed(A) * $signed(B);
      for (i = 1; i < LATENCY; i = i + 1)
        pipe[i] <= pipe[i-1];
    end
  end
  assign P = pipe[LATENCY-1];
endmodule

module testbench;
  localparam integer FFT_SAMPLES = 64;
  localparam integer FUND_BIN = 4; // 0x1000 / 2^16 * 64

  reg clk = 1'b0;
  always #2 clk = ~clk;

  reg data_sync = 1'b1;
  reg [15:0] axi_scale_0 = 16'h1000;
  reg [15:0] axi_init_0 = 16'h0000;
  reg [15:0] axi_incr_0 = 16'h0800;
  reg [15:0] axi_scale_1 = 16'h2000; // deliberately nonzero tone 1
  reg [15:0] axi_init_1 = 16'h0000;
  reg [15:0] axi_incr_1 = 16'h1000;
  reg [15:0] sched_scale_sm = 16'h2ccc;
  reg [15:0] sched_init = 16'h0000;
  reg [15:0] sched_incr = 16'h1000;
  reg sched_apply = 1'b0;
  reg [15:0] reference_scale = 16'h1000;
  reg [15:0] reference_init = 16'h0000;
  reg [15:0] reference_incr = 16'h0800;
  reg [15:0] duplicate_scale = 16'h2ccc;
  reg gate_valid = 1'b0;

  wire [15:0] mux_scale_0;
  wire [15:0] mux_init_0;
  wire [15:0] mux_incr_0;
  wire [15:0] mux_scale_1;
  wire [15:0] mux_init_1;
  wire [15:0] mux_incr_1;
  wire [63:0] scheduled_data;
  wire [63:0] reference_data;
  wire [63:0] duplicated_data;
  wire [63:0] safe_scheduled_data;

  integer failures = 0;
  integer n;
  integer k;
  integer beat;
  integer lane;
  integer mismatch_count;
  integer signed_sample;
  real fft_re [0:FFT_SAMPLES/2];
  real fft_im [0:FFT_SAMPLES/2];
  real angle;
  real bin_power;
  real fundamental_power;
  real largest_spur_power;

  ad_ip_jesd204_tpl_dac_sched_mux #(
    .NUM_CHANNELS(1),
    .DDS_PHASE_DW(16)
  ) i_sched_mux (
    .axi_scale_0(axi_scale_0),
    .axi_init_0(axi_init_0),
    .axi_incr_0(axi_incr_0),
    .axi_scale_1(axi_scale_1),
    .axi_init_1(axi_init_1),
    .axi_incr_1(axi_incr_1),
    .sched_scale_sm(sched_scale_sm),
    .sched_init(sched_init),
    .sched_incr(sched_incr),
    .sched_apply(sched_apply),
    .scale_0(mux_scale_0),
    .init_0(mux_init_0),
    .incr_0(mux_incr_0),
    .scale_1(mux_scale_1),
    .init_1(mux_init_1),
    .incr_1(mux_incr_1));

  ad_dds #(
    .DDS_DW(16), .PHASE_DW(16), .DDS_TYPE(1),
    .CORDIC_DW(16), .CORDIC_PHASE_DW(16), .CLK_RATIO(4)
  ) i_scheduled_dds (
    .clk(clk), .dac_dds_format(1'b0), .dac_data_sync(data_sync),
    .dac_valid(1'b1),
    .tone_1_scale(mux_scale_0), .tone_2_scale(mux_scale_1),
    .tone_1_init_offset(mux_init_0), .tone_2_init_offset(mux_init_1),
    .tone_1_freq_word(mux_incr_0), .tone_2_freq_word(mux_incr_1),
    .dac_dds_data(scheduled_data));

  // Golden path: the same production DDS fed explicitly as one tone.
  ad_dds #(
    .DDS_DW(16), .PHASE_DW(16), .DDS_TYPE(1),
    .CORDIC_DW(16), .CORDIC_PHASE_DW(16), .CLK_RATIO(4)
  ) i_reference_dds (
    .clk(clk), .dac_dds_format(1'b0), .dac_data_sync(data_sync),
    .dac_valid(1'b1),
    .tone_1_scale(reference_scale), .tone_2_scale(16'h0000),
    .tone_1_init_offset(reference_init), .tone_2_init_offset(axi_init_1),
    .tone_1_freq_word(reference_incr), .tone_2_freq_word(axi_incr_1),
    .dac_dds_data(reference_data));

  // Historical broken mapping, retained only as a negative control: event-v1
  // scale/phase/frequency was applied to both tones and summed.
  ad_dds #(
    .DDS_DW(16), .PHASE_DW(16), .DDS_TYPE(1),
    .CORDIC_DW(16), .CORDIC_PHASE_DW(16), .CLK_RATIO(4)
  ) i_duplicated_dds (
    .clk(clk), .dac_dds_format(1'b0), .dac_data_sync(data_sync),
    .dac_valid(1'b1),
    .tone_1_scale(duplicate_scale), .tone_2_scale(duplicate_scale),
    .tone_1_init_offset(sched_init), .tone_2_init_offset(sched_init),
    .tone_1_freq_word(sched_incr), .tone_2_freq_word(sched_incr),
    .dac_dds_data(duplicated_data));

  // Production final safety boundary, configured with the AWG's frozen
  // 32-link-clock first-sample budget.
  ad_ip_jesd204_tpl_dac_output_gate #(
    .NUM_CHANNELS(1), .SAMPLES_PER_CHANNEL(4), .SAMPLE_WIDTH(16),
    .UNMUTE_DELAY_CYCLES(32)
  ) i_output_gate (
    .clk(clk), .output_valid(gate_valid), .offset_binary(1'b0),
    .data_in(scheduled_data), .data_out(safe_scheduled_data));

  task automatic fail;
    input [255:0] label;
    begin
      failures = failures + 1;
      $display("FAIL: %0s", label);
    end
  endtask

  task automatic check_sample_scale;
    input [15:0] sign_magnitude;
    input [15:0] twos_complement;
    input [255:0] label;
    integer sample_index;
    begin
      @(negedge clk);
      sched_scale_sm = sign_magnitude;
      reference_scale = twos_complement;
      duplicate_scale = twos_complement;
      repeat (32) @(posedge clk);
      if (mux_scale_0 !== twos_complement || mux_scale_1 !== 16'h0000)
        fail(label);
      for (sample_index = 0; sample_index < 16; sample_index = sample_index + 1) begin
        @(negedge clk);
        if (scheduled_data !== reference_data)
          fail(label);
        if ((twos_complement == 16'h0000) &&
            ((scheduled_data !== 64'h0000000000000000) ||
             (safe_scheduled_data !== 64'h0000000000000000)))
          fail("zero-scale scheduled DDS did not settle to digital zero");
      end
    end
  endtask

  initial begin
    // Establish deterministic phase, then fill the scheduled instance with
    // intentionally nonzero AXI tone-0 and tone-1 samples while its final gate
    // is closed.  The one-tone reference follows AXI tone 0 over this interval.
    repeat (5) @(posedge clk);
    @(negedge clk);
    data_sync = 1'b0;
    repeat (40) @(posedge clk);

    // A FIRE without phase reinitialisation changes persistent ownership and
    // opens output_valid together.  The 32-cycle gate budget must hide every
    // old dual-tone AXI sample while both production DDS pipelines converge.
    @(negedge clk);
    sched_apply = 1'b1;
    reference_scale = 16'h2ccc;
    reference_init = sched_init;
    reference_incr = sched_incr;
    gate_valid = 1'b1;
    for (n = 0; n < 31; n = n + 1) begin
      @(posedge clk); #1;
      if (safe_scheduled_data !== 64'h0000000000000000)
        fail("final gate exposed a pre-FIRE DDS pipeline sample");
    end
    @(posedge clk); #1;
    if (^safe_scheduled_data === 1'bx)
      fail("first unmuted scheduled sample is unknown/stale");
    if (safe_scheduled_data !== reference_data)
      fail("first unmuted sample differs from one-tone reference");
    repeat (16) @(posedge clk);

    if (mux_scale_0 !== 16'h2ccc || mux_scale_1 !== 16'h0000)
      fail("scheduler mux did not convert tone 0 and suppress tone 1");

    // Also cover the phase-reinitialised case and align the duplicated-tone
    // negative control before bit-exact/FFT sampling.
    @(negedge clk);
    data_sync = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    data_sync = 1'b0;
    repeat (48) @(posedge clk);

    mismatch_count = 0;
    for (k = 0; k <= FFT_SAMPLES/2; k = k + 1) begin
      fft_re[k] = 0.0;
      fft_im[k] = 0.0;
    end

    // Bit-exact output comparison and a small rectangular-window DFT over an
    // integer number of carrier periods.  The corrected stream must equal the
    // explicit one-tone reference on every sample, differ from the duplicated
    // negative control, and contain only the expected carrier (quantization
    // residual is allowed below -20 dBc in power).
    for (beat = 0; beat < FFT_SAMPLES/4; beat = beat + 1) begin
      @(negedge clk);
      if (scheduled_data !== reference_data)
        fail("scheduled DDS sample differs from one-tone reference");
      if (scheduled_data !== duplicated_data)
        mismatch_count = mismatch_count + 1;
      for (lane = 0; lane < 4; lane = lane + 1) begin
        n = beat*4 + lane;
        signed_sample = $signed(scheduled_data[16*lane +: 16]);
        for (k = 0; k <= FFT_SAMPLES/2; k = k + 1) begin
          angle = 6.283185307179586 * k * n / FFT_SAMPLES;
          fft_re[k] = fft_re[k] + signed_sample * $cos(angle);
          fft_im[k] = fft_im[k] - signed_sample * $sin(angle);
        end
      end
    end

    if (mismatch_count == 0)
      fail("scheduled DDS still matches historical duplicated-tone path");

    fundamental_power = fft_re[FUND_BIN]*fft_re[FUND_BIN] +
                        fft_im[FUND_BIN]*fft_im[FUND_BIN];
    largest_spur_power = 0.0;
    for (k = 1; k <= FFT_SAMPLES/2; k = k + 1) begin
      if (k != FUND_BIN) begin
        bin_power = fft_re[k]*fft_re[k] + fft_im[k]*fft_im[k];
        if (bin_power > largest_spur_power)
          largest_spur_power = bin_power;
      end
    end
    if (fundamental_power <= 0.0)
      fail("FFT did not find scheduled carrier");
    if (largest_spur_power * 100.0 >= fundamental_power)
      fail("FFT spur exceeds -20 dBc power bound");

    // Compare actual production DDS samples against a one-tone AXI reference
    // across every required v1 scale boundary, not merely the mux controls.
    check_sample_scale(16'h2000, 16'h2000, "+0.5 sample mismatch");
    check_sample_scale(16'h2ccc, 16'h2ccc, "+0.7 sample mismatch");
    check_sample_scale(16'h4000, 16'h4000, "+1.0 sample mismatch");
    check_sample_scale(16'ha000, 16'he000, "-0.5 sample mismatch");
    check_sample_scale(16'hc000, 16'hc000, "-1.0 sample mismatch");
    check_sample_scale(16'hffff, 16'h8001, "boundary-negative sample mismatch");
    // Scale zero is the explicit-silence mechanism used by a final EOF event.
    // Ownership and final output validity remain asserted throughout.
    check_sample_scale(16'h0000, 16'h0000, "zero sample mismatch");

    // Ownership is persistent.  Releasing it returns the intentionally
    // different AXI settings without modifying either tone's saved controls.
    sched_apply = 1'b0;
    #1;
    if (mux_scale_0 !== axi_scale_0 || mux_scale_1 !== axi_scale_1 ||
        mux_init_0 !== axi_init_0 || mux_init_1 !== axi_init_1 ||
        mux_incr_0 !== axi_incr_0 || mux_incr_1 !== axi_incr_1)
      fail("release did not restore both AXI DDS tones");

    if (failures == 0)
      $display("SUCCESS");
    else
      $display("FAILED: %0d", failures);
    $finish;
  end
endmodule
