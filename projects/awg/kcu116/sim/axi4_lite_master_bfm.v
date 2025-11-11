// AXI4-Lite Master Bus Functional Model (BFM)
//
// This module implements a simplified AXI4-Lite master for testbench use.
// It provides tasks to perform write and read transactions on the AXI4-Lite bus.
//
// Features:
// - Task-based interface for simple write/read operations
// - Protocol-compliant AXI4-Lite handshaking
// - Timeout detection
// - Response checking (OKAY, SLVERR, etc.)
//
// Usage:
//   axi4_lite_master_bfm bfm (
//     .axi_aclk(clk),
//     .axi_aresetn(resetn),
//     ... connect AXI signals ...
//   );
//
//   initial begin
//     bfm.axi_write(32'h44A00000, 32'h12345678);
//     bfm.axi_read(32'h44A00000, read_data);
//   end
//
// Author: System Testbench Implementation
// Date: November 2025

`timescale 1ns/1ps

module axi4_lite_master_bfm #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter TIMEOUT = 1000
)(
  // Clock and Reset
  input                       axi_aclk,
  input                       axi_aresetn,
  
  // Write Address Channel
  output reg [ADDR_WIDTH-1:0] m_axi_awaddr,
  output reg [2:0]            m_axi_awprot,
  output reg                  m_axi_awvalid,
  input                       m_axi_awready,
  
  // Write Data Channel
  output reg [DATA_WIDTH-1:0] m_axi_wdata,
  output reg [3:0]            m_axi_wstrb,
  output reg                  m_axi_wvalid,
  input                       m_axi_wready,
  
  // Write Response Channel
  input [1:0]                 m_axi_bresp,
  input                       m_axi_bvalid,
  output reg                  m_axi_bready,
  
  // Read Address Channel
  output reg [ADDR_WIDTH-1:0] m_axi_araddr,
  output reg [2:0]            m_axi_arprot,
  output reg                  m_axi_arvalid,
  input                       m_axi_arready,
  
  // Read Data Channel
  input [DATA_WIDTH-1:0]      m_axi_rdata,
  input [1:0]                 m_axi_rresp,
  input                       m_axi_rvalid,
  output reg                  m_axi_rready
);

  //===========================================================================
  // Internal signals
  //===========================================================================
  
  integer timeout_count;
  reg [1:0] last_bresp;
  reg [1:0] last_rresp;
  
  //===========================================================================
  // Initialize outputs
  //===========================================================================
  
  initial begin
    m_axi_awaddr  = 0;
    m_axi_awprot  = 3'b000;
    m_axi_awvalid = 0;
    m_axi_wdata   = 0;
    m_axi_wstrb   = 4'b1111;
    m_axi_wvalid  = 0;
    m_axi_bready  = 1;  // Always ready to accept write response
    m_axi_araddr  = 0;
    m_axi_arprot  = 3'b000;
    m_axi_arvalid = 0;
    m_axi_rready  = 1;  // Always ready to accept read data
    last_bresp    = 2'b00;
    last_rresp    = 2'b00;
  end
  
  //===========================================================================
  // Task: AXI Write
  //===========================================================================
  
  task axi_write;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    input [3:0] strb;  // Byte strobes (optional)
    begin
      timeout_count = 0;
      
      // Drive write address and data simultaneously
      @(posedge axi_aclk);
      #1;  // Delta delay for signal assignment
      m_axi_awaddr  = addr;
      m_axi_awvalid = 1;
      m_axi_wdata   = data;
      m_axi_wstrb   = strb;
      m_axi_wvalid  = 1;
      
      // Wait for address accepted
      while (!m_axi_awready && timeout_count < TIMEOUT) begin
        @(posedge axi_aclk);
        timeout_count = timeout_count + 1;
      end
      
      if (timeout_count >= TIMEOUT) begin
        $display("[ERROR] %t: AXI Write timeout on address channel (addr=0x%h)", $time, addr);
        $finish;
      end
      
      @(posedge axi_aclk);
      #1;
      m_axi_awvalid = 0;
      
      // Wait for data accepted
      timeout_count = 0;
      while (!m_axi_wready && timeout_count < TIMEOUT) begin
        @(posedge axi_aclk);
        timeout_count = timeout_count + 1;
      end
      
      if (timeout_count >= TIMEOUT) begin
        $display("[ERROR] %t: AXI Write timeout on data channel (addr=0x%h)", $time, addr);
        $finish;
      end
      
      @(posedge axi_aclk);
      #1;
      m_axi_wvalid = 0;
      
      // Wait for write response
      timeout_count = 0;
      while (!m_axi_bvalid && timeout_count < TIMEOUT) begin
        @(posedge axi_aclk);
        timeout_count = timeout_count + 1;
      end
      
      if (timeout_count >= TIMEOUT) begin
        $display("[ERROR] %t: AXI Write timeout on response channel (addr=0x%h)", $time, addr);
        $finish;
      end
      
      // Capture response
      last_bresp = m_axi_bresp;
      @(posedge axi_aclk);
      
      // Check response
      if (last_bresp != 2'b00) begin
        $display("[WARNING] %t: AXI Write response error: BRESP=%b (addr=0x%h, data=0x%h)", 
                 $time, last_bresp, addr, data);
      end else begin
        $display("[INFO] %t: AXI Write: addr=0x%08h data=0x%08h", $time, addr, data);
      end
    end
  endtask
  
  //===========================================================================
  // Task: AXI Write (with default full byte strobe)
  //===========================================================================
  
  task axi_write_simple;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    begin
      axi_write(addr, data, 4'b1111);
    end
  endtask
  
  //===========================================================================
  // Task: AXI Read
  //===========================================================================
  
  task axi_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    begin
      timeout_count = 0;
      
      // Drive read address
      @(posedge axi_aclk);
      #1;
      m_axi_araddr  = addr;
      m_axi_arvalid = 1;
      
      // Wait for address accepted
      while (!m_axi_arready && timeout_count < TIMEOUT) begin
        @(posedge axi_aclk);
        timeout_count = timeout_count + 1;
      end
      
      if (timeout_count >= TIMEOUT) begin
        $display("[ERROR] %t: AXI Read timeout on address channel (addr=0x%h)", $time, addr);
        $finish;
      end
      
      @(posedge axi_aclk);
      #1;
      m_axi_arvalid = 0;
      
      // Wait for read data
      timeout_count = 0;
      while (!m_axi_rvalid && timeout_count < TIMEOUT) begin
        @(posedge axi_aclk);
        timeout_count = timeout_count + 1;
      end
      
      if (timeout_count >= TIMEOUT) begin
        $display("[ERROR] %t: AXI Read timeout on data channel (addr=0x%h)", $time, addr);
        $finish;
      end
      
      // Capture data and response
      data = m_axi_rdata;
      last_rresp = m_axi_rresp;
      @(posedge axi_aclk);
      
      // Check response
      if (last_rresp != 2'b00) begin
        $display("[WARNING] %t: AXI Read response error: RRESP=%b (addr=0x%h)", 
                 $time, last_rresp, addr);
      end else begin
        $display("[INFO] %t: AXI Read: addr=0x%08h data=0x%08h", $time, addr, data);
      end
    end
  endtask
  
  //===========================================================================
  // Task: Register Read-Modify-Write
  //===========================================================================
  
  task axi_rmw;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] mask;      // Bits to modify
    input [DATA_WIDTH-1:0] value;     // New values for masked bits
    reg [DATA_WIDTH-1:0] read_data;
    reg [DATA_WIDTH-1:0] new_data;
    begin
      // Read current value
      axi_read(addr, read_data);
      
      // Modify
      new_data = (read_data & ~mask) | (value & mask);
      
      // Write back
      axi_write_simple(addr, new_data);
    end
  endtask
  
  //===========================================================================
  // Task: Verify Register Value
  //===========================================================================
  
  task axi_verify;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] expected;
    input [DATA_WIDTH-1:0] mask;      // Bits to check (1=check, 0=ignore)
    reg [DATA_WIDTH-1:0] read_data;
    begin
      axi_read(addr, read_data);
      
      if ((read_data & mask) !== (expected & mask)) begin
        $display("[ERROR] %t: Register verification failed!", $time);
        $display("        Address  : 0x%08h", addr);
        $display("        Expected : 0x%08h (mask: 0x%08h)", expected, mask);
        $display("        Got      : 0x%08h", read_data);
        $display("        Mismatch : 0x%08h", (read_data ^ expected) & mask);
      end else begin
        $display("[INFO] %t: Register verification passed: addr=0x%08h value=0x%08h", 
                 $time, addr, read_data);
      end
    end
  endtask
  
  //===========================================================================
  // Task: Poll register until condition met
  //===========================================================================
  
  task axi_poll;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] mask;
    input [DATA_WIDTH-1:0] expected;
    input integer max_polls;
    reg [DATA_WIDTH-1:0] read_data;
    integer poll_count;
    begin
      poll_count = 0;
      read_data = 0;
      
      while (((read_data & mask) !== (expected & mask)) && (poll_count < max_polls)) begin
        axi_read(addr, read_data);
        poll_count = poll_count + 1;
        if (poll_count < max_polls && (read_data & mask) !== (expected & mask)) begin
          repeat(10) @(posedge axi_aclk);  // Wait between polls
        end
      end
      
      if (poll_count >= max_polls) begin
        $display("[ERROR] %t: Poll timeout on addr=0x%08h", $time, addr);
        $display("        Expected (masked): 0x%08h", expected & mask);
        $display("        Got (masked)     : 0x%08h", read_data & mask);
      end else begin
        $display("[INFO] %t: Poll succeeded after %0d attempts: addr=0x%08h value=0x%08h", 
                 $time, poll_count, addr, read_data);
      end
    end
  endtask

endmodule
