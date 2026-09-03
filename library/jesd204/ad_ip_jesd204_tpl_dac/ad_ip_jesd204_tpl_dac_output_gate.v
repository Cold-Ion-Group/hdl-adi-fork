// Final Release-A DAC sample gate.
//
// This block is deliberately placed after every per-channel source selector
// and immediately before JESD framing.  It therefore mutes DDS, DMA, pattern,
// PN, and IQ-corrected sources with one policy.  Zero is encoded per sample as
// either two's-complement 0 or offset-binary midscale.
`timescale 1ns/100ps

module ad_ip_jesd204_tpl_dac_output_gate #(
  parameter integer NUM_CHANNELS = 2,
  parameter integer SAMPLES_PER_CHANNEL = 4,
  parameter integer SAMPLE_WIDTH = 16,
  parameter integer UNMUTE_DELAY_CYCLES = 0
) (
  input  wire                    clk,
  input  wire [NUM_CHANNELS-1:0] output_valid,
  input  wire                    offset_binary,
  input  wire [NUM_CHANNELS*SAMPLES_PER_CHANNEL*SAMPLE_WIDTH-1:0] data_in,
  output wire [NUM_CHANNELS*SAMPLES_PER_CHANNEL*SAMPLE_WIDTH-1:0] data_out
);

  wire [SAMPLE_WIDTH-1:0] zero_code =
    {offset_binary, {(SAMPLE_WIDTH-1){1'b0}}};

  genvar ch;
  genvar sample;
  generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : g_channel
      wire output_valid_delayed;
      if (UNMUTE_DELAY_CYCLES == 0) begin : g_no_unmute_delay
        assign output_valid_delayed = output_valid[ch];
      end else if (UNMUTE_DELAY_CYCLES == 1) begin : g_one_cycle_unmute_delay
        reg valid_pipe = 1'b0;
        always @(posedge clk) begin
          if (!output_valid[ch])
            valid_pipe <= 1'b0;
          else
            valid_pipe <= 1'b1;
        end
        assign output_valid_delayed = output_valid[ch] & valid_pipe;
      end else begin : g_unmute_delay
        reg [UNMUTE_DELAY_CYCLES-1:0] valid_pipe =
          {UNMUTE_DELAY_CYCLES{1'b0}};
        always @(posedge clk) begin
          if (!output_valid[ch])
            valid_pipe <= {UNMUTE_DELAY_CYCLES{1'b0}};
          else
            valid_pipe <= {valid_pipe[UNMUTE_DELAY_CYCLES-2:0], 1'b1};
        end
        // Keep the direct input in the expression so a falling validity gate
        // mutes immediately, without waiting for the shift register to clear.
        assign output_valid_delayed = output_valid[ch] &
                                      valid_pipe[UNMUTE_DELAY_CYCLES-1];
      end
      for (sample = 0; sample < SAMPLES_PER_CHANNEL; sample = sample + 1) begin : g_sample
        localparam integer SAMPLE_LSB =
          (ch*SAMPLES_PER_CHANNEL + sample)*SAMPLE_WIDTH;
        assign data_out[SAMPLE_LSB +: SAMPLE_WIDTH] = output_valid_delayed ?
          data_in[SAMPLE_LSB +: SAMPLE_WIDTH] : zero_code;
      end
    end
  endgenerate

endmodule
