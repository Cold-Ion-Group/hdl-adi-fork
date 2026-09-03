// Release-A scheduler ownership mux for the JESD DAC TPL.
//
// Event-v1 carries exactly one ADI sign-magnitude scale/phase/frequency tuple
// for one physical channel.  The normal AXI path has already converted its DDS
// scales to signed two's-complement coefficients in up_dac_channel; scheduled
// scales bypass that block and therefore require the identical conversion here
// exactly once.  Tone 1 remains available to AXI operation, but is suppressed
// for the duration of scheduler ownership.
`timescale 1ns/100ps

module ad_ip_jesd204_tpl_dac_sched_mux #(
  parameter integer NUM_CHANNELS = 2,
  parameter integer DDS_PHASE_DW = 16
) (
  input  wire [NUM_CHANNELS*16-1:0]           axi_scale_0,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] axi_init_0,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] axi_incr_0,
  input  wire [NUM_CHANNELS*16-1:0]           axi_scale_1,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] axi_init_1,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] axi_incr_1,
  input  wire [NUM_CHANNELS*16-1:0]           sched_scale_sm,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] sched_init,
  input  wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] sched_incr,
  input  wire [NUM_CHANNELS-1:0]              sched_apply,
  output wire [NUM_CHANNELS*16-1:0]           scale_0,
  output wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] init_0,
  output wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] incr_0,
  output wire [NUM_CHANNELS*16-1:0]           scale_1,
  output wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] init_1,
  output wire [NUM_CHANNELS*DDS_PHASE_DW-1:0] incr_1
);

  function [15:0] sm2tc;
    input [15:0] din;
    reg [15:0] magnitude;
    begin
      magnitude = {1'b0, din[14:0]};
      sm2tc = din[15] ? (~magnitude + 1'b1) : magnitude;
    end
  endfunction

  genvar ch;
  generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : g_channel
      assign scale_0[16*ch +: 16] = sched_apply[ch] ?
        sm2tc(sched_scale_sm[16*ch +: 16]) : axi_scale_0[16*ch +: 16];
      assign init_0[DDS_PHASE_DW*ch +: DDS_PHASE_DW] = sched_apply[ch] ?
        sched_init[DDS_PHASE_DW*ch +: DDS_PHASE_DW] :
        axi_init_0[DDS_PHASE_DW*ch +: DDS_PHASE_DW];
      assign incr_0[DDS_PHASE_DW*ch +: DDS_PHASE_DW] = sched_apply[ch] ?
        sched_incr[DDS_PHASE_DW*ch +: DDS_PHASE_DW] :
        axi_incr_0[DDS_PHASE_DW*ch +: DDS_PHASE_DW];

      assign scale_1[16*ch +: 16] = sched_apply[ch] ?
        16'h0000 : axi_scale_1[16*ch +: 16];
      // Tone 1's phase controls remain under AXI ownership.  They are harmless
      // while its scale is zero and resume without receiving event-v1 fields.
      assign init_1[DDS_PHASE_DW*ch +: DDS_PHASE_DW] =
        axi_init_1[DDS_PHASE_DW*ch +: DDS_PHASE_DW];
      assign incr_1[DDS_PHASE_DW*ch +: DDS_PHASE_DW] =
        axi_incr_1[DDS_PHASE_DW*ch +: DDS_PHASE_DW];
    end
  endgenerate

endmodule
