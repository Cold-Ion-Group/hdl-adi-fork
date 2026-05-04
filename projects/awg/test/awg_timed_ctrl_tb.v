`timescale 1ns/1ps

module awg_timed_ctrl_tb;

  localparam [7:0] REG_CTRL             = 8'h00;
  localparam [7:0] REG_EVENT_COUNT      = 8'h08;
  localparam [7:0] REG_IP_ID            = 8'h14;
  localparam [7:0] REG_IP_VERSION       = 8'h18;
  localparam [7:0] REG_IP_CAPS          = 8'h1C;
  localparam [7:0] REG_EVT_WADDR        = 8'h40;
  localparam [7:0] REG_EVT_WDATA0       = 8'h44;
  localparam [7:0] REG_EVT_WDATA1       = 8'h48;
  localparam [7:0] REG_EVT_WDATA2       = 8'h4C;
  localparam [7:0] REG_EVT_WDATA3       = 8'h50;
  localparam [7:0] REG_EVT_WDATA4       = 8'h54;
  localparam [7:0] REG_EVT_WDATA5       = 8'h58;
  localparam [7:0] REG_EVT_WDATA6       = 8'h5C;
  localparam [7:0] REG_EVT_WCTRL        = 8'h60;
  localparam [7:0] REG_IRQ_ENABLE       = 8'h64;
  localparam [7:0] REG_IP_SCRATCH       = 8'h68;
  localparam [7:0] REG_TIME_RELOAD_LO   = 8'h6C;
  localparam [7:0] REG_TIME_RELOAD_HI   = 8'h70;
  localparam [7:0] REG_TIME_RELOAD_CTRL = 8'h74;

  reg         s_axi_aclk = 1'b0;
  reg         s_axi_aresetn = 1'b0;
  reg  [7:0]  s_axi_awaddr = 8'h0;
  reg  [2:0]  s_axi_awprot = 3'b000;
  reg         s_axi_awvalid = 1'b0;
  wire        s_axi_awready;
  reg  [31:0] s_axi_wdata = 32'h0;
  reg  [3:0]  s_axi_wstrb = 4'h0;
  reg         s_axi_wvalid = 1'b0;
  wire        s_axi_wready;
  wire [1:0]  s_axi_bresp;
  wire        s_axi_bvalid;
  reg         s_axi_bready = 1'b0;
  reg  [7:0]  s_axi_araddr = 8'h0;
  reg  [2:0]  s_axi_arprot = 3'b000;
  reg         s_axi_arvalid = 1'b0;
  wire        s_axi_arready;
  wire [31:0] s_axi_rdata;
  wire [1:0]  s_axi_rresp;
  wire        s_axi_rvalid;
  reg         s_axi_rready = 1'b0;

  reg         sched_clk = 1'b0;
  reg         sched_reset = 1'b1;
  reg         sysref_pulse = 1'b0;
  wire        marker_commit;
  wire        marker_start;
  wire        marker_done;
  wire [127:0] sched_scale_s;
  wire [255:0] sched_init_s;
  wire [255:0] sched_incr_s;
  wire [7:0]  sched_apply_s;
  wire        sched_phase_reinit;
  wire        irq;

  integer failures = 0;
  integer seed = 32'h1badf00d;

  reg [31:0] expected_scratch;
  reg [31:0] expected_event_count;
  reg [31:0] expected_irq_enable;
  reg [31:0] expected_reload_lo;
  reg [31:0] expected_reload_hi;
  reg [31:0] expected_evt_waddr;
  reg [31:0] expected_evt_wdata0;
  reg [31:0] expected_evt_wdata1;
  reg [31:0] expected_evt_wdata2;
  reg [31:0] expected_evt_wdata3;
  reg [31:0] expected_evt_wdata4;
  reg [31:0] expected_evt_wdata5;
  reg [31:0] expected_evt_wdata6;

  reg [31:0] read_data;
  reg [255:0] expected_event_word;
  reg prev_run_tgl;
  reg prev_arm_tgl;
  reg prev_stop_tgl;
  reg prev_sreset_tgl;
  reg prev_load_sysref_tgl;
  reg prev_load_now_tgl;
  reg prev_event_wr_ack_tgl;
  integer i;
  integer sel;
  integer aw_delay;
  integer w_delay;
  reg [7:0] rand_addr;
  reg [31:0] rand_data;
  reg [3:0] rand_strb;
  reg [31:0] expected_readback;

  awg_timed_ctrl dut (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .sched_clk(sched_clk),
    .sched_reset(sched_reset),
    .sysref_pulse(sysref_pulse),
    .marker_commit(marker_commit),
    .marker_start(marker_start),
    .marker_done(marker_done),
    .sched_scale_s(sched_scale_s),
    .sched_init_s(sched_init_s),
    .sched_incr_s(sched_incr_s),
    .sched_apply_s(sched_apply_s),
    .sched_phase_reinit(sched_phase_reinit),
    .irq(irq)
  );

  always #5 s_axi_aclk = ~s_axi_aclk;
  always #4 sched_clk = ~sched_clk;

  initial begin
    $dumpfile("awg_timed_ctrl_tb.vcd");
    $dumpvars(0, awg_timed_ctrl_tb);
  end

  initial begin
    expected_scratch     = 32'h0;
    expected_event_count = 32'h0;
    expected_irq_enable  = 32'h0;
    expected_reload_lo   = 32'h0;
    expected_reload_hi   = 32'h0;
    expected_evt_waddr   = 32'h0;
    expected_evt_wdata0  = 32'h0;
    expected_evt_wdata1  = 32'h0;
    expected_evt_wdata2  = 32'h0;
    expected_evt_wdata3  = 32'h0;
    expected_evt_wdata4  = 32'h0;
    expected_evt_wdata5  = 32'h0;
    expected_evt_wdata6  = 32'h0;

    repeat (6) @(posedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (4) @(posedge sched_clk);
    sched_reset = 1'b0;
    repeat (4) @(posedge s_axi_aclk);

    // Basic read path sanity
    axi_read(REG_IP_ID, read_data);
    expect_eq32("IP_ID", read_data, 32'h41574753);
    axi_read(REG_IP_VERSION, read_data);
    expect_eq32("IP_VERSION", read_data, 32'h00010000);
    axi_read(REG_IP_CAPS, read_data);
    expect_eq32("IP_CAPS", read_data, 32'h08804000);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("IP_SCRATCH reset", read_data, expected_scratch);

    // Directed write timing cases that reproduce the XSDB failure mode.
    expected_scratch = 32'h89abcdef;
    axi_write(REG_IP_SCRATCH, expected_scratch, 4'hf, 0, 0, 0);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("scratch same-cycle", read_data, expected_scratch);

    expected_scratch = 32'h12345678;
    axi_write(REG_IP_SCRATCH, expected_scratch, 4'hf, 3, 0, 0);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("scratch AW-before-W", read_data, expected_scratch);

    expected_scratch = 32'hdeadbeef;
    axi_write(REG_IP_SCRATCH, expected_scratch, 4'hf, 0, 4, 0);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("scratch W-before-AW", read_data, expected_scratch);

    expected_scratch = apply_wstrb32(expected_scratch, 32'h00aa5500, 4'b0110);
    axi_write(REG_IP_SCRATCH, 32'h00aa5500, 4'b0110, 2, 1, 0);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("scratch partial strobe", read_data, expected_scratch);

    // Response backpressure: BVALID must hold and prevent a new write until consumed.
    expected_scratch = 32'hcafebabe;
    axi_write(REG_IP_SCRATCH, expected_scratch, 4'hf, 1, 2, 5);
    axi_read(REG_IP_SCRATCH, read_data);
    expect_eq32("scratch after delayed BREADY", read_data, expected_scratch);

    // Randomized coverage over readable RW registers with channel skew.
    for (i = 0; i < 24; i = i + 1) begin
      sel = rand_mod(12);
      rand_data = $random(seed);
      rand_strb = rand_nonzero_strb(0);
      aw_delay = rand_mod(4);
      w_delay = rand_mod(4);

      case (sel)
        0: begin
          rand_addr = REG_EVENT_COUNT;
          expected_event_count = apply_wstrb32(expected_event_count, rand_data, rand_strb);
          expected_readback = expected_event_count;
        end
        1: begin
          rand_addr = REG_IRQ_ENABLE;
          expected_irq_enable = apply_wstrb32(expected_irq_enable, rand_data, rand_strb);
          expected_readback = expected_irq_enable;
        end
        2: begin
          rand_addr = REG_TIME_RELOAD_LO;
          expected_reload_lo = apply_wstrb32(expected_reload_lo, rand_data, rand_strb);
          expected_readback = expected_reload_lo;
        end
        3: begin
          rand_addr = REG_TIME_RELOAD_HI;
          expected_reload_hi = apply_wstrb32(expected_reload_hi, rand_data, rand_strb);
          expected_readback = expected_reload_hi;
        end
        4: begin
          rand_addr = REG_EVT_WADDR;
          expected_evt_waddr = rand_data & 32'h000000ff;
          expected_readback = expected_evt_waddr;
        end
        5: begin
          rand_addr = REG_EVT_WDATA0;
          expected_evt_wdata0 = apply_wstrb32(expected_evt_wdata0, rand_data, rand_strb);
          expected_readback = expected_evt_wdata0;
        end
        6: begin
          rand_addr = REG_EVT_WDATA1;
          expected_evt_wdata1 = apply_wstrb32(expected_evt_wdata1, rand_data, rand_strb);
          expected_readback = expected_evt_wdata1;
        end
        7: begin
          rand_addr = REG_EVT_WDATA2;
          expected_evt_wdata2 = apply_wstrb32(expected_evt_wdata2, rand_data, rand_strb);
          expected_readback = expected_evt_wdata2;
        end
        8: begin
          rand_addr = REG_EVT_WDATA3;
          expected_evt_wdata3 = apply_wstrb32(expected_evt_wdata3, rand_data, rand_strb);
          expected_readback = expected_evt_wdata3;
        end
        9: begin
          rand_addr = REG_EVT_WDATA4;
          expected_evt_wdata4 = apply_wstrb32(expected_evt_wdata4, rand_data, rand_strb);
          expected_readback = expected_evt_wdata4;
        end
        10: begin
          rand_addr = REG_EVT_WDATA5;
          expected_evt_wdata5 = apply_wstrb32(expected_evt_wdata5, rand_data, rand_strb);
          expected_readback = expected_evt_wdata5;
        end
        default: begin
          rand_addr = REG_EVT_WDATA6;
          expected_evt_wdata6 = apply_wstrb32(expected_evt_wdata6, rand_data, rand_strb);
          expected_readback = expected_evt_wdata6;
        end
      endcase

      axi_write(rand_addr, rand_data, rand_strb, aw_delay, w_delay, 0);
      axi_read(rand_addr, read_data);
      expect_eq32("random RW readback", read_data, expected_readback);
    end

    // Control pulse register: all pulse bits should toggle exactly once and irq_en should stick.
    prev_run_tgl = dut.run_req_tgl;
    prev_arm_tgl = dut.arm_req_tgl;
    prev_stop_tgl = dut.stop_req_tgl;
    prev_sreset_tgl = dut.sreset_req_tgl;
    axi_write(REG_CTRL, 32'h0000010f, 4'b0011, 3, 0, 0);
    @(posedge s_axi_aclk);
    expect_eq1("run_req toggled", dut.run_req_tgl != prev_run_tgl, 1'b1);
    expect_eq1("arm_req toggled", dut.arm_req_tgl != prev_arm_tgl, 1'b1);
    expect_eq1("stop_req toggled", dut.stop_req_tgl != prev_stop_tgl, 1'b1);
    expect_eq1("sreset_req toggled", dut.sreset_req_tgl != prev_sreset_tgl, 1'b1);
    axi_read(REG_CTRL, read_data);
    expect_eq32("CTRL readback sticky irq_en", read_data, 32'h00000100);

    prev_arm_tgl = dut.arm_req_tgl;
    prev_run_tgl = dut.run_req_tgl;
    axi_write(REG_CTRL, 32'h00000002, 4'b0001, 0, 2, 0);
    @(posedge s_axi_aclk);
    expect_eq1("arm_req toggled second time", dut.arm_req_tgl != prev_arm_tgl, 1'b1);
    expect_eq1("run_req unchanged on arm-only write", dut.run_req_tgl, prev_run_tgl);

    // TIME_RELOAD_CTRL: bit0 is sticky, bit1 is write-1 pulse.
    prev_load_sysref_tgl = dut.load_sysref_req_tgl;
    prev_load_now_tgl = dut.load_now_req_tgl;
    axi_write(REG_TIME_RELOAD_CTRL, 32'h00000003, 4'b0001, 1, 4, 0);
    @(posedge s_axi_aclk);
    expect_eq1("load_sysref toggled", dut.load_sysref_req_tgl != prev_load_sysref_tgl, 1'b1);
    expect_eq1("load_now toggled", dut.load_now_req_tgl != prev_load_now_tgl, 1'b1);
    axi_read(REG_TIME_RELOAD_CTRL, read_data);
    expect_eq32("TIME_RELOAD_CTRL readback", read_data, 32'h00000001);
    axi_write(REG_TIME_RELOAD_CTRL, 32'h00000000, 4'b0001, 2, 1, 0);
    axi_read(REG_TIME_RELOAD_CTRL, read_data);
    expect_eq32("TIME_RELOAD_CTRL clear sticky bit", read_data, 32'h00000000);

    // Event push path: mixed-order register writes followed by WCTRL should update BRAM.
    expected_evt_waddr  = 32'h00000005;
    expected_evt_wdata0 = 32'h11223344;
    expected_evt_wdata1 = 32'h55667788;
    expected_evt_wdata2 = 32'habcd1234;
    expected_evt_wdata3 = 32'h0badc0de;
    expected_evt_wdata4 = 32'hfeedface;
    expected_evt_wdata5 = 32'h89abcdef;
    expected_evt_wdata6 = 32'h13579bdf;

    axi_write(REG_EVT_WADDR,  expected_evt_waddr,  4'hf, 0, 3, 0);
    axi_write(REG_EVT_WDATA0, expected_evt_wdata0, 4'hf, 2, 0, 0);
    axi_write(REG_EVT_WDATA1, expected_evt_wdata1, 4'hf, 0, 1, 0);
    axi_write(REG_EVT_WDATA2, expected_evt_wdata2, 4'hf, 4, 0, 0);
    axi_write(REG_EVT_WDATA3, expected_evt_wdata3, 4'hf, 1, 2, 0);
    axi_write(REG_EVT_WDATA4, expected_evt_wdata4, 4'hf, 0, 0, 0);
    axi_write(REG_EVT_WDATA5, expected_evt_wdata5, 4'hf, 3, 1, 0);
    axi_write(REG_EVT_WDATA6, expected_evt_wdata6, 4'hf, 1, 4, 0);

    prev_event_wr_ack_tgl = dut.event_wr_ack_tgl;
    axi_write(REG_EVT_WCTRL, 32'h00000001, 4'b0001, 5, 0, 0);
    wait_for_event_write_ack();
    expected_event_word = pack_event(expected_evt_wdata0,
                                     expected_evt_wdata1,
                                     expected_evt_wdata2,
                                     expected_evt_wdata3,
                                     expected_evt_wdata4,
                                     expected_evt_wdata5,
                                     expected_evt_wdata6);
    expect_eq256("event BRAM write", dut.event_mem[5], expected_event_word);

    repeat (10) @(posedge s_axi_aclk);
    if (failures == 0) begin
      $display("SUCCESS");
    end else begin
      $display("FAILED: %0d failure(s)", failures);
    end
    $finish;
  end

  initial begin
    #250000;
    fail("timeout");
    $display("FAILED");
    $finish;
  end

  function [31:0] apply_wstrb32;
    input [31:0] cur;
    input [31:0] data;
    input [3:0]  strb;
    begin
      apply_wstrb32 = cur;
      if (strb[0]) apply_wstrb32[7:0]   = data[7:0];
      if (strb[1]) apply_wstrb32[15:8]  = data[15:8];
      if (strb[2]) apply_wstrb32[23:16] = data[23:16];
      if (strb[3]) apply_wstrb32[31:24] = data[31:24];
    end
  endfunction

  function [255:0] pack_event;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w2;
    input [31:0] w3;
    input [31:0] w4;
    input [31:0] w5;
    input [31:0] w6;
    begin
      pack_event = {32'h0, w6, w5, w4, w3, {w2[15:0], w2[31:16]}, w1, w0};
    end
  endfunction

  function integer rand_mod;
    input integer modulus;
    integer value;
    begin
      value = $random(seed);
      if (value < 0) value = -value;
      rand_mod = value % modulus;
    end
  endfunction

  function [3:0] rand_nonzero_strb;
    input integer unused;
    integer value;
    begin
      value = rand_mod(15) + 1;
      rand_nonzero_strb = value[3:0];
    end
  endfunction

  task automatic fail;
    input [127:0] label;
    begin
      failures = failures + 1;
      $display("[%0t] FAIL: %0s", $time, label);
    end
  endtask

  task automatic expect_eq1;
    input [255:0] label;
    input got;
    input exp;
    begin
      if (got !== exp) begin
        failures = failures + 1;
        $display("[%0t] FAIL: %0s got=%0b exp=%0b", $time, label, got, exp);
      end
    end
  endtask

  task automatic expect_eq32;
    input [255:0] label;
    input [31:0] got;
    input [31:0] exp;
    begin
      if (got !== exp) begin
        failures = failures + 1;
        $display("[%0t] FAIL: %0s got=0x%08x exp=0x%08x", $time, label, got, exp);
      end
    end
  endtask

  task automatic expect_eq256;
    input [255:0] label;
    input [255:0] got;
    input [255:0] exp;
    begin
      if (got !== exp) begin
        failures = failures + 1;
        $display("[%0t] FAIL: %0s", $time, label);
        $display("  got=0x%064x", got);
        $display("  exp=0x%064x", exp);
      end
    end
  endtask

  task automatic axi_write;
    input [7:0] addr;
    input [31:0] data;
    input [3:0] strb;
    input integer aw_wait_cycles;
    input integer w_wait_cycles;
    input integer bready_wait_cycles;
    integer timeout;
    begin
      s_axi_bready = 1'b0;

      fork
        begin : aw_thread
          integer aw_timeout;
          repeat (aw_wait_cycles) @(posedge s_axi_aclk);
          @(negedge s_axi_aclk);
          s_axi_awaddr = addr;
          s_axi_awvalid = 1'b1;
          aw_timeout = 0;
          while (!(s_axi_awvalid && s_axi_awready)) begin
            @(posedge s_axi_aclk);
            aw_timeout = aw_timeout + 1;
            if (aw_timeout > 64) begin
              fail("AW handshake timeout");
              disable aw_thread;
            end
          end
          @(negedge s_axi_aclk);
          s_axi_awvalid = 1'b0;
        end

        begin : w_thread
          integer w_timeout;
          repeat (w_wait_cycles) @(posedge s_axi_aclk);
          @(negedge s_axi_aclk);
          s_axi_wdata = data;
          s_axi_wstrb = strb;
          s_axi_wvalid = 1'b1;
          w_timeout = 0;
          while (!(s_axi_wvalid && s_axi_wready)) begin
            @(posedge s_axi_aclk);
            w_timeout = w_timeout + 1;
            if (w_timeout > 64) begin
              fail("W handshake timeout");
              disable w_thread;
            end
          end
          @(negedge s_axi_aclk);
          s_axi_wvalid = 1'b0;
          s_axi_wstrb = 4'h0;
        end
      join

      timeout = 0;
      while (s_axi_bvalid !== 1'b1) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          fail("BVALID timeout");
          disable axi_write;
        end
      end

      if (bready_wait_cycles > 0) begin
        expect_eq1("AWREADY held low while response pending", s_axi_awready, 1'b0);
        expect_eq1("WREADY held low while response pending", s_axi_wready, 1'b0);
      end

      repeat (bready_wait_cycles) @(posedge s_axi_aclk);
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_bvalid && s_axi_bready)) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          fail("B handshake timeout");
          disable axi_write;
        end
      end
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic axi_read;
    input [7:0] addr;
    output [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = addr;
      s_axi_arvalid = 1'b1;
      timeout = 0;
      while (!(s_axi_arvalid && s_axi_arready)) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          fail("AR handshake timeout");
          disable axi_read;
        end
      end

      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      s_axi_rready = 1'b1;
      timeout = 0;
      while (s_axi_rvalid !== 1'b1) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          fail("RVALID timeout");
          disable axi_read;
        end
      end

      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic wait_for_event_write_ack;
    integer timeout;
    begin
      timeout = 0;
      while (dut.event_wr_ack_tgl === prev_event_wr_ack_tgl) begin
        @(posedge sched_clk);
        timeout = timeout + 1;
        if (timeout > 32) begin
          fail("event write ack timeout");
          disable wait_for_event_write_ack;
        end
      end
    end
  endtask

endmodule
