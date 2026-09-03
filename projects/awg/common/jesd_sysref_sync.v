// JESD SYSREF and SYNC~ synchronizer for Subclass-1 bring-up.
`timescale 1ns/1ps

module jesd_sysref_sync #(
  parameter integer SYNC_WIDTH = 1,
  parameter integer ARM_DELAY_CYCLES = 0
) (
  input                         device_clk,
  input                         reset,
  input                         sysref_in,
  input      [SYNC_WIDTH-1:0]   sync_in,
  output                        sysref_pulse,
  output     [SYNC_WIDTH-1:0]   sync_out
);

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [2:0] sysref_ff = 3'b000;
  reg [2:0] sysref_sample_valid = 3'b000;
  reg [SYNC_WIDTH-1:0] sync_ff1 = {SYNC_WIDTH{1'b1}};
  reg [SYNC_WIDTH-1:0] sync_ff2 = {SYNC_WIDTH{1'b1}};
  reg [31:0] arm_cnt = 32'd0;
  reg arm = 1'b0;

  always @(posedge device_clk) begin
    if (reset) begin
      sysref_ff <= 3'b000;
      sysref_sample_valid <= 3'b000;
      sync_ff1 <= {SYNC_WIDTH{1'b1}};
      sync_ff2 <= {SYNC_WIDTH{1'b1}};
      arm_cnt <= 32'd0;
      arm <= 1'b0;
    end else begin
      sysref_ff <= {sysref_ff[1:0], sysref_in};
      sysref_sample_valid <= {sysref_sample_valid[1:0], 1'b1};
      sync_ff1 <= sync_in;
      sync_ff2 <= sync_ff1;

      // Fill the complete synchronizer before arming edge detection.  In
      // particular, a SYSREF pin which is already high when reset is released
      // establishes a high baseline; it must not be misreported as a physical
      // rising edge merely because the reset value of sysref_ff was low.
      if (!arm && (&sysref_sample_valid)) begin
        if (ARM_DELAY_CYCLES == 0) begin
          arm <= 1'b1;
        end else if (arm_cnt >= (ARM_DELAY_CYCLES - 1)) begin
          arm <= 1'b1;
        end else begin
          arm_cnt <= arm_cnt + 1'b1;
        end
      end
    end
  end

  assign sync_out = sync_ff2;
  // sysref_ff shifts toward the MSB, so ff[1]=1 while the older ff[2]=0
  // denotes a physical rising edge.  The opposite expression detects a fall.
  assign sysref_pulse = arm ? (sysref_ff[1] & ~sysref_ff[2]) : 1'b0;

endmodule
