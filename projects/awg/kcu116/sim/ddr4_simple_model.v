// Simple DDR4 Memory Model for Testbench
//
// This module provides a simplified behavioral model of DDR4 memory
// for simulation purposes. It implements an AXI4 slave interface.
//
// Features:
// - Configurable memory size
// - AXI4 full interface (for DMA transfers)
// - Simplified timing (no DDR4 protocol details)
// - Memory initialization support
// - Read/write access monitoring
//
// Limitations:
// - Does not model DDR4 timing accurately
// - Does not implement refresh, ZQ calibration, etc.
// - Fixed latency model
//
// Author: System Testbench Implementation
// Date: November 2025

`timescale 1ns/1ps

module ddr4_simple_model #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH = 4,
  parameter MEM_SIZE_KB = 1024,  // Memory size in KB
  parameter READ_LATENCY = 10,   // Cycles of read latency
  parameter WRITE_LATENCY = 5    // Cycles of write latency
)(
  // Clock and Reset
  input                       axi_aclk,
  input                       axi_aresetn,
  
  // Write Address Channel
  input [ID_WIDTH-1:0]        s_axi_awid,
  input [ADDR_WIDTH-1:0]      s_axi_awaddr,
  input [7:0]                 s_axi_awlen,    // Burst length - 1
  input [2:0]                 s_axi_awsize,   // Bytes per beat
  input [1:0]                 s_axi_awburst,  // Burst type
  input                       s_axi_awlock,
  input [3:0]                 s_axi_awcache,
  input [2:0]                 s_axi_awprot,
  input [3:0]                 s_axi_awqos,
  input                       s_axi_awvalid,
  output reg                  s_axi_awready,
  
  // Write Data Channel
  input [DATA_WIDTH-1:0]      s_axi_wdata,
  input [DATA_WIDTH/8-1:0]    s_axi_wstrb,
  input                       s_axi_wlast,
  input                       s_axi_wvalid,
  output reg                  s_axi_wready,
  
  // Write Response Channel
  output reg [ID_WIDTH-1:0]   s_axi_bid,
  output reg [1:0]            s_axi_bresp,
  output reg                  s_axi_bvalid,
  input                       s_axi_bready,
  
  // Read Address Channel
  input [ID_WIDTH-1:0]        s_axi_arid,
  input [ADDR_WIDTH-1:0]      s_axi_araddr,
  input [7:0]                 s_axi_arlen,
  input [2:0]                 s_axi_arsize,
  input [1:0]                 s_axi_arburst,
  input                       s_axi_arlock,
  input [3:0]                 s_axi_arcache,
  input [2:0]                 s_axi_arprot,
  input [3:0]                 s_axi_arqos,
  input                       s_axi_arvalid,
  output reg                  s_axi_arready,
  
  // Read Data Channel
  output reg [ID_WIDTH-1:0]   s_axi_rid,
  output reg [DATA_WIDTH-1:0] s_axi_rdata,
  output reg [1:0]            s_axi_rresp,
  output reg                  s_axi_rlast,
  output reg                  s_axi_rvalid,
  input                       s_axi_rready
);

  //===========================================================================
  // Memory array
  //===========================================================================
  
  localparam MEM_SIZE = MEM_SIZE_KB * 1024 / (DATA_WIDTH/8);  // Number of DATA_WIDTH words
  reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];
  
  //===========================================================================
  // Internal state
  //===========================================================================
  
  // Write channel state
  reg [ID_WIDTH-1:0]   wr_id;
  reg [ADDR_WIDTH-1:0] wr_addr;
  reg [7:0]            wr_len;
  reg [2:0]            wr_size;
  reg [1:0]            wr_burst;
  reg [7:0]            wr_beat_cnt;
  integer              wr_latency_cnt;
  
  // Read channel state
  reg [ID_WIDTH-1:0]   rd_id;
  reg [ADDR_WIDTH-1:0] rd_addr;
  reg [7:0]            rd_len;
  reg [2:0]            rd_size;
  reg [1:0]            rd_burst;
  reg [7:0]            rd_beat_cnt;
  integer              rd_latency_cnt;
  
  // State machines
  typedef enum {WR_IDLE, WR_ADDR, WR_DATA, WR_RESP} wr_state_t;
  typedef enum {RD_IDLE, RD_ADDR, RD_DATA} rd_state_t;
  
  wr_state_t wr_state;
  rd_state_t rd_state;
  
  //===========================================================================
  // Initialize memory
  //===========================================================================
  
  integer i;
  initial begin
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
      memory[i] = {DATA_WIDTH{1'b0}};
    end
    
    wr_state = WR_IDLE;
    rd_state = RD_IDLE;
    
    s_axi_awready = 0;
    s_axi_wready  = 0;
    s_axi_bid     = 0;
    s_axi_bresp   = 0;
    s_axi_bvalid  = 0;
    
    s_axi_arready = 0;
    s_axi_rid     = 0;
    s_axi_rdata   = 0;
    s_axi_rresp   = 0;
    s_axi_rlast   = 0;
    s_axi_rvalid  = 0;
  end
  
  //===========================================================================
  // Task: Write to memory
  //===========================================================================
  
  task mem_write;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    input [DATA_WIDTH/8-1:0] strb;
    integer byte_idx;
    integer word_idx;
    reg [DATA_WIDTH-1:0] old_data;
    reg [DATA_WIDTH-1:0] new_data;
    begin
      word_idx = (addr >> $clog2(DATA_WIDTH/8)) & (MEM_SIZE - 1);
      old_data = memory[word_idx];
      new_data = old_data;
      
      for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1) begin
        if (strb[byte_idx]) begin
          new_data[byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
        end
      end
      
      memory[word_idx] = new_data;
      //$display("[DDR4] Write: addr=0x%08h data=0x%016h strb=0x%02h", addr, new_data, strb);
    end
  endtask
  
  //===========================================================================
  // Task: Read from memory
  //===========================================================================
  
  task mem_read;
    input [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    integer word_idx;
    begin
      word_idx = (addr >> $clog2(DATA_WIDTH/8)) & (MEM_SIZE - 1);
      data = memory[word_idx];
      //$display("[DDR4] Read: addr=0x%08h data=0x%016h", addr, data);
    end
  endtask
  
  //===========================================================================
  // Write Channel State Machine
  //===========================================================================
  
  always @(posedge axi_aclk) begin
    if (!axi_aresetn) begin
      wr_state <= WR_IDLE;
      s_axi_awready <= 0;
      s_axi_wready <= 0;
      s_axi_bvalid <= 0;
      wr_beat_cnt <= 0;
    end else begin
      case (wr_state)
        WR_IDLE: begin
          s_axi_awready <= 1;  // Ready to accept address
          s_axi_wready <= 0;
          s_axi_bvalid <= 0;
          
          if (s_axi_awvalid && s_axi_awready) begin
            wr_id <= s_axi_awid;
            wr_addr <= s_axi_awaddr;
            wr_len <= s_axi_awlen;
            wr_size <= s_axi_awsize;
            wr_burst <= s_axi_awburst;
            wr_beat_cnt <= 0;
            s_axi_awready <= 0;
            wr_state <= WR_DATA;
          end
        end
        
        WR_DATA: begin
          s_axi_wready <= 1;  // Ready to accept data
          
          if (s_axi_wvalid && s_axi_wready) begin
            // Write to memory
            mem_write(wr_addr, s_axi_wdata, s_axi_wstrb);
            
            // Calculate next address (INCR burst)
            if (wr_burst == 2'b01) begin  // INCR
              wr_addr <= wr_addr + (1 << wr_size);
            end
            
            // Check if last beat
            if (s_axi_wlast || (wr_beat_cnt >= wr_len)) begin
              s_axi_wready <= 0;
              wr_latency_cnt <= 0;
              wr_state <= WR_RESP;
            end else begin
              wr_beat_cnt <= wr_beat_cnt + 1;
            end
          end
        end
        
        WR_RESP: begin
          // Add write latency
          if (wr_latency_cnt < WRITE_LATENCY) begin
            wr_latency_cnt <= wr_latency_cnt + 1;
          end else begin
            s_axi_bid <= wr_id;
            s_axi_bresp <= 2'b00;  // OKAY
            s_axi_bvalid <= 1;
            
            if (s_axi_bready) begin
              s_axi_bvalid <= 0;
              wr_state <= WR_IDLE;
            end
          end
        end
        
        default: wr_state <= WR_IDLE;
      endcase
    end
  end
  
  //===========================================================================
  // Read Channel State Machine
  //===========================================================================
  
  always @(posedge axi_aclk) begin
    if (!axi_aresetn) begin
      rd_state <= RD_IDLE;
      s_axi_arready <= 0;
      s_axi_rvalid <= 0;
      s_axi_rlast <= 0;
      rd_beat_cnt <= 0;
    end else begin
      case (rd_state)
        RD_IDLE: begin
          s_axi_arready <= 1;  // Ready to accept address
          s_axi_rvalid <= 0;
          s_axi_rlast <= 0;
          
          if (s_axi_arvalid && s_axi_arready) begin
            rd_id <= s_axi_arid;
            rd_addr <= s_axi_araddr;
            rd_len <= s_axi_arlen;
            rd_size <= s_axi_arsize;
            rd_burst <= s_axi_arburst;
            rd_beat_cnt <= 0;
            rd_latency_cnt <= 0;
            s_axi_arready <= 0;
            rd_state <= RD_DATA;
          end
        end
        
        RD_DATA: begin
          // Add read latency for first beat
          if (rd_latency_cnt < READ_LATENCY) begin
            rd_latency_cnt <= rd_latency_cnt + 1;
          end else begin
            // Read from memory
            mem_read(rd_addr, s_axi_rdata);
            
            s_axi_rid <= rd_id;
            s_axi_rresp <= 2'b00;  // OKAY
            s_axi_rlast <= (rd_beat_cnt >= rd_len);
            s_axi_rvalid <= 1;
            
            if (s_axi_rready) begin
              // Calculate next address (INCR burst)
              if (rd_burst == 2'b01) begin  // INCR
                rd_addr <= rd_addr + (1 << rd_size);
              end
              
              if (s_axi_rlast) begin
                s_axi_rvalid <= 0;
                s_axi_rlast <= 0;
                rd_state <= RD_IDLE;
              end else begin
                rd_beat_cnt <= rd_beat_cnt + 1;
                rd_latency_cnt <= READ_LATENCY - 1;  // Reduce latency for subsequent beats
              end
            end
          end
        end
        
        default: rd_state <= RD_IDLE;
      endcase
    end
  end
  
  //===========================================================================
  // Memory initialization task (for testbench use)
  //===========================================================================
  
  task load_mem;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    integer word_idx;
    begin
      word_idx = (addr >> $clog2(DATA_WIDTH/8)) & (MEM_SIZE - 1);
      memory[word_idx] = data;
      $display("[DDR4] Load: addr=0x%08h data=0x%016h", addr, data);
    end
  endtask

endmodule
