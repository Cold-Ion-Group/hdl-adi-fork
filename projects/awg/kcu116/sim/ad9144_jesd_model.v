// AD9144 JESD204B Receiver Model
//
// This module provides a simplified behavioral model of the AD9144 DAC
// for testbench purposes. It focuses on JESD204B link behavior.
//
// Features:
// - JESD204B receiver (link layer behavioral model)
// - SYNC signal generation
// - Link state monitoring
// - Data capture and verification
//
// Limitations:
// - Does not model actual DAC analog output
// - Simplified JESD204B protocol (focuses on sync behavior)
// - Does not decode full ILAS configuration
//
// Author: System Testbench Implementation
// Date: November 2025

`timescale 1ns/1ps

module ad9144_jesd_model #(
  parameter NUM_LANES = 4,
  parameter DATA_PATH_WIDTH = 4  // Parallel data width per lane (4 or 8)
)(
  // Reference clock
  input                                    ref_clk,
  input                                    sysref,
  
  // JESD204B differential inputs (parallel data - not actual SERDES)
  input  [(NUM_LANES*DATA_PATH_WIDTH*8)-1:0] tx_data,  // Parallel data from PHY
  input                                    tx_data_valid,
  
  // SYNC outputs (to FPGA)
  output reg [1:0]                         tx_sync,
  
  // Status
  output reg                               link_ready,
  output reg [2:0]                         link_state
);

  //===========================================================================
  // JESD204B Link States
  //===========================================================================
  
  localparam ST_WAIT = 3'h0;
  localparam ST_CGS  = 3'h1;  // Code Group Sync
  localparam ST_ILAS = 3'h2;  // Initial Lane Alignment Sequence
  localparam ST_DATA = 3'h3;  // User Data
  
  //===========================================================================
  // Internal signals
  //===========================================================================
  
  reg [7:0] cgs_counter;
  reg [7:0] ilas_counter;
  reg       sysref_detected;
  reg       sysref_d1, sysref_d2;
  
  // Data capture
  reg [(NUM_LANES*DATA_PATH_WIDTH*8)-1:0] captured_data;
  integer data_sample_count;
  integer data_file;
  
  //===========================================================================
  // Initialize
  //===========================================================================
  
  initial begin
    link_state = ST_WAIT;
    link_ready = 0;
    tx_sync = 2'b00;  // SYNC low means link not ready
    cgs_counter = 0;
    ilas_counter = 0;
    sysref_detected = 0;
    sysref_d1 = 0;
    sysref_d2 = 0;
    data_sample_count = 0;
    
    $display("[AD9144] JESD204B Model initialized with %0d lanes", NUM_LANES);
  end
  
  //===========================================================================
  // SYSREF edge detection
  //===========================================================================
  
  always @(posedge ref_clk) begin
    sysref_d1 <= sysref;
    sysref_d2 <= sysref_d1;
    
    // Rising edge detection
    if (sysref_d1 && !sysref_d2) begin
      sysref_detected <= 1;
      $display("[AD9144] %t: SYSREF rising edge detected", $time);
    end
  end
  
  //===========================================================================
  // JESD204B Link State Machine
  //===========================================================================
  
  always @(posedge ref_clk) begin
    case (link_state)
      
      ST_WAIT: begin
        tx_sync <= 2'b00;  // SYNC deasserted
        link_ready <= 0;
        
        // Wait for SYSREF before starting link
        if (sysref_detected) begin
          $display("[AD9144] %t: Entering CGS state", $time);
          link_state <= ST_CGS;
          cgs_counter <= 0;
        end
      end
      
      ST_CGS: begin
        // Code Group Synchronization
        // In real JESD204B, we'd look for /K28.5/ characters
        // For this model, we'll just wait for a number of valid data cycles
        
        if (tx_data_valid) begin
          cgs_counter <= cgs_counter + 1;
          
          // After receiving enough CGS characters, move to ILAS
          if (cgs_counter >= 16) begin
            $display("[AD9144] %t: CGS complete, entering ILAS state", $time);
            link_state <= ST_ILAS;
            ilas_counter <= 0;
          end
        end
      end
      
      ST_ILAS: begin
        // Initial Lane Alignment Sequence
        // Real JESD would decode configuration here
        // We'll just count ILAS multiframes
        
        if (tx_data_valid) begin
          ilas_counter <= ilas_counter + 1;
          
          // ILAS typically lasts 4 multiframes
          if (ilas_counter >= 32) begin
            $display("[AD9144] %t: ILAS complete, entering DATA state", $time);
            link_state <= ST_DATA;
            tx_sync <= 2'b11;  // Assert SYNC to indicate link ready
            link_ready <= 1;
          end
        end
      end
      
      ST_DATA: begin
        // User Data state - link is active
        // Capture data for verification
        
        if (tx_data_valid) begin
          captured_data <= tx_data;
          data_sample_count <= data_sample_count + 1;
          
          // Periodically display data
          if (data_sample_count % 1000 == 0) begin
            $display("[AD9144] %t: Data samples received: %0d", $time, data_sample_count);
          end
        end
      end
      
      default: begin
        link_state <= ST_WAIT;
      end
      
    endcase
  end
  
  //===========================================================================
  // Data capture for verification (optional)
  //===========================================================================
  
  task start_capture;
    input [256*8-1:0] filename;
    begin
      data_file = $fopen(filename, "w");
      if (data_file == 0) begin
        $display("[AD9144] ERROR: Could not open file for data capture");
      end else begin
        $display("[AD9144] Started data capture to file: %s", filename);
      end
    end
  endtask
  
  task stop_capture;
    begin
      if (data_file != 0) begin
        $fclose(data_file);
        $display("[AD9144] Stopped data capture. Total samples: %0d", data_sample_count);
      end
    end
  endtask
  
  // Write data to file when in DATA state
  always @(posedge ref_clk) begin
    if (link_state == ST_DATA && tx_data_valid && data_file != 0) begin
      $fwrite(data_file, "%h\n", captured_data);
    end
  end
  
  //===========================================================================
  // Simulation helpers
  //===========================================================================
  
  // Task to reset the link
  task reset_link;
    begin
      link_state <= ST_WAIT;
      link_ready <= 0;
      tx_sync <= 2'b00;
      cgs_counter <= 0;
      ilas_counter <= 0;
      sysref_detected <= 0;
      data_sample_count <= 0;
      $display("[AD9144] Link reset");
    end
  endtask
  
  // Task to force link to DATA state (for quick testing)
  task force_link_ready;
    begin
      link_state <= ST_DATA;
      link_ready <= 1;
      tx_sync <= 2'b11;
      $display("[AD9144] Link forced to ready state");
    end
  endtask

endmodule
