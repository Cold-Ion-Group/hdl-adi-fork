// Minimal copy of the ADI HDL testbench base style.
`timescale 1ns/1ps

module tb_base;

  reg clk = 1'b0;
  reg [3:0] reset_shift = 4'b1111;
  reg trigger_reset = 1'b0;
  wire reset;
  wire resetn = ~reset;

  reg failed = 1'b0;

  initial begin
`ifdef VCD_FILE
    $dumpfile(`VCD_FILE);
    $dumpvars;
`endif
`ifdef TIMEOUT
    #`TIMEOUT;
`else
    #100000;
`endif
    if (failed == 1'b0)
      $display("SUCCESS");
    else
      $display("FAILED");
    $finish;
  end

  always @(*) #10 clk <= ~clk;

  always @(posedge clk) begin
    if (trigger_reset == 1'b1)
      reset_shift <= 4'b1111;
    else
      reset_shift <= {reset_shift[2:0], 1'b0};
  end

  assign reset = reset_shift[3];

  task do_trigger_reset;
  begin
    @(posedge clk) trigger_reset <= 1'b1;
    @(posedge clk) trigger_reset <= 1'b0;
  end
  endtask

endmodule
