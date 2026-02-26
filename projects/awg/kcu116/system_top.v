// modified for KCU116 and AD9144 by Prerna Baranwal 
`timescale 1ns/100ps

module system_top #(
  parameter NUM_LINKS = 2,      // Number of links (default is 1)
  parameter DEVICE_CODE = 1     // Device code for configuration
)(
  // System Clock and Reset
  input                   sys_rst,       // System reset (active high)
  input                   sys_clk_p,     // Differential system clock (positive)
  input                   sys_clk_n,     // Differential system clock (negative)

  // UART Interface
  input                   uart_sin,      // UART serial input
  output                  uart_sout,     // UART serial output

  // DDR4 Interface
  output                  ddr4_act_n,    // DDR4 activate command
  output      [16:0]      ddr4_addr,     // DDR4 address bus
  output      [ 1:0]      ddr4_ba,       // DDR4 bank address
  output      [ 0:0]      ddr4_bg,       // DDR4 bank group
  output                  ddr4_ck_p,     // DDR4 differential clock (positive)
  output                  ddr4_ck_n,     // DDR4 differential clock (negative)
  output      [ 0:0]      ddr4_cke,      // DDR4 clock enable
  output      [ 0:0]      ddr4_cs_n,     // DDR4 chip select (active low)
  inout       [ 3:0]      ddr4_dm_n,     // DDR4 data mask (active low)
  inout       [ 31:0]      ddr4_dq,       // DDR4 data bus
  inout       [ 3:0]      ddr4_dqs_p,    // DDR4 differential data strobe (positive)
  inout       [ 3:0]      ddr4_dqs_n,    // DDR4 differential data strobe (negative)
  output      [ 0:0]      ddr4_odt,      // DDR4 on-die termination
  output                  ddr4_reset_n,  // DDR4 reset (active low)

  // GPIO and I2C Interface
  inout       [16:0]      gpio_bd,       // Board GPIOs
 
  inout                   iic_scl,       // I2C serial clock
  inout                   iic_sda,       // I2C serial data

  // AD9144 DAC Interface
  input                   tx_ref_clk_p,  // Differential transmit reference clock (positive)
  input                   tx_ref_clk_n,  // Differential transmit reference clock (negative)
  input                   tx_sysref_p,   // Differential transmit sysref (positive)
  input                   tx_sysref_n,   // Differential transmit sysref (negative)
  input       [1:0]       tx_sync_p,     // Differential transmit sync (positive)
  input       [1:0]       tx_sync_n,     // Differential transmit sync (negative)
  output      [ 3:0]      tx_data_p,     // Differential transmit data (positive)
  output      [ 3:0]      tx_data_n,     // Differential transmit data (negative)

  // SPI Interface for AD9144 DAC
  output                  spi_csn_clk,   // SPI chip select for clock device
  output                  spi_csn_dac,   // SPI chip select for DAC device
  output                  spi_clk,       // SPI clock
  input                   spi_miso,      // SPI master in slave out
  output                  spi_mosi,      // SPI master out slave in 
  output                  spi_en,        // SPI enable (direction control for spi_sdio)

  // DAC Control Signals
  inout       [1:0]       dac_ctrl       // DAC control signals (e.g., FMC_HPC0_LA07_P)
);

  // Internal Signals
  wire    [63:0]  gpio_i;               // GPIO input data
  wire    [63:0]  gpio_o;               // GPIO output data
  wire    [63:0]  gpio_t;               // GPIO tri-state control
  wire    [ 1:0]  spi_csn;              // SPI chip select signals
  wire            tx_ref_clk;           // Single-ended transmit reference clock
  wire            tx_sysref;            // Single-ended transmit sysref
  wire    [1:0]   tx_sync;              // Single-ended transmit sync signals
  wire            tx_sysref_loc;        // Local sysref signal (device-specific)
  wire            dac_fifo_bypass;      // DAC FIFO bypass signal



  assign spi_en = (DEVICE_CODE <= 2);

  // Assign chip select signals
  assign spi_csn_dac = spi_csn[1];      // Chip select for DAC device
  assign spi_csn_clk = spi_csn[0];      // Chip select for clock device

  // Instantiate awg_spi module for SPI communication
 /*
  awg_spi i_spi (
    .reset      (sys_rst),              // System reset
    .spi_csn    (spi_csn[1:0]),         // SPI chip select signals
    .spi_clk    (spi_clk),              // SPI clock
    .spi_mosi   (spi_mosi),             // SPI Master Out Slave In
    .spi_miso   (spi_miso),             // SPI Master In Slave Out
    .spi_en    (spi_en)                // SPI direction control (enable)
  );
*/
  // Instantiate IBUFDS for differential clock inputs
  IBUFDS_GTE4 i_ibufds_tx_ref_clk (
    .CEB  (1'd0),                       // Clock enable (active low)
    .I    (tx_ref_clk_p),               // Positive differential clock input
    .IB   (tx_ref_clk_n),               // Negative differential clock input
    .O    (tx_ref_clk),                 // Single-ended clock output
    .ODIV2()                            // Divided clock output (unused)
  );

  // Instantiate IBUFDS for differential sysref input
  IBUFDS i_ibufds_tx_sysref (
    .I    (tx_sysref_p),                // Positive differential sysref input
    .IB   (tx_sysref_n),                // Negative differential sysref input
    .O    (tx_sysref)                   // Single-ended sysref output
  );

  // Instantiate IBUFDS for differential sync inputs
  IBUFDS i_ibufds_tx_sync_0 (
    .I    (tx_sync_p[0]),               // Positive differential sync input (channel 0)
    .IB   (tx_sync_n[0]),               // Negative differential sync input (channel 0)
    .O    (tx_sync[0])                  // Single-ended sync output (channel 0)
  );

  IBUFDS i_ibufds_tx_sync_1 (
    .I    (tx_sync_p[1]),               // Positive differential sync input (channel 1)
    .IB   (tx_sync_n[1]),               // Negative differential sync input (channel 1)
    .O    (tx_sync[1])                  // Single-ended sync output (channel 1)
  );

  // Instantiate GPIO buffers for DAC control signals
  ad_iobuf #(
    .DATA_WIDTH(2)                      // 2-bit GPIO buffer
  ) i_iobuf (
    .dio_t (gpio_t[21+:2]),             // Tri-state control
    .dio_i (gpio_o[21+:2]),             // Input data
    .dio_o (gpio_i[21+:2]),             // Output data
    .dio_p (dac_ctrl)                   // Physical pins
  );

  // Assign DAC FIFO bypass signal
  assign dac_fifo_bypass = gpio_o[18];

  // Instantiate GPIO buffers for board GPIOs
  ad_iobuf #(
    .DATA_WIDTH(17)                     // 17-bit GPIO buffer
  ) i_iobuf_bd (
    .dio_t (gpio_t[0+:17]),             // Tri-state control
    .dio_i (gpio_o[0+:17]),             // Input data
    .dio_o (gpio_i[0+:17]),             // Output data
    .dio_p (gpio_bd)                    // Physical pins
  );

  // Connect unused GPIOs
  assign gpio_i[63:23] = gpio_o[63:23];
  assign gpio_i[20:19] = gpio_o[20:19];

  // Instantiate system wrapper
  system_wrapper i_system_wrapper (
    // DDR4 Interface
    .c0_ddr4_act_n   (ddr4_act_n),
    .c0_ddr4_adr     (ddr4_addr),
    .c0_ddr4_ba      (ddr4_ba),
    .c0_ddr4_bg      (ddr4_bg),
    .c0_ddr4_ck_c    (ddr4_ck_n),
    .c0_ddr4_ck_t    (ddr4_ck_p),
    .c0_ddr4_cke     (ddr4_cke),
    .c0_ddr4_cs_n    (ddr4_cs_n),
    .c0_ddr4_dm_n    (ddr4_dm_n),
    .c0_ddr4_dq      (ddr4_dq),
    .c0_ddr4_dqs_c   (ddr4_dqs_n),
    .c0_ddr4_dqs_t   (ddr4_dqs_p),
    .c0_ddr4_odt     (ddr4_odt),
    .c0_ddr4_reset_n (ddr4_reset_n),

    // GPIO Interface
    .gpio0_i         (gpio_i[31:0]),
    .gpio0_o         (gpio_o[31:0]),
    .gpio0_t         (gpio_t[31:0]),
    .gpio1_i         (gpio_i[63:32]),
    .gpio1_o         (gpio_o[63:32]),
    .gpio1_t         (gpio_t[63:32]),

    // I2C Interface
    .iic_main_scl_io (iic_scl),
    .iic_main_sda_io (iic_sda),

    // SPI Interface
    .spi_clk_i       (spi_clk),
    .spi_clk_o       (spi_clk),
    .spi_csn_i       (spi_csn),
    .spi_csn_o       (spi_csn),
    .spi_sdi_i       (spi_miso),
    .spi_sdo_i       (spi_mosi),
    .spi_sdo_o       (spi_mosi),

    // System Clock and Reset
    .sys_clk_clk_n   (sys_clk_n),
    .sys_clk_clk_p   (sys_clk_p),
    .sys_rst         (sys_rst),

    // AD9144 DAC Interface
    .tx_data_0_n     (tx_data_n[0]),
    .tx_data_0_p     (tx_data_p[0]),
    .tx_data_1_n     (tx_data_n[1]),
    .tx_data_1_p     (tx_data_p[1]),
    .tx_data_2_n     (tx_data_n[2]),
    .tx_data_2_p     (tx_data_p[2]),
    .tx_data_3_n     (tx_data_n[3]),
    .tx_data_3_p     (tx_data_p[3]),
    .tx_ref_clk_0    (tx_ref_clk),
    .tx_sync_0       (tx_sync),
    .tx_sysref_0     (tx_sysref),

    // UART Interface
    .uart_sin        (uart_sin),
    .uart_sout       (uart_sout),

    // DAC FIFO Bypass
    .dac_fifo_bypass (dac_fifo_bypass)
  );

  // Assign local sysref signal based on device code
  assign tx_sysref_loc = (DEVICE_CODE == 3) ? tx_sync[1] : tx_sysref;

endmodule