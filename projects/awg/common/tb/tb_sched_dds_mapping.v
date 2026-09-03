`timescale 1ns/1ps

module testbench;
  reg [31:0] axi_scale_0 = 32'h11112222;
  reg [63:0] axi_init_0 = 64'h1111111122222222;
  reg [63:0] axi_incr_0 = 64'h3333333344444444;
  reg [31:0] axi_scale_1 = 32'h55556666;
  reg [63:0] axi_init_1 = 64'h7777777788888888;
  reg [63:0] axi_incr_1 = 64'h99999999aaaaaaaa;
  reg [31:0] sched_scale_sm = 32'h0;
  reg [63:0] sched_init = 64'h0123456789abcdef;
  reg [63:0] sched_incr = 64'h13579bdf2468ace0;
  reg [1:0] sched_apply = 2'b00;
  wire [31:0] scale_0;
  wire [63:0] init_0;
  wire [63:0] incr_0;
  wire [31:0] scale_1;
  wire [63:0] init_1;
  wire [63:0] incr_1;
  integer failures = 0;

  ad_ip_jesd204_tpl_dac_sched_mux #(
    .NUM_CHANNELS(2),
    .DDS_PHASE_DW(32)
  ) dut (
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
    .scale_0(scale_0),
    .init_0(init_0),
    .incr_0(incr_0),
    .scale_1(scale_1),
    .init_1(init_1),
    .incr_1(incr_1));

  task fail;
    input [255:0] label;
    begin
      failures = failures + 1;
      $display("FAIL: %0s", label);
    end
  endtask

  task check_scale_ch0;
    input [15:0] sign_magnitude;
    input [15:0] twos_complement;
    begin
      sched_scale_sm[15:0] = sign_magnitude;
      #1;
      if (scale_0[15:0] !== twos_complement) begin
        failures = failures + 1;
        $display("FAIL: scale sm=%04x got=%04x expected=%04x",
                 sign_magnitude, scale_0[15:0], twos_complement);
      end
      if (scale_1[15:0] !== 16'h0000)
        fail("tone 1 was not suppressed during scheduler ownership");
    end
  endtask

  initial begin
    #1;
    if (scale_0 !== axi_scale_0 || init_0 !== axi_init_0 ||
        incr_0 !== axi_incr_0 || scale_1 !== axi_scale_1 ||
        init_1 !== axi_init_1 || incr_1 !== axi_incr_1)
      fail("AXI DDS controls changed without scheduler ownership");

    sched_apply = 2'b01;
    check_scale_ch0(16'h0000, 16'h0000);
    check_scale_ch0(16'h2000, 16'h2000); // +0.5
    check_scale_ch0(16'h2ccc, 16'h2ccc); // +0.7 quantized
    check_scale_ch0(16'h4000, 16'h4000); // +1.0
    check_scale_ch0(16'ha000, 16'he000); // -0.5
    check_scale_ch0(16'hc000, 16'hc000); // -1.0
    check_scale_ch0(16'hffff, 16'h8001); // most-negative v1 magnitude
    check_scale_ch0(16'h8000, 16'h0000); // negative zero canonicalizes

    if (init_0[31:0] !== sched_init[31:0] ||
        incr_0[31:0] !== sched_incr[31:0])
      fail("scheduled phase tuple did not map to tone 0");
    if (init_1[31:0] !== axi_init_1[31:0] ||
        incr_1[31:0] !== axi_incr_1[31:0])
      fail("event-v1 incorrectly overwrote tone 1 phase controls");
    if (scale_0[31:16] !== axi_scale_0[31:16] ||
        scale_1[31:16] !== axi_scale_1[31:16])
      fail("channel 0 ownership affected channel 1");

    // Move persistent ownership to channel 1 and prove the mapping is
    // independent; tone 0 on channel 0 immediately returns to AXI control.
    sched_scale_sm[31:16] = 16'ha000;
    sched_apply = 2'b10;
    #1;
    if (scale_0[15:0] !== axi_scale_0[15:0] ||
        scale_1[15:0] !== axi_scale_1[15:0])
      fail("released channel did not return to AXI controls");
    if (scale_0[31:16] !== 16'he000 || scale_1[31:16] !== 16'h0000)
      fail("channel 1 one-tone negative mapping incorrect");
    if (init_0[63:32] !== sched_init[63:32] ||
        incr_0[63:32] !== sched_incr[63:32])
      fail("channel 1 scheduled phase tuple incorrect");

    // Sequential events on different physical channels leave both channels
    // under persistent scheduler ownership; each retains its own tuple and
    // each independently suppresses tone 1.
    sched_scale_sm[15:0] = 16'h2000;
    sched_apply = 2'b11;
    #1;
    if (scale_0 !== 32'he0002000 || scale_1 !== 32'h00000000)
      fail("persistent two-channel one-tone ownership incorrect");
    if (init_0 !== sched_init || incr_0 !== sched_incr)
      fail("persistent two-channel phase tuples incorrect");

    sched_apply = 2'b00;
    #1;
    if (scale_0 !== axi_scale_0 || scale_1 !== axi_scale_1)
      fail("STOP-style release did not restore AXI scales");

    if (failures == 0) $display("SUCCESS");
    else $display("FAILED: %0d", failures);
    $finish;
  end
endmodule
