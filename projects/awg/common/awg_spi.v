`timescale 1ns/100ps

module awg_spi (
  input                   reset,   // reset signal 
  input       [ 1:0]      spi_csn,   // chip select signals for 2 chips 
  input                   spi_clk,   // SPI clock 
  input                   spi_mosi,  // master out slave in 
  output                  spi_miso, // master in slave out
  output                  spi_en  // direction control for spi_sdo
);

  // internal registers

  reg     [ 5:0]  spi_count = 'd0; // spi clock counter
  reg             spi_rd_wr_n = 'd0; // read write command, 0 is write and 1 is for read
  reg             spi_enable = 'd0; // enabling signal for the spi communication
  reg             chip_select= 'd0; // internal signal to track the chip select
  reg     [7:0]   spi_read_date= 8'hAA;      // register to read data from the slave   

  // internal signals

  wire            spi_csn_s; // combined chip select signal, set to active low for now. 
  wire            spi_enable_s; // enable signal for bi-directional data 

  // check on rising edge and change on falling edge
  // the chip select pin for the AD9144 pin is active low !!!!!!
  // THIS was the main error. 

 assign spi_csn_s = ~(|spi_csn);

// code to see which chip is selected

  always @(*) begin
    if (spi_csn[0] == 1'b0) begin
      chip_select = 1'b0;             // Chip 0 is selected
    end else if (spi_csn[1] == 1'b0) begin
      chip_select = 1'b1;             // Chip 1 is selected
    end else begin
      chip_select = 1'b0;             // Default to Chip 0 
    end
  end


  assign spi_en = ~spi_enable_s; // 0 = output, slave driven, 1= output is driven by the master
  assign spi_enable_s = spi_enable & ~spi_csn_s; // this is enabled only when the chip is selected 

  always @(posedge spi_clk or posedge spi_csn_s) begin
   if(reset) begin
      spi_count <= 6'd0; // reset counter
      spi_rd_wr_n <= 1'd0; // reset command to read and write
   end else if (spi_csn_s == 1'b1) begin
      spi_count <= 6'd0;
      spi_rd_wr_n <= 1'd0;
   end else begin
      spi_count <= (spi_count < 6'h3f) ? spi_count + 1'b1 : spi_count;
      if (spi_count == 6'd0) begin
        spi_rd_wr_n <= spi_mosi;
      end
   end
  end
//  falling edge logic for enabling SPI communication
  always @(negedge spi_clk or posedge reset) begin
    if (reset) begin
      spi_enable <= 1'b0; // disables spi communication on the presence of a reset button
    end else if (spi_csn_s == 1'b1) begin
      spi_enable <= 1'b0;
    end else begin
      if (spi_count == 6'd16) begin
        spi_enable <= spi_rd_wr_n;
      end
    end
  end


// logic for the spi read is not enabled implement it later on. 


endmodule
