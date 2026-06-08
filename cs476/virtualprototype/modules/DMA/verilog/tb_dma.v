`timescale 1ns/1ps

// =============================================================================
// tb_DMA.v  —  Testbench for DMA + ramDmaCi + dualPortSSRAM
//
// Test plan:
//   TC1  TO_CI  single-word transfer    (blockSize=1, burstSize=0)
//   TC2  TO_CI  exact-burst transfer    (blockSize=4, burstSize=3)
//   TC3  TO_CI  multi-burst transfer    (blockSize=6, burstSize=2)
//   TC4  TO_CI  bus error mid-transfer  (busError asserted during RECEIVE)
//   TC5  FROM_CI single-word transfer   (blockSize=1, burstSize=0)
//   TC6  FROM_CI exact-burst transfer   (blockSize=4, burstSize=3)
//   TC7  FROM_CI multi-burst transfer   (blockSize=6, burstSize=2)
//   TC8  FROM_CI busy-slave stall       (busyIn toggled during TRANSFER)
//
// Bus model (slave side):
//   - beginTransaction seen  -> after 1 cycle: grant data on addressDataIn /
//     assert dataValidIn for TO_CI; or accept dataValidOut for FROM_CI
//   - endTransaction from DMA ends the burst
// =============================================================================

module tb_DMA;

  // -------------------------------------------------------------------------
  // Clock / reset
  // -------------------------------------------------------------------------
  reg clock = 0;
  always #5 clock = ~clock;          // 100 MHz

  reg reset;

  // -------------------------------------------------------------------------
  // DMA port wires
  // -------------------------------------------------------------------------
  // bus-in
  reg  [31:0] addressDataIn;
  reg         endTransactionIn;
  reg         busErrorIn;
  reg         dataValidIn;
  reg         busyIn;
  reg         arbiterGranted;

  // CI-side inputs (driven by ramDmaCi or directly in tests)
  reg  [3:0]  paramWE;
  reg  [8:0]  memStartAddr;
  reg  [31:0] busStartAddr;
  reg  [9:0]  blockSize;
  reg  [7:0]  burstSize;
  reg  [1:0]  ctrlRegIn;
  reg         ctrlRegWE;
  wire  [31:0] memReadData;   // fed from SSRAM port B via ramDmaCi

  // DMA outputs
  wire [1:0]  statusRegOut;
  wire [8:0]  memAddr;
  wire [31:0] memWriteData;
  wire        memWE;
  wire [31:0] addressDataOut;
  wire [3:0]  byteEnablesOut;
  wire [7:0]  burstSizeOut;
  wire        dataValidOut;
  wire        endTransactionOut;
  wire        readNotWriteOut;
  wire        beginTransactionOut;
  wire        busRequest;

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  DMA dut (
    .clock             (clock),
    .reset             (reset),
    .addressDataIn     (addressDataIn),
    .endTransactionIn  (endTransactionIn),
    .busErrorIn        (busErrorIn),
    .dataValidIn       (dataValidIn),
    .busyIn            (busyIn),
    .arbiterGranted    (arbiterGranted),
    .paramWE           (paramWE),
    .memStartAddr      (memStartAddr),
    .busStartAddr      (busStartAddr),
    .blockSize         (blockSize),
    .burstSize         (burstSize),
    .ctrlRegIn         (ctrlRegIn),
    .ctrlRegWE         (ctrlRegWE),
    .memReadData       (memReadData),
    .statusRegOut      (statusRegOut),
    .memAddr           (memAddr),
    .memWriteData      (memWriteData),
    .memWE             (memWE),
    .addressDataOut    (addressDataOut),
    .byteEnablesOut    (byteEnablesOut),
    .burstSizeOut      (burstSizeOut),
    .dataValidOut      (dataValidOut),
    .endTransactionOut (endTransactionOut),
    .readNotWriteOut   (readNotWriteOut),
    .beginTransactionOut(beginTransactionOut),
    .busRequest        (busRequest)
  );

  // -------------------------------------------------------------------------
  // Scratchpad SSRAM — 512x32  (mirrors what ramDmaCi instantiates)
  // The DMA writes to port B; we read it back via port A after each TC.
  // -------------------------------------------------------------------------
  reg  [8:0]  sram_addrA;
  reg         sram_weA;
  reg  [31:0] sram_dinA;
  wire [31:0] sram_doutA;

  wire clockB_inv = ~clock;

  dualPortSSRAM #(
    .bitwidth    (32),
    .nrOfEntries (512),
    .readAfterWrite(0)
  ) ssram (
    .clockA      (clock),
    .clockB      (clockB_inv),
    .writeEnableA(sram_weA),
    .writeEnableB(memWE),
    .addressA    (sram_addrA),
    .addressB    (memAddr),
    .dataInA     (sram_dinA),
    .dataInB     (memWriteData),
    .dataOutA    (sram_doutA),
    .dataOutB    (memReadData)   // feeds back into DMA.memReadData for FROM_CI
  );

  // -------------------------------------------------------------------------
  // Test infrastructure
  // -------------------------------------------------------------------------
  integer tc_errors = 0;
  integer tc_num    = 0;

  task print_pass;
    input [127:0] name;
    begin
      $display("[PASS] TC%0d %s", tc_num, name);
    end
  endtask

  task print_fail;
    input [127:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
      $display("[FAIL] TC%0d %s  got=%0h  exp=%0h", tc_num, name, got, exp);
      tc_errors = tc_errors + 1;
    end
  endtask

  // Single-cycle pulse of ctrlRegWE to start a DMA transfer
  task start_dma;
    input [1:0] direction;   // 1=TO_CI, 2=FROM_CI
    begin
      @(negedge clock);
      ctrlRegIn  = direction;
      ctrlRegWE  = 1'b1;
      @(negedge clock);
      ctrlRegWE  = 1'b0;
      ctrlRegIn  = 2'd0;
    end
  endtask

  // Configure DMA registers via paramWE.
  // We drive them combinatorially for one cycle.
  task cfg_dma;
    input [31:0] bus_addr;
    input [8:0]  mem_addr;
    input [9:0]  blk;
    input [7:0]  bst;
    begin
      @(negedge clock);
      busStartAddr = bus_addr;
      memStartAddr = mem_addr;
      blockSize    = blk;
      burstSize    = bst;
      paramWE      = 4'b0010; @(negedge clock); // write busStartAddr
      paramWE      = 4'b0001; @(negedge clock); // write memStartAddr
      paramWE      = 4'b0100; @(negedge clock); // write blockSize
      paramWE      = 4'b1000; @(negedge clock); // write burstSize
      paramWE      = 4'b0000;
    end
  endtask

  // Wait until DMA goes idle (statusRegOut[0] == 0) with timeout
  task wait_idle;
    input integer timeout;
    integer i;
    begin
      i = 0;
      while (statusRegOut[0] === 1'b1 && i < timeout)
      begin
        @(posedge clock); #1;
        i = i + 1;
      end
      if (i >= timeout)
        $display("[WARN] TC%0d wait_idle timed out after %0d cycles", tc_num, timeout);
    end
  endtask

  // Pre-fill SSRAM via port A so FROM_CI tests have known data
  task fill_sram;
    input [8:0]  base_addr;
    input [9:0]  count;
    input [31:0] base_val;
    integer      k;
    begin
      for (k = 0; k < count; k = k + 1)
      begin
        @(negedge clock);
        sram_addrA = base_addr + k[8:0];
        sram_dinA  = base_val  + k;
        sram_weA   = 1'b1;
      end
      @(negedge clock);
      sram_weA = 1'b0;
      @(posedge clock); #1; // let write settle
    end
  endtask

  // Read one word from SSRAM port A and return it in r_read_val
  reg [31:0] r_read_val;
  task read_sram;
    input [8:0] addr;
    begin
      @(negedge clock);
      sram_addrA = addr;
      sram_weA   = 1'b0;
      @(posedge clock); #1;  // synchronous read: result on next posedge
      @(posedge clock); #1;
      r_read_val = sram_doutA;
    end
  endtask

  // =========================================================================
  // Bus slave model tasks
  // =========================================================================

  // Drive N words of data into the DMA for a TO_CI transfer.
  // Watches beginTransactionOut then pulses dataValidIn / addressDataIn.
  task bus_slave_send;
    input [9:0]  n_words;
    input [31:0] base_val;
    integer      j;
    begin
      // wait for beginTransaction (registered inside DMA so allow a few cycles)
      @(posedge beginTransactionOut); #1;
      // one idle cycle like a real bus
      @(negedge clock);
      for (j = 0; j < n_words; j = j + 1)
      begin
        addressDataIn = base_val + j;
        dataValidIn   = 1'b1;
        @(negedge clock);
      end
      dataValidIn   = 1'b0;
      addressDataIn = 32'd0;
      endTransactionIn = 1'b1;
      @(negedge clock);
      endTransactionIn = 1'b0;
    end
  endtask

  // Accept words from a FROM_CI transfer (just watch dataValidOut).
  // Stores received words in recv_buf.
  reg [31:0] recv_buf [0:511];
  integer    recv_count;

  task bus_slave_recv;
    input [9:0] n_words;
    begin
      recv_count = 0;
      @(posedge beginTransactionOut); #1;
      while (recv_count < n_words)
      begin
        @(posedge clock); #1;
        if (dataValidOut === 1'b1 && busyIn === 1'b0)
        begin
          recv_buf[recv_count] = addressDataOut;
          recv_count = recv_count + 1;
        end
        if (endTransactionOut === 1'b1)
        begin
          // if more bursts coming, re-arm
          if (recv_count < n_words)
            @(posedge beginTransactionOut); #1;
        end
      end
    end
  endtask

  // Grant bus to DMA: pulse arbiterGranted for one clock after busRequest
  task auto_grant;
    begin
      @(posedge busRequest); #1;
      @(negedge clock);
      arbiterGranted = 1'b1;
      @(negedge clock);
      arbiterGranted = 1'b0;
    end
  endtask

  // =========================================================================
  // Reset helper
  // =========================================================================
  task do_reset;
    begin
      reset            = 1'b1;
      arbiterGranted   = 1'b0;
      busErrorIn       = 1'b0;
      dataValidIn      = 1'b0;
      busyIn           = 1'b0;
      endTransactionIn = 1'b0;
      addressDataIn    = 32'd0;
      paramWE          = 4'd0;
      ctrlRegWE        = 1'b0;
      ctrlRegIn        = 2'd0;
      sram_weA         = 1'b0;
      sram_addrA       = 9'd0;
      sram_dinA        = 32'd0;
      repeat(4) @(posedge clock);
      reset = 1'b0;
      @(posedge clock); #1;
    end
  endtask

  // =========================================================================
  // TC helper: check TO_CI result by reading SSRAM port A
  // =========================================================================
  task check_to_ci;
    input [8:0]  base_mem;
    input [9:0]  count;
    input [31:0] base_val;
    integer      k;
    reg  [31:0]  exp;
    begin
      for (k = 0; k < count; k = k + 1)
      begin
        read_sram(base_mem + k[8:0]);
        exp = base_val + k;
        if (r_read_val !== exp)
          print_fail("SRAM word mismatch", r_read_val, exp);
      end
    end
  endtask

  // =========================================================================
  // MAIN TEST SEQUENCE
  // =========================================================================
  integer i;

  initial
  begin
    $dumpfile("tb_DMA.vcd");
    $dumpvars(0, tb_DMA);

    do_reset;

    // -----------------------------------------------------------------------
    // TC1 — TO_CI: single word (blockSize=1, burstSize=0)
    // -----------------------------------------------------------------------
    tc_num = 1;
    $display("--- TC%0d: TO_CI single word ---", tc_num);
    cfg_dma(32'hA000_0000, 9'd0, 10'd1, 8'd0);
    fork
      begin auto_grant; end
      begin bus_slave_send(1, 32'hDEAD_0001); end
      begin start_dma(2'd1); end
    join
    wait_idle(200);
    check_to_ci(9'd0, 10'd1, 32'hDEAD_0001);
    if (statusRegOut[1] === 1'b0) print_pass("TC1 TO_CI single word");
    else                          print_fail("TC1 bus-error flag unexpected", statusRegOut, 2'd0);

    do_reset;

    // -----------------------------------------------------------------------
    // TC2 — TO_CI: exact burst (blockSize=4, burstSize=3 → 1 burst of 4)
    // -----------------------------------------------------------------------
    tc_num = 2;
    $display("--- TC%0d: TO_CI exact burst (4 words, burst=3) ---", tc_num);
    cfg_dma(32'hB000_0000, 9'd10, 10'd4, 8'd3);
    fork
      begin auto_grant; end
      begin bus_slave_send(4, 32'hCAFE_0000); end
      begin start_dma(2'd1); end
    join
    wait_idle(200);
    check_to_ci(9'd10, 10'd4, 32'hCAFE_0000);
    if (statusRegOut[1] === 1'b0) print_pass("TC2 TO_CI exact burst");
    else                          print_fail("TC2 bus-error flag unexpected", statusRegOut, 2'd0);

    do_reset;

    // -----------------------------------------------------------------------
    // TC3 — TO_CI: multi-burst (blockSize=6, burstSize=2 → 2 bursts: 3+3)
    // -----------------------------------------------------------------------
    tc_num = 3;
    $display("--- TC%0d: TO_CI multi-burst (6 words, burst=2) ---", tc_num);
    cfg_dma(32'hC000_0000, 9'd20, 10'd6, 8'd2);
    fork
      // grant for each burst separately
      begin
        auto_grant;
        auto_grant;
      end
      begin
        // first burst: 3 words
        @(posedge beginTransactionOut); #1;
        @(negedge clock);
        for (i = 0; i < 3; i = i + 1)
        begin
          addressDataIn = 32'h1234_0000 + i;
          dataValidIn   = 1'b1;
          @(negedge clock);
        end
        dataValidIn      = 1'b0;
        endTransactionIn = 1'b1;
        @(negedge clock);
        endTransactionIn = 1'b0;
        // second burst: 3 words
        @(posedge beginTransactionOut); #1;
        @(negedge clock);
        for (i = 0; i < 3; i = i + 1)
        begin
          addressDataIn = 32'h1234_0003 + i;
          dataValidIn   = 1'b1;
          @(negedge clock);
        end
        dataValidIn      = 1'b0;
        endTransactionIn = 1'b1;
        @(negedge clock);
        endTransactionIn = 1'b0;
      end
      begin start_dma(2'd1); end
    join
    wait_idle(400);
    check_to_ci(9'd20, 10'd6, 32'h1234_0000);
    if (statusRegOut[1] === 1'b0) print_pass("TC3 TO_CI multi-burst");
    else                          print_fail("TC3 bus-error flag unexpected", statusRegOut, 2'd0);

    do_reset;

    // -----------------------------------------------------------------------
    // TC4 — TO_CI: bus error mid-transfer
    // -----------------------------------------------------------------------
    tc_num = 4;
    $display("--- TC%0d: TO_CI bus error ---", tc_num);
    cfg_dma(32'hD000_0000, 9'd50, 10'd4, 8'd3);
    fork
      begin auto_grant; end
      begin
        @(posedge beginTransactionOut); #1;
        @(negedge clock);
        // deliver only 1 word then raise busError
        addressDataIn = 32'hBAD0_0001;
        dataValidIn   = 1'b1;
        @(negedge clock);
        dataValidIn  = 1'b0;
        busErrorIn   = 1'b1;
        @(negedge clock);
        busErrorIn   = 1'b0;
      end
      begin start_dma(2'd1); end
    join
    wait_idle(200);
    if (statusRegOut[1] === 1'b1) print_pass("TC4 TO_CI bus-error flag set");
    else                          print_fail("TC4 bus-error flag missing", statusRegOut, 2'd2);
    if (statusRegOut[0] === 1'b0) print_pass("TC4 DMA returned to IDLE");
    else                          print_fail("TC4 DMA still busy", statusRegOut, 2'd0);

    do_reset;

    // -----------------------------------------------------------------------
    // TC5 — FROM_CI: single word (blockSize=1, burstSize=0)
    // -----------------------------------------------------------------------
    tc_num = 5;
    $display("--- TC%0d: FROM_CI single word ---", tc_num);
    fill_sram(9'd100, 10'd1, 32'hABCD_0001);
    cfg_dma(32'hE000_0000, 9'd100, 10'd1, 8'd0);
    fork
      begin auto_grant; end
      begin bus_slave_recv(1); end
      begin start_dma(2'd2); end
    join
    wait_idle(200);
    if (recv_buf[0] === 32'hABCD_0001)
      print_pass("TC5 FROM_CI single word data");
    else
      print_fail("TC5 FROM_CI wrong data", recv_buf[0], 32'hABCD_0001);

    do_reset;

    // -----------------------------------------------------------------------
    // TC6 — FROM_CI: exact burst (blockSize=4, burstSize=3)
    // -----------------------------------------------------------------------
    tc_num = 6;
    $display("--- TC%0d: FROM_CI exact burst (4 words, burst=3) ---", tc_num);
    fill_sram(9'd200, 10'd4, 32'h5A5A_0000);
    cfg_dma(32'hF000_0000, 9'd200, 10'd4, 8'd3);
    fork
      begin auto_grant; end
      begin bus_slave_recv(4); end
      begin start_dma(2'd2); end
    join
    wait_idle(200);
    begin : tc6_check
      integer k6;
      for (k6 = 0; k6 < 4; k6 = k6 + 1)
      begin
        if (recv_buf[k6] !== 32'h5A5A_0000 + k6)
          print_fail("TC6 FROM_CI word mismatch", recv_buf[k6], 32'h5A5A_0000 + k6);
      end
      if (statusRegOut[1] === 1'b0) print_pass("TC6 FROM_CI exact burst");
    end

    do_reset;

    // -----------------------------------------------------------------------
    // TC7 — FROM_CI: multi-burst (blockSize=6, burstSize=2 → 2 bursts: 3+3)
    // -----------------------------------------------------------------------
    tc_num = 7;
    $display("--- TC%0d: FROM_CI multi-burst (6 words, burst=2) ---", tc_num);
    fill_sram(9'd0, 10'd6, 32'h9900_0000);
    cfg_dma(32'h1000_0000, 9'd0, 10'd6, 8'd2);
    fork
      begin
        auto_grant;
        auto_grant;
      end
      begin bus_slave_recv(6); end
      begin start_dma(2'd2); end
    join
    wait_idle(400);
    begin : tc7_check
      integer k7;
      for (k7 = 0; k7 < 6; k7 = k7 + 1)
      begin
        if (recv_buf[k7] !== 32'h9900_0000 + k7)
          print_fail("TC7 FROM_CI word mismatch", recv_buf[k7], 32'h9900_0000 + k7);
      end
      if (statusRegOut[1] === 1'b0) print_pass("TC7 FROM_CI multi-burst");
    end

    do_reset;

    // -----------------------------------------------------------------------
    // TC8 — FROM_CI: busy-slave stall (busyIn toggled mid-burst)
    // -----------------------------------------------------------------------
    tc_num = 8;
    $display("--- TC%0d: FROM_CI busy-slave stall ---", tc_num);
    fill_sram(9'd50, 10'd3, 32'hFEED_0000);
    cfg_dma(32'h2000_0000, 9'd50, 10'd3, 8'd2);
    fork
      begin auto_grant; end
      begin
        // accept words but insert a busy stall after first word
        recv_count = 0;
        @(posedge beginTransactionOut); #1;
        @(posedge clock); #1;
        // word 0 accepted
        recv_buf[recv_count] = addressDataOut;
        recv_count = recv_count + 1;
        // stall for 3 cycles
        busyIn = 1'b1;
        repeat(3) @(posedge clock);
        busyIn = 1'b0;
        // collect remaining 2 words
        while (recv_count < 2)
        begin
          //$display("loop %0d",recv_count);
          @(posedge clock); #1;
          if (dataValidOut === 1'b1 && busyIn === 1'b0)
          begin
            recv_buf[recv_count] = addressDataOut;
            recv_count = recv_count + 1;
          end
        end
      end
      begin start_dma(2'd2); end
    join
    wait_idle(300);
    begin : tc8_check
      integer k8;
      for (k8 = 0; k8 < 3; k8 = k8 + 1)
      begin
        if (recv_buf[k8] !== 32'hFEED_0000 + k8)
          print_fail("TC8 busy-stall word mismatch", recv_buf[k8], 32'hFEED_0000 + k8);
      end
      if (statusRegOut[1] === 1'b0) print_pass("TC8 FROM_CI busy stall");
    end

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("=========================================");
    if (tc_errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", tc_errors);
    $display("=========================================");

    $finish;
  end

  // Safety watchdog — kill sim if it hangs
  initial
  begin
    #500000;
    $display("[ERROR] Simulation watchdog timeout");
    $finish;
  end

endmodule