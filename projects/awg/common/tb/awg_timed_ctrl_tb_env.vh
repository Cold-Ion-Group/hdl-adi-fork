  localparam [7:0] REG_CTRL             = 8'h00;
  localparam [7:0] REG_STATUS           = 8'h04;
  localparam [7:0] REG_EVENT_COUNT      = 8'h08;
  localparam [7:0] REG_CUR_EVENT        = 8'h0C;
  localparam [7:0] REG_ERR_REG          = 8'h10;
  localparam [7:0] REG_IP_ID            = 8'h14;
  localparam [7:0] REG_IP_VERSION       = 8'h18;
  localparam [7:0] REG_IP_CAPS          = 8'h1C;
  localparam [7:0] REG_TIME_NOW_LO      = 8'h20;
  localparam [7:0] REG_TIME_NOW_HI      = 8'h24;
  localparam [7:0] REG_LAST_EXEC_LO     = 8'h28;
  localparam [7:0] REG_LAST_EXEC_HI     = 8'h2C;
  localparam [7:0] REG_COMMIT_COUNT     = 8'h30;
  localparam [7:0] REG_REINIT_COUNT     = 8'h34;
  localparam [7:0] REG_REINIT_REJECT    = 8'h38;
  localparam [7:0] REG_IRQ_STATUS       = 8'h3C;
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
  localparam [7:0] REG_STREAM_CTRL      = 8'h78;
  localparam [7:0] REG_OCCUPANCY        = 8'h7C;
  localparam [7:0] REG_FREE_SPACE       = 8'h80;
  localparam [7:0] REG_LOW_WMARK        = 8'h84;
  localparam [7:0] REG_STREAM_DEPTH     = 8'h88;
  localparam [7:0] REG_STREAM_PUSHES    = 8'h8C;
  localparam [7:0] REG_STREAM_STALLS    = 8'h90;

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
  reg [255:0] dma_s_axis_tdata = 256'h0;
  reg         dma_s_axis_tvalid = 1'b0;
  wire        dma_s_axis_tready;
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
  reg [31:0] read_data;
  reg [63:0] read_data64;

  awg_timed_ctrl #(
    .EVENT_MEM_ADDR_WIDTH(TB_EVENT_ADDR_WIDTH),
    .STREAM_ADDR_WIDTH(TB_STREAM_ADDR_WIDTH)
  ) dut (
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
    .dma_s_axis_tdata(dma_s_axis_tdata),
    .dma_s_axis_tvalid(dma_s_axis_tvalid),
    .dma_s_axis_tready(dma_s_axis_tready),
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
    $dumpfile(VCD_FILE);
    $dumpvars(0, testbench);
  end

  task automatic test_fail;
    input [255:0] label;
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

  task automatic expect_eq64;
    input [255:0] label;
    input [63:0] got;
    input [63:0] exp;
    begin
      if (got !== exp) begin
        failures = failures + 1;
        $display("[%0t] FAIL: %0s got=0x%016x exp=0x%016x", $time, label, got, exp);
      end
    end
  endtask

  task automatic expect_true;
    input [255:0] label;
    input cond;
    begin
      if (!cond)
        test_fail(label);
    end
  endtask

  task automatic finish_test;
    begin
      repeat (8) @(posedge s_axi_aclk);
      if (failures == 0)
        $display("SUCCESS");
      else
        $display("FAILED: %0d failure(s)", failures);
      $finish;
    end
  endtask

  task automatic reset_dut;
    begin
      s_axi_aresetn = 1'b0;
      sched_reset = 1'b1;
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      s_axi_bready = 1'b0;
      s_axi_arvalid = 1'b0;
      s_axi_rready = 1'b0;
      dma_s_axis_tdata = 256'h0;
      dma_s_axis_tvalid = 1'b0;
      repeat (6) @(posedge s_axi_aclk);
      s_axi_aresetn = 1'b1;
      repeat (4) @(posedge sched_clk);
      sched_reset = 1'b0;
      repeat (4) @(posedge s_axi_aclk);
    end
  endtask

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

  task automatic axi_write;
    input [7:0] addr;
    input [31:0] data;
    input [3:0] strb;
    integer timeout;
    begin
      s_axi_bready = 1'b0;

      fork
        begin : aw_thread
          integer aw_timeout;
          @(negedge s_axi_aclk);
          s_axi_awaddr = addr;
          s_axi_awvalid = 1'b1;
          aw_timeout = 0;
          while (!(s_axi_awvalid && s_axi_awready)) begin
            @(posedge s_axi_aclk);
            aw_timeout = aw_timeout + 1;
            if (aw_timeout > 64) begin
              test_fail("AW handshake timeout");
              disable aw_thread;
            end
          end
          @(negedge s_axi_aclk);
          s_axi_awvalid = 1'b0;
        end

        begin : w_thread
          integer w_timeout;
          @(negedge s_axi_aclk);
          s_axi_wdata = data;
          s_axi_wstrb = strb;
          s_axi_wvalid = 1'b1;
          w_timeout = 0;
          while (!(s_axi_wvalid && s_axi_wready)) begin
            @(posedge s_axi_aclk);
            w_timeout = w_timeout + 1;
            if (w_timeout > 64) begin
              test_fail("W handshake timeout");
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
          test_fail("BVALID timeout");
          disable axi_write;
        end
      end

      @(negedge s_axi_aclk);
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_bvalid && s_axi_bready)) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          test_fail("B handshake timeout");
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
        if (timeout > 128) begin
          test_fail("AXI read address timeout");
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
        if (timeout > 128) begin
          test_fail("AXI read data timeout");
          disable axi_read;
        end
      end
      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_read64;
    input [7:0] lo_addr;
    input [7:0] hi_addr;
    output [63:0] data;
    reg [31:0] lo_word;
    reg [31:0] hi_word;
    begin
      axi_read(lo_addr, lo_word);
      axi_read(hi_addr, hi_word);
      data = {hi_word, lo_word};
    end
  endtask

  task automatic set_stream_mode;
    input bit enable;
    begin
      axi_write(REG_STREAM_CTRL, enable ? 32'h1 : 32'h0, 4'b0001);
    end
  endtask

  task automatic set_low_wmark;
    input [31:0] value;
    begin
      axi_write(REG_LOW_WMARK, value, 4'hf);
    end
  endtask

  task automatic arm_scheduler;
    begin
      axi_write(REG_CTRL, 32'h00000002, 4'b0001);
    end
  endtask

  task automatic run_scheduler;
    begin
      axi_write(REG_CTRL, 32'h00000001, 4'b0001);
    end
  endtask

  task automatic stop_scheduler;
    begin
      axi_write(REG_CTRL, 32'h00000004, 4'b0001);
    end
  endtask

  task automatic soft_reset_scheduler;
    begin
      axi_write(REG_CTRL, 32'h00000008, 4'b0001);
    end
  endtask

  task automatic legacy_load_event;
    input [31:0] index;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w2;
    input [31:0] w3;
    input [31:0] w4;
    input [31:0] w5;
    input [31:0] w6;
    integer timeout;
    reg prev_ack;
    begin
      axi_write(REG_EVT_WADDR, index, 4'hf);
      axi_write(REG_EVT_WDATA0, w0, 4'hf);
      axi_write(REG_EVT_WDATA1, w1, 4'hf);
      axi_write(REG_EVT_WDATA2, w2, 4'hf);
      axi_write(REG_EVT_WDATA3, w3, 4'hf);
      axi_write(REG_EVT_WDATA4, w4, 4'hf);
      axi_write(REG_EVT_WDATA5, w5, 4'hf);
      axi_write(REG_EVT_WDATA6, w6, 4'hf);
      prev_ack = dut.event_wr_ack_tgl;
      axi_write(REG_EVT_WCTRL, 32'h1, 4'b0001);
      timeout = 0;
      while (dut.event_wr_ack_tgl === prev_ack) begin
        @(posedge sched_clk);
        timeout = timeout + 1;
        if (timeout > 64) begin
          test_fail("legacy event write ack timeout");
          disable legacy_load_event;
        end
      end
    end
  endtask

  task automatic stream_push_event;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w2;
    input [31:0] w3;
    input [31:0] w4;
    input [31:0] w5;
    input [31:0] w6;
    begin
      axi_write(REG_EVT_WDATA0, w0, 4'hf);
      axi_write(REG_EVT_WDATA1, w1, 4'hf);
      axi_write(REG_EVT_WDATA2, w2, 4'hf);
      axi_write(REG_EVT_WDATA3, w3, 4'hf);
      axi_write(REG_EVT_WDATA4, w4, 4'hf);
      axi_write(REG_EVT_WDATA5, w5, 4'hf);
      axi_write(REG_EVT_WDATA6, w6, 4'hf);
      axi_write(REG_EVT_WCTRL, 32'h1, 4'b0001);
    end
  endtask

  task automatic dma_push_word;
    input [255:0] word;
    integer timeout;
    integer done;
    begin
      @(negedge s_axi_aclk);
      dma_s_axis_tdata = word;
      dma_s_axis_tvalid = 1'b1;
      timeout = 0;
      done = 0;
      while (!done) begin
        @(posedge s_axi_aclk);
        if (dma_s_axis_tready)
          done = 1;
        else begin
          timeout = timeout + 1;
          if (timeout > 128) begin
            test_fail("DMA stream handshake timeout");
            done = 1;
          end
        end
      end
      @(negedge s_axi_aclk);
      dma_s_axis_tvalid = 1'b0;
      dma_s_axis_tdata = 256'h0;
    end
  endtask

  task automatic wait_for_done;
    integer timeout;
    reg [31:0] status_word;
    begin
      timeout = 0;
      while (1'b1) begin
        axi_read(REG_STATUS, status_word);
        if (status_word[2])
          disable wait_for_done;
        if (status_word[3]) begin
          test_fail("wait_for_done saw error state");
          disable wait_for_done;
        end
        timeout = timeout + 1;
        if (timeout > 256) begin
          test_fail("wait_for_done timeout");
          disable wait_for_done;
        end
      end
    end
  endtask

  task automatic wait_for_error;
    integer timeout;
    reg [31:0] status_word;
    begin
      timeout = 0;
      while (1'b1) begin
        axi_read(REG_STATUS, status_word);
        if (status_word[3])
          disable wait_for_error;
        timeout = timeout + 1;
        if (timeout > 256) begin
          test_fail("wait_for_error timeout");
          disable wait_for_error;
        end
      end
    end
  endtask
