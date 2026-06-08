/* set the time-units for simulation */
`timescale 1ps/1ps

module ramDmaCi_tb;

  reg reset, clock;

  initial
  begin
    reset = 1'b1;
    clock = 1'b0;
    repeat (4) #5 clock = ~clock; /* generate 2 clock periods */
    reset = 1'b0;
    forever
      #5 clock = ~clock; /* 10 time-unit period */
  end

  /* DUT signals */
  reg s_start;
  reg [31:0] s_valueA, s_valueB;
  reg [7:0] s_ciN;

  wire s_done;
  wire [31:0] s_result;

  /* Instantiate DUT */
  ramDmaCi #(.customId(8'hAA)) DUT (
    .clock(clock),
    .reset(reset),
    .start(s_start),
    .valueA(s_valueA),
    .valueB(s_valueB),
    .ciN(s_ciN),
    .done(s_done),
    .result(s_result)
  );

  /* Dump waves */
  initial
  begin
    $dumpfile("ramDmaCi.vcd");
    $dumpvars(1, DUT);
  end

  /* Stimulus */
  initial
  begin
    s_start  = 0;
    s_valueA = 0;
    s_valueB = 0;
    s_ciN    = 0;

    @(negedge reset);
    repeat(2) @(negedge clock);

    /* ----------------------------- */
    /* TEST 1: Wrong instruction ID */
    /* ----------------------------- */
    s_ciN   = 8'h55;  // wrong ID
    s_start = 1;
    s_valueA = {22'b0, 1'b1, 9'd5};
    s_valueB = 32'h12345678;
    @(negedge clock);
    s_start = 0;

    repeat(2) @(negedge clock);

    /* ----------------------------- */
    /* TEST 2: WRITE to address 5 */
    /* ----------------------------- */
    s_ciN   = 8'hAA;
    s_start = 1;
    s_valueA = {22'b0, 1'b1, 9'd5}; // write enable = bit 9
    s_valueB = 32'hDEADBEEF;
    @(negedge clock);
    s_start = 0;

    wait(s_done);
    @(negedge clock);

    /* ----------------------------- */
    /* TEST 3: WRITE to address 10 */
    /* ----------------------------- */
    s_start = 1;
    s_valueA = {22'b0, 1'b1, 9'd10};
    s_valueB = 32'hCAFEBABE;
    @(negedge clock);
    s_start = 0;

    wait(s_done);
    @(negedge clock);

    /* ----------------------------- */
    /* TEST 4: READ address 5 */
    /* ----------------------------- */
    s_start = 1;
    s_valueA = {22'b0, 1'b0, 9'd5}; // read
    @(negedge clock);
    s_start = 0;

    wait(s_done);
    $display("READ addr 5: %h", s_result);
    @(negedge clock);

    /* ----------------------------- */
    /* TEST 5: READ address 10 */
    /* ----------------------------- */
    s_start = 1;
    s_valueA = {22'b0, 1'b0, 9'd10};
    @(negedge clock);
    s_start = 0;

    wait(s_done);
    $display("READ addr 10: %h", s_result);
    @(negedge clock);

    /* ----------------------------- */
    /* TEST 6: INVALID ADDRESS (upper bits != 0) */
    /* ----------------------------- */
    s_start = 1;
    s_valueA = 32'hFFFF_FFFF; // invalid per spec
    @(negedge clock);
    s_start = 0;

    repeat(3) @(negedge clock);

    /* ----------------------------- */
    /* TEST 7: BACK-TO-BACK READ */
    /* ----------------------------- */
    s_start = 1;
    s_valueA = {22'b0, 1'b0, 9'd5};
    @(negedge clock);
    s_start = 0;

    wait(s_done);
    $display("READ again addr 5: %h", s_result);

    repeat(3) @(negedge clock);

    $finish;
  end

endmodule