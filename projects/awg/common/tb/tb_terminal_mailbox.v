`timescale 1ns/1ps

module testbench;
  localparam integer TB_EVENT_ADDR_WIDTH = 8;
  localparam integer TB_STREAM_ADDR_WIDTH = 3;
  localparam VCD_FILE = "tb_terminal_mailbox.vcd";
`include "awg_timed_ctrl_tb_env.vh"

  integer req_count;
  integer ack_count;
  reg req_d;
  reg ack_d;
  reg mailbox_observing;
  reg [31:0] held_status;
  reg [63:0] held_last_exec;
  reg [31:0] held_cur_event;
  reg [5:0] held_irq;
  reg held_eof;
  reg held_mode;

  always @(posedge sched_clk) begin
    req_d <= dut.terminal_req_tgl;
    if (dut.terminal_req_tgl != req_d)
      req_count <= req_count + 1;

    if (dut.terminal_req_tgl != dut.terminal_ack_sync2) begin
      if (!mailbox_observing) begin
        mailbox_observing <= 1'b1;
        held_status <= dut.terminal_status_sched;
        held_last_exec <= dut.terminal_last_exec_sched;
        held_cur_event <= dut.terminal_cur_event_sched;
        held_irq <= dut.terminal_irq_sched;
        held_eof <= dut.terminal_eof_sched;
        held_mode <= dut.terminal_mode_stream_sched;
      end else begin
        if (dut.terminal_status_sched !== held_status ||
            dut.terminal_last_exec_sched !== held_last_exec ||
            dut.terminal_cur_event_sched !== held_cur_event ||
            dut.terminal_irq_sched !== held_irq ||
            dut.terminal_eof_sched !== held_eof ||
            dut.terminal_mode_stream_sched !== held_mode)
          test_fail("terminal mailbox payload changed before acknowledgement");
      end
    end else begin
      mailbox_observing <= 1'b0;
    end
  end

  always @(posedge s_axi_aclk) begin
    ack_d <= dut.terminal_ack_tgl;
    if (dut.terminal_ack_tgl != ack_d)
      ack_count <= ack_count + 1;
  end

  task automatic wait_mailbox_idle;
    integer timeout;
    begin
      timeout = 0;
      while ((dut.terminal_req_tgl !== dut.terminal_ack_sync2) && timeout < 128) begin
        @(posedge sched_clk);
        timeout = timeout + 1;
      end
      if (timeout >= 128)
        test_fail("terminal mailbox acknowledgement timeout");
    end
  endtask

  task automatic wait_for_request_count;
    input integer expected;
    integer timeout;
    begin
      timeout = 0;
      while ((req_count < expected) && timeout < 256) begin
        @(posedge sched_clk);
        timeout = timeout + 1;
      end
      if (timeout >= 256)
        test_fail("terminal request-count timeout");
    end
  endtask

  // Drive an IRQ W1C transaction so write_issue is true on the exact AXI edge
  // which captures a new terminal request.
  task automatic w1c_coincident_with_terminal;
    input [5:0] mask;
    integer timeout;
    begin
      timeout = 0;
      while ((dut.terminal_capture_axi !== 1'b1) && timeout < 256) begin
        @(negedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout >= 256) begin
        test_fail("did not observe terminal capture window");
        disable w1c_coincident_with_terminal;
      end
      s_axi_awaddr = REG_IRQ_STATUS;
      s_axi_awvalid = 1'b1;
      s_axi_wdata = {26'h0, mask};
      s_axi_wstrb = 4'b0001;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b0;
      @(posedge s_axi_aclk);
      if (!(s_axi_awready && s_axi_wready))
        test_fail("coincident W1C AXI handshake not ready");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      s_axi_wstrb = 4'h0;
      s_axi_bready = 1'b1;
      while (!s_axi_bvalid) @(posedge s_axi_aclk);
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  initial begin
    req_count = 0;
    ack_count = 0;
    req_d = 1'b0;
    ack_d = 1'b0;
    mailbox_observing = 1'b0;
    reset_dut();
    req_d = dut.terminal_req_tgl;
    ack_d = dut.terminal_ack_tgl;

    // A single-event EOF can transition FIRE->ADVANCE->DONE faster than AXI
    // samples the FIRE status toggle.  DONE and its IRQ must still be lossless.
    set_stream_mode(1'b1);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    stream_push_event(read_data64[31:0] + 32'd512,
                      read_data64[63:32],
                      32'h00000002,
                      32'h00004000, 32'h1, 32'h2, 32'h0);
    arm_scheduler();
    run_scheduler();
    wait_for_done();
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("DONE status is exact ABI packing", read_data, 32'h00000004);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("DONE ERR_REG is zero", read_data, 32'h00000000);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("DONE IRQ delivered", read_data[0], 1'b1);
    repeat (40) @(posedge sched_clk);
    expect_eq32("DONE state generated one request", req_count, 1);
    expect_eq32("DONE request acknowledged once", ack_count, 1);
    axi_write(REG_IRQ_STATUS, 32'h00000001, 4'b0001);
    repeat (6) @(posedge s_axi_aclk);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("DONE W1C remains clear", read_data[0], 1'b0);

    // A single-event preload completion takes the legacy BRAM path.  This is
    // deliberately separate from the streaming EOF case above: both terminal
    // transitions must generate exactly one transaction.
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    set_stream_mode(1'b0);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    legacy_load_event(32'd0,
                      read_data64[31:0] + 32'd1024,
                      read_data64[63:32],
                      32'h00000000,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    axi_write(REG_EVENT_COUNT, 32'd1, 4'hf);
    // W1C before capture cannot mask the subsequently arriving DONE source.
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    arm_scheduler();
    run_scheduler();
    wait_for_done();
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("preload DONE status packing", read_data, 32'h00000004);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("preload DONE ERR_REG is zero", read_data, 32'h00000000);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("preload DONE survives earlier W1C", read_data[0], 1'b1);
    repeat (32) @(posedge sched_clk);
    expect_eq32("preload DONE generated one additional request", req_count, 2);
    expect_eq32("preload DONE request acknowledged once", ack_count, 2);

    // Two ordinary preload events seven ticks apart violate the eight-tick
    // minimum without being late when the second event reaches COMPARE.
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    set_stream_mode(1'b0);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    legacy_load_event(32'd0,
                      read_data64[31:0] + 32'd512,
                      read_data64[63:32],
                      32'h00000000,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    legacy_load_event(32'd1,
                      read_data64[31:0] + 32'd519,
                      read_data64[63:32],
                      32'h00000000,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    axi_write(REG_EVENT_COUNT, 32'd2, 4'hf);
    arm_scheduler();
    run_scheduler();
    wait_for_error();
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("ordinary spacing STATUS packing", read_data, 32'h00000208);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("ordinary spacing ERR_REG mirror", read_data, 32'h00000002);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("ordinary spacing ERROR IRQ", read_data[1], 1'b1);
    expect_eq1("ordinary spacing violation IRQ", read_data[2], 1'b1);
    repeat (32) @(posedge sched_clk);
    expect_eq32("ordinary spacing generated one additional request", req_count, 3);
    expect_eq32("ordinary spacing request acknowledged once", ack_count, 3);

    // Consecutive phase-reinitialised events inside the same spacing window
    // use the distinct reinit-spacing ABI error code.
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    set_stream_mode(1'b0);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    legacy_load_event(32'd0,
                      read_data64[31:0] + 32'd512,
                      read_data64[63:32],
                      32'h00000001,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    legacy_load_event(32'd1,
                      read_data64[31:0] + 32'd519,
                      read_data64[63:32],
                      32'h00000001,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    axi_write(REG_EVENT_COUNT, 32'd2, 4'hf);
    arm_scheduler();
    run_scheduler();
    wait_for_error();
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("reinit spacing STATUS packing", read_data, 32'h00000308);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("reinit spacing ERR_REG mirror", read_data, 32'h00000003);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("reinit spacing ERROR IRQ", read_data[1], 1'b1);
    expect_eq1("reinit spacing violation IRQ", read_data[2], 1'b1);
    repeat (32) @(posedge sched_clk);
    expect_eq32("reinit spacing generated one additional request", req_count, 4);
    expect_eq32("reinit spacing request acknowledged once", ack_count, 4);

    // Exercise blind control sequencing: issue STOP and soft reset as soon as
    // the scheduler enters DONE, without first polling its public status or
    // waiting for mailbox acknowledgement.  The queued DONE transaction must
    // survive both commands and remain sticky for the subsequent re-arm.
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    set_stream_mode(1'b0);
    axi_read64(REG_TIME_NOW_LO, REG_TIME_NOW_HI, read_data64);
    legacy_load_event(32'd0,
                      read_data64[31:0] + 32'd1024,
                      read_data64[63:32],
                      32'h00000000,
                      32'h00004000, 32'h10, 32'h20, 32'h0);
    axi_write(REG_EVENT_COUNT, 32'd1, 4'hf);
    arm_scheduler();
    run_scheduler();
    // Hold the AXI domain in reset before the event becomes due.  The source
    // request will be created while its consumer is stopped.
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b0;
    while (!marker_done) @(posedge sched_clk);
    // The JESD/link reset is independent of AXI reset in the block design.
    // Assert it while the terminal request is still crossing to AXI; mailbox
    // phase and bundled payload must survive.
    @(negedge sched_clk);
    sched_reset = 1'b1;
    repeat (4) @(posedge sched_clk);
    @(negedge sched_clk);
    sched_reset = 1'b0;
    repeat (4) @(posedge sched_clk);
    repeat (4) @(posedge s_axi_aclk);
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    stop_scheduler();
    soft_reset_scheduler();
    wait_for_request_count(5);
    wait_mailbox_idle();
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("blind STOP/reset preserves queued DONE IRQ", read_data[0], 1'b1);
    repeat (32) @(posedge sched_clk);
    expect_eq32("blind command sequence retained one request", req_count, 5);
    expect_eq32("blind command sequence retained one acknowledgement", ack_count, 5);

    // Missed-deadline ERROR uses STATUS[15:8], mirrors ERR_REG, mutes output,
    // and carries both ERROR and UNDERRUN IRQ sources through the mailbox.
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    set_stream_mode(1'b1);
    stream_push_event(32'd1, 32'd0, 32'h00000002,
                      32'h00004000, 32'h0, 32'h1, 32'h0);
    arm_scheduler();
    run_scheduler();
    wait_for_error();
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("missed deadline STATUS packing", read_data, 32'h00000108);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("missed deadline ERR_REG mirror", read_data, 32'h00000001);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("missed deadline ERROR IRQ", read_data[1], 1'b1);
    expect_eq1("missed deadline UNDERRUN IRQ", read_data[3], 1'b1);
    expect_eq32("fatal timing error closes all channel gates",
                {24'h0, sched_output_valid}, 32'h0);
    repeat (32) @(posedge sched_clk);
    expect_eq32("ERROR state generated one additional request", req_count, 6);
    expect_eq32("ERROR request acknowledged once", ack_count, 6);

    // Clear old sources, then inject an extension fault while arranging a W1C
    // on the terminal-capture cycle.  The arriving IRQ must win.
    axi_write(REG_IRQ_STATUS, 32'h0000003f, 4'b0001);
    stop_scheduler();
    soft_reset_scheduler();
    repeat (20) @(posedge s_axi_aclk);
    fork
      begin
        w1c_coincident_with_terminal(6'h3f);
      end
      begin
        @(negedge sched_clk);
        extension_error_toggle_in = ~extension_error_toggle_in;
      end
    join
    wait_mailbox_idle();
    axi_read(REG_STATUS, read_data);
    expect_eq32("extension fault STATUS packing", read_data, 32'h00000408);
    axi_read(REG_ERR_REG, read_data);
    expect_eq32("extension fault ERR_REG mirror", read_data, 32'h00000004);
    axi_read(REG_IRQ_STATUS, read_data);
    expect_eq1("new ERROR IRQ wins coincident W1C", read_data[1], 1'b1);
    expect_eq32("extension fault closes all channel gates",
                {24'h0, sched_output_valid}, 32'h0);
    repeat (32) @(posedge sched_clk);
    expect_eq32("seven terminal entries generated seven requests", req_count, 7);
    expect_eq32("seven terminal requests were acknowledged", ack_count, 7);

    finish_test();
  end
endmodule
