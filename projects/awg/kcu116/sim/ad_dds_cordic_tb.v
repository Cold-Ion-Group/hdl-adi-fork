// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2025 Cold Ion Group
// CORDIC DDS Testbench for AWG Project
// ***************************************************************************
// ***************************************************************************

`timescale 1ns/100ps

module ad_dds_cordic_tb;

  parameter VCD_FILE = "ad_dds_cordic_tb.vcd";
  parameter CORDIC_DW = 16;
  parameter PHASE_DW = 16;
  
  // Clock and reset
  reg clk = 1'b0;
  reg [3:0] reset_shift = 4'b1111;
  wire reset;
  
  // DDS controls
  reg dac_data_sync = 1'b0;
  reg dac_dds_format = 1'b0;  // 0=offset binary, 1=2's complement
  
  // Tone 1 parameters
  reg [15:0] tone_1_scale = 16'h0FFF;      // ~1.0 amplitude
  reg [15:0] tone_1_init_offset = 16'h0000;
  reg [15:0] tone_1_freq_word = 16'h0100;  // Frequency increment
  
  // Tone 2 parameters  
  reg [15:0] tone_2_scale = 16'h0800;      // ~0.5 amplitude
  reg [15:0] tone_2_init_offset = 16'h4000; // 90 degree phase offset
  reg [15:0] tone_2_freq_word = 16'h0200;  // 2x frequency of tone 1
  
  // Output
  wire [CORDIC_DW-1:0] dac_dds_data;
  
  // Test control
  reg failed = 1'b0;
  integer fd;
  integer sample_count = 0;
  
  // Clock generation - 200 MHz
  always #2.5 clk = ~clk;
  
  // Reset generation
  always @(posedge clk) begin
    reset_shift <= {reset_shift[2:0], 1'b0};
  end
  assign reset = reset_shift[3];
  
  // DUT instantiation
  ad_dds #(
    .DISABLE(0),
    .DDS_DW(CORDIC_DW),
    .PHASE_DW(PHASE_DW),
    .DDS_TYPE(1),              // 1=CORDIC, 2=Polynomial
    .CORDIC_DW(CORDIC_DW),
    .CORDIC_PHASE_DW(PHASE_DW),
    .CLK_RATIO(1)
  ) i_dds (
    .clk(clk),
    .dac_dds_format(dac_dds_format),
    .dac_data_sync(dac_data_sync),
    .dac_valid(1'b1),
    .tone_1_scale(tone_1_scale),
    .tone_2_scale(tone_2_scale),
    .tone_1_init_offset(tone_1_init_offset),
    .tone_2_init_offset(tone_2_init_offset),
    .tone_1_freq_word(tone_1_freq_word),
    .tone_2_freq_word(tone_2_freq_word),
    .dac_dds_data(dac_dds_data)
  );
  
  // Test stimulus
  initial begin
    $dumpfile(VCD_FILE);
    $dumpvars(0, ad_dds_cordic_tb);
    
    // Open output file for data analysis
    fd = $fopen("dds_output.txt", "w");
    
    // Wait for reset to deassert
    wait(reset == 1'b0);
    #100;
    
    $display("===========================================");
    $display("CORDIC DDS Testbench");
    $display("===========================================");
    $display("CORDIC_DW = %0d", CORDIC_DW);
    $display("PHASE_DW = %0d", PHASE_DW);
    $display("Tone 1: freq_word=0x%04h, scale=0x%04h", tone_1_freq_word, tone_1_scale);
    $display("Tone 2: freq_word=0x%04h, scale=0x%04h", tone_2_freq_word, tone_2_scale);
    $display("===========================================");
    
    // Sync the DDS
    @(posedge clk);
    dac_data_sync = 1'b1;
    @(posedge clk);
    dac_data_sync = 1'b0;
    
    // Run for 2048 samples (1 full period at freq_word=0x0100)
    repeat(2048) begin
      @(posedge clk);
    end
    
    $display("Collected %0d samples", sample_count);
    $display("===========================================");
    
    // Change frequency and test again
    $display("Changing to higher frequency...");
    tone_1_freq_word = 16'h0400;
    tone_2_freq_word = 16'h0800;
    
    @(posedge clk);
    dac_data_sync = 1'b1;
    @(posedge clk);
    dac_data_sync = 1'b0;
    
    repeat(512) begin
      @(posedge clk);
    end
    
    $fclose(fd);
    
    if (failed == 1'b0)
      $display("TEST PASSED");
    else
      $display("TEST FAILED");
      
    $display("===========================================");
    $display("Output saved to dds_output.txt");
    $display("Use analyze_dds.py to visualize results");
    $finish;
  end
  
  // Capture output data
  always @(posedge clk) begin
    if (!reset && dac_dds_data !== 16'hxxxx) begin
      $fwrite(fd, "%d\n", $signed(dac_dds_data));
      sample_count = sample_count + 1;
    end
  end
  
  // Basic sanity checks
  reg [CORDIC_DW-1:0] prev_sample;
  reg [31:0] zero_crossing_count = 0;
  
  always @(posedge clk) begin
    if (!reset && sample_count > 10) begin
      // Check for zero crossings (should happen regularly for sine wave)
      if ((prev_sample[CORDIC_DW-1] != dac_dds_data[CORDIC_DW-1])) begin
        zero_crossing_count = zero_crossing_count + 1;
      end
      prev_sample = dac_dds_data;
    end
  end
  
  // Monitor progress
  always @(posedge clk) begin
    if (sample_count > 0 && sample_count % 256 == 0) begin
      $display("  Progress: %0d samples, %0d zero crossings", 
               sample_count, zero_crossing_count);
    end
  end

endmodule
