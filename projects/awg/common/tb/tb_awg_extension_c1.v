`timescale 1ns/1ps

module testbench;
  reg clk = 1'b0;
  reg resetn = 1'b0;
  always #5 clk = ~clk;

  reg [8:0] awaddr = 0;
  reg [2:0] awprot = 0;
  reg awvalid = 0;
  wire awready;
  reg [31:0] wdata = 0;
  reg [3:0] wstrb = 0;
  reg wvalid = 0;
  wire wready;
  wire [1:0] bresp;
  wire bvalid;
  reg bready = 0;
  reg [8:0] araddr = 0;
  reg [2:0] arprot = 0;
  reg arvalid = 0;
  wire arready;
  wire [31:0] rdata;
  wire [1:0] rresp;
  wire rvalid;
  reg rready = 0;

  reg [255:0] in_data = 0;
  reg in_valid = 0;
  wire in_ready;
  wire [255:0] out_data;
  wire out_valid;
  reg out_ready = 1;
  wire extension_error;
  wire extension_error_toggle;
  integer failures = 0;
  integer output_count = 0;
  integer run_number = -1;
  time previous_output_time = 0;

  localparam [255:0] HEADER0 = 256'h0000000000000002000000000000006400000001002000400000000143475741;
  localparam [255:0] HEADER1 = 256'h0000000000000000cf4a035d10a1aba300000000000000400000000000000001;
  localparam [255:0] WAIT8   = 256'h0000000000000000000000000000000000000000000000000000000800000001;
  localparam [255:0] FIRE    = 256'h000000000123456789abcdef0011223344556677000000080000000100030002;
  localparam [255:0] EVENT   = 256'h000000000123456789abcdef001122334455667700030003000000000000006c;
  localparam [255:0] L_HEADER0 = 256'h0000000100000005000000000000006400000001002000400000000143475741;
  localparam [255:0] L_HEADER1 = 256'h0000000000000000a7abf37f6e9c6d2100000000000000a00000000000000006;
  localparam [255:0] L_REPEAT  = 256'h0000000000000000000000000000000000000000000000000000000200000005;
  localparam [255:0] L_LINEAR  = 256'h000000000000001e000000140000000a00000008000000030000000000030003;
  localparam [255:0] L_CONT    = 256'h0000000000000000000000030000000000000002000000000000000100000004;
  localparam [255:0] L_END     = 256'h0000000000000000000000000000000000000000000000000000000000000006;

  awg_extension #(.C1_IMPLEMENTED(1), .COMMAND_ADDR_WIDTH(4)) dut (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arprot(arprot), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .s_axis_tdata(in_data), .s_axis_tvalid(in_valid), .s_axis_tready(in_ready),
    .m_axis_tdata(out_data), .m_axis_tvalid(out_valid), .m_axis_tready(out_ready),
    .extension_error(extension_error), .extension_error_toggle(extension_error_toggle)
  );

  task fail;
    input [255:0] label;
    begin failures = failures + 1; $display("FAIL: %0s", label); end
  endtask

  task axi_write;
    input [8:0] addr;
    input [31:0] data;
    begin
      @(negedge clk);
      awaddr = addr; wdata = data; wstrb = 4'hf; awvalid = 1; wvalid = 1;
      while (!(awready && wready)) @(posedge clk);
      @(negedge clk); awvalid = 0; wvalid = 0; wstrb = 0; bready = 1;
      while (!bvalid) @(posedge clk);
      @(negedge clk); bready = 0;
    end
  endtask

  task push;
    input [255:0] data;
    begin
      @(negedge clk); in_data = data; in_valid = 1;
      while (!in_ready) @(posedge clk);
      @(negedge clk); in_valid = 0; in_data = 0;
    end
  endtask

  always @(posedge clk) begin
    if (out_valid && out_ready) begin
      if (run_number == -1) begin
        if (out_data !== EVENT)
          fail("direct bypass changed a scheduler event");
      end else if (run_number == 0) begin
        if (out_data !== EVENT)
          fail("decoded FIRE differs from scheduler ABI v1 golden");
      end else begin
        if (output_count > 0 && ($time - previous_output_time) != 10)
          fail("LINEAR decoder inserted an output bubble");
        case (output_count)
          0: if (out_data !== 256'h000000000000000000000000001e00000014000a00000003000000000000006c) fail("linear event 0");
          1: if (out_data !== 256'h000000000000000000000000002100000016000b000000030000000000000074) fail("linear event 1");
          2: if (out_data !== 256'h000000000000000000000000002400000018000c00000003000000000000007c) fail("linear event 2");
          3: if (out_data !== 256'h000000000000000000000000001e00000014000a000000030000000000000084) fail("repeat event 0");
          4: if (out_data !== 256'h000000000000000000000000002100000016000b00000003000000000000008c) fail("repeat event 1");
          5: if (out_data !== 256'h000000000000000000000000002400000018000c000200030000000000000094) fail("repeat EOF event");
          default: fail("too many linear/repeat events");
        endcase
      end
      previous_output_time = $time;
      output_count = output_count + 1;
    end
  end

  initial begin
    repeat (6) @(posedge clk);
    resetn = 1;
    repeat (4) @(posedge clk);

    // Direct mode is a transparent one-beat bypass with the same address map.
    push(EVENT);
    repeat (4) @(posedge clk);
    if (output_count != 1) fail("direct bypass event count mismatch");
    output_count = 0;
    previous_output_time = 0;
    run_number = 0;
    axi_write(9'h00c, 32'h1);
    push(HEADER0);
    push(HEADER1);
    push(WAIT8);
    push(FIRE);

    repeat (80) @(posedge clk);
    if (output_count != 1) fail("decoder did not emit exactly one event");
    if (dut.error_reg != 0) fail("decoder latched an unexpected error");
    if (dut.emitted_events != 1) fail("event telemetry mismatch");
    if (dut.records_accepted != 2) fail("record telemetry mismatch");
    if (dut.output_crc != 64'h0b631523d3b88f0b) fail("output CRC mismatch");
    if (dut.state != 11) fail("decoder did not reach DONE");

    // Exercise the continuation record, signed DDS steps, and repeat stack.
    axi_write(9'h00c, 32'h3);
    repeat (4) @(posedge clk);
    run_number = 1;
    output_count = 0;
    push(L_HEADER0);
    push(L_HEADER1);
    push(WAIT8);
    push(L_REPEAT);
    push(L_LINEAR);
    push(L_CONT);
    push(L_END);
    repeat (160) @(posedge clk);
    if (output_count != 6) fail("linear/repeat event count mismatch");
    if (dut.records_accepted != 5) fail("linear/repeat record count mismatch");
    if (dut.max_depth_seen != 1) fail("repeat depth telemetry mismatch");
    if (dut.output_crc != 64'he4e8ab671aa5cf40) fail("linear/repeat output CRC mismatch");
    if (dut.error_reg != 0 || dut.state != 11) fail("linear/repeat program did not finish cleanly");

    // The complete compact program is buffered and CRC-checked before any
    // scheduler event is emitted.
    axi_write(9'h00c, 32'h3);
    repeat (4) @(posedge clk);
    run_number = 2;
    output_count = 0;
    push(HEADER0);
    push(HEADER1 ^ (256'h1 << 128));
    push(WAIT8);
    push(FIRE);
    repeat (24) @(posedge clk);
    if (output_count != 0) fail("bad-CRC program emitted an event");
    if (dut.state != 12 || !dut.error_reg[5]) fail("bad-CRC program did not latch ERR_BAD_CRC");
    if (!extension_error || !extension_error_toggle) fail("decoder error did not reach sideband outputs");

    if (failures == 0) $display("SUCCESS");
    else $display("FAILED: %0d", failures);
    $finish;
  end
endmodule
