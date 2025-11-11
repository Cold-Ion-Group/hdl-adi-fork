// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2025 Cold Ion Group
// CORDIC Sine/Cosine Unit Testbench
// ***************************************************************************
// ***************************************************************************

`timescale 1ns/100ps

module cordic_sine_tb;

  parameter VCD_FILE = "cordic_sine_tb.vcd";
  parameter CORDIC_DW = 16;
  parameter PHASE_DW = 16;
  
  // Clock and reset
  reg clk = 1'b0;
  reg [3:0] reset_shift = 4'b1111;
  wire reset;
  
  // Test inputs
  reg [PHASE_DW-1:0] angle = 0;
  
  // Outputs
  wire [CORDIC_DW-1:0] sine;
  wire [CORDIC_DW-1:0] cosine;
  
  // Test control
  reg failed = 1'b0;
  integer fd_sine, fd_cosine;
  integer test_count = 0;
  
  // Clock generation - 200 MHz
  always #2.5 clk = ~clk;
  
  // Reset generation
  always @(posedge clk) begin
    reset_shift <= {reset_shift[2:0], 1'b0};
  end
  assign reset = reset_shift[3];
  
  // DUT - CORDIC sine/cosine generator
  ad_dds_sine_cordic #(
    .CORDIC_DW(CORDIC_DW),
    .PHASE_DW(PHASE_DW),
    .DELAY_DW(1)
  ) i_cordic (
    .clk(clk),
    .angle(angle),
    .sine(sine),
    .cosine(cosine),
    .ddata_in(1'b0),
    .ddata_out()
  );
  
  // Test stimulus
  initial begin
    $dumpfile(VCD_FILE);
    $dumpvars(0, cordic_sine_tb);
    
    // Open output files
    fd_sine = $fopen("cordic_sine_output.txt", "w");
    fd_cosine = $fopen("cordic_cosine_output.txt", "w");
    
    // Wait for reset to deassert
    wait(reset == 1'b0);
    #100;
    
    $display("===========================================");
    $display("CORDIC Sine/Cosine Testbench");
    $display("===========================================");
    $display("CORDIC_DW = %0d", CORDIC_DW);
    $display("PHASE_DW = %0d", PHASE_DW);
    $display("===========================================");
    
    // Test 1: Sweep through all angles (0 to 2π)
    $display("\nTest 1: Full angle sweep (0 to 2π)");
    for (int i = 0; i < (1 << PHASE_DW); i = i + 16) begin
      angle = i;
      @(posedge clk);
      @(posedge clk); // Pipeline delay
    end
    
    // Test 2: Test specific angles
    $display("Test 2: Specific angles");
    test_angle(16'h0000, "0°");      // 0 degrees
    test_angle(16'h4000, "90°");     // 90 degrees
    test_angle(16'h8000, "180°");    // 180 degrees
    test_angle(16'hC000, "270°");    // 270 degrees
    test_angle(16'h2000, "45°");     // 45 degrees
    test_angle(16'h6000, "135°");    // 135 degrees
    
    // Test 3: Verify Pythagorean identity (sin²+cos²=1)
    $display("\nTest 3: Pythagorean identity verification");
    verify_pythagorean();
    
    $fclose(fd_sine);
    $fclose(fd_cosine);
    
    if (failed == 1'b0) begin
      $display("\n===========================================");
      $display("ALL TESTS PASSED");
      $display("===========================================");
    end else begin
      $display("\n===========================================");
      $display("TESTS FAILED");
      $display("===========================================");
    end
    
    $finish;
  end
  
  // Capture output data
  always @(posedge clk) begin
    if (!reset) begin
      $fwrite(fd_sine, "%0d %d\n", angle, $signed(sine));
      $fwrite(fd_cosine, "%0d %d\n", angle, $signed(cosine));
    end
  end
  
  // Task to test specific angle
  task test_angle(input [PHASE_DW-1:0] test_ang, input string label);
    real expected_sine, expected_cosine;
    real actual_sine, actual_cosine;
    real angle_rad, error_sine, error_cosine;
    begin
      angle = test_ang;
      repeat(PHASE_DW + 5) @(posedge clk); // Wait for full pipeline (CORDIC_DW-1 stages + margin)
      
      // Convert angle to radians
      angle_rad = (test_ang * 2.0 * 3.14159265359) / (1 << PHASE_DW);
      
      // Expected values
      expected_sine = $sin(angle_rad);
      expected_cosine = $cos(angle_rad);
      
      // Actual values (normalized)
      actual_sine = $signed(sine) / ((1 << (CORDIC_DW-1)) - 1.0);
      actual_cosine = $signed(cosine) / ((1 << (CORDIC_DW-1)) - 1.0);
      
      // Calculate errors
      error_sine = $abs(actual_sine - expected_sine);
      error_cosine = $abs(actual_cosine - expected_cosine);
      
      $display("  %s (0x%04h):", label, test_ang);
      $display("    Sin: Expected=%f, Actual=%f, Error=%f", 
               expected_sine, actual_sine, error_sine);
      $display("    Cos: Expected=%f, Actual=%f, Error=%f", 
               expected_cosine, actual_cosine, error_cosine);
      
      // Check if error is acceptable (< 0.01 for 16-bit CORDIC)
      if (error_sine > 0.01 || error_cosine > 0.01) begin
        $display("    ERROR: Accuracy outside acceptable range!");
        failed = 1'b1;
      end
      
      test_count = test_count + 1;
    end
  endtask
  
  // Verify sin²+cos²=1
  task verify_pythagorean();
    real sine_norm, cosine_norm, sum_squares, error;
    integer errors = 0;
    begin
      for (int i = 0; i < 64; i++) begin
        angle = $random;
        repeat(PHASE_DW) @(posedge clk);
        
        sine_norm = $signed(sine) / ((1 << (CORDIC_DW-1)) - 1.0);
        cosine_norm = $signed(cosine) / ((1 << (CORDIC_DW-1)) - 1.0);
        sum_squares = sine_norm*sine_norm + cosine_norm*cosine_norm;
        error = $abs(sum_squares - 1.0);
        
        if (error > 0.02) begin // Allow 2% error
          errors = errors + 1;
          $display("  Angle 0x%04h: sin²+cos²=%f (error=%f)", 
                   angle, sum_squares, error);
        end
      end
      
      if (errors == 0) begin
        $display("  ✓ Pythagorean identity verified for 64 random angles");
      end else begin
        $display("  ERROR: %0d angles failed Pythagorean identity", errors);
        failed = 1'b1;
      end
    end
  endtask

endmodule
