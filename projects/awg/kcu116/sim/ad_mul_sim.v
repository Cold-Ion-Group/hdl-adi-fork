// ***************************************************************************
// ***************************************************************************
// Generic Multiplier for Simulation
// Replaces Xilinx-specific ad_mul for use with Icarus Verilog
// 
// Functionally equivalent to Xilinx ad_mul with MULT_MACRO LATENCY=3
// - 3 pipeline stages for multiplication
// - 3 pipeline stages for delay data path (ddata_in -> ddata_out)
// ***************************************************************************
// ***************************************************************************

`timescale 1ns/100ps

module ad_mul #(
  parameter A_DATA_WIDTH = 16,
  parameter B_DATA_WIDTH = 18,
  parameter A_ADDRESS_WIDTH = 0,
  parameter B_ADDRESS_WIDTH = 0,
  parameter DELAY_DATA_WIDTH = 16,
  parameter DW = A_DATA_WIDTH + B_DATA_WIDTH
) (
  input                               clk,
  
  input       [A_DATA_WIDTH-1:0]      data_a,
  input       [B_DATA_WIDTH-1:0]      data_b,
  output reg  [DW-1:0]                data_p,
  
  // Optional address ports (unused in simulation)
  input       [A_ADDRESS_WIDTH-1:0]   address_a,
  input       [B_ADDRESS_WIDTH-1:0]   address_b,
  
  // Optional delay data ports
  input       [DELAY_DATA_WIDTH-1:0]  ddata_in,
  output reg  [DELAY_DATA_WIDTH-1:0]  ddata_out
);

  // 3-stage pipelined multiplier matching Xilinx MULT_MACRO LATENCY=3
  reg [A_DATA_WIDTH-1:0] data_a_d1;
  reg [B_DATA_WIDTH-1:0] data_b_d1;
  reg [DW-1:0] data_p_d1;
  reg [DELAY_DATA_WIDTH-1:0] ddata_d1;
  reg [DELAY_DATA_WIDTH-1:0] ddata_d2;
  
  // Stage 1: Register inputs
  always @(posedge clk) begin
    data_a_d1 <= data_a;
    data_b_d1 <= data_b;
    ddata_d1 <= ddata_in;
  end
  
  // Stage 2: Multiply and register
  always @(posedge clk) begin
    data_p_d1 <= $signed(data_a_d1) * $signed(data_b_d1);
    ddata_d2 <= ddata_d1;
  end
  
  // Stage 3: Final output register (matches MULT_MACRO latency=3)
  always @(posedge clk) begin
    data_p <= data_p_d1;
    ddata_out <= ddata_d2;
  end

endmodule
