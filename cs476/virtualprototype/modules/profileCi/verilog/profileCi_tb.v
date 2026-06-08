/* set the time-units for simulation */
`timescale 1ps/1ps

module profileCi_tb;

  reg reset, clock;
  initial
  begin
    reset = 1'b1;
    clock = 1'b0;                 /* set the initial values */
    repeat (4) #5 clock = ~clock; /* generate 2 clock periods */
    reset = 1'b0;                 /* de-activate the reset */
    forever
      #5 clock = ~clock;    /* generate a clock with a period of 10 time-units */
  end

  /* define the signals for the DUT */
  reg s_start, s_stall,s_busIdle;
  reg [31:0] s_valueA,s_valueB;
  reg [7:0] s_ciN;

  wire s_done;
  wire [31:0] s_result;


  profileCi #(.customId(8'd1)) /* instantiate the DUT as component */
            DUT (
              .clock(clock),
              .reset(reset),
              .start(s_start),
              .stall(s_stall),
              .busIdle(s_busIdle),
              .valueA(s_valueA),
              .valueB(s_valueB),
              .ciN(s_ciN),
              .done(s_done),
              .result(s_result)

            );

  initial
  begin
    $dumpfile("profileCi_tb.vcd"); /* define the name of the .vcd file that can be viewed by GTKWAVE */
    $dumpvars(1,DUT);             /* dump all signals inside the DUT-component in the .vcd file */
  end

  initial
  begin
    s_start=1'd0;
    s_stall=1'd0;
    s_busIdle=1'd0;
    s_valueA=32'd0;
    s_valueB=32'd0;
    s_ciN=8'd0;
    @(negedge reset);            /* wait for the reset period to end */
    repeat(2) @(negedge clock);  /* wait for 2 clock cycles */
    

    /* TEST WRONG INSTRUCTION NUM */
    s_ciN=8'd12;
    s_start=1'd1;
    s_valueB=32'd1;
    @(negedge clock);
    s_start=1'd0;

    /* TEST NO START SIGNAL */
    @(negedge clock);
    s_ciN=8'd1;

    /* ACTIVATE C0*/
    @(negedge clock);
    s_start=1;
    @(negedge clock);
    s_start=0;
    s_ciN=8'd0;

    repeat(3) @(negedge clock);
    /* ACTIVATE C1 + GENERATE STALL CYCLES*/
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'b10;
    @(negedge clock)
    s_start=1'd0;

    repeat(4) @(negedge clock) s_stall= !s_stall;
    @   (negedge clock);
    s_stall=1'd0;

    /* ACTIVATE C2 + GENERATE IDLE CYCLES*/
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'b100;
    @(negedge clock)
    s_start=1'd0;

    repeat(4) @(negedge clock) s_busIdle= !s_busIdle;
    @(negedge clock);
    s_busIdle=1'd0;
    
    /* ACTIVATE C3 */
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'b1000;
    @(negedge clock)
    s_start=1'd0;
    repeat(2) @(negedge clock);

    /* DEACTIVATE ALL COUNTERS */
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'b11110000;

    /* GENERATE STALL+IDLE CYCLE TO BE SURE THEY DONT INCREMENT*/
    @(negedge clock);
    s_stall=1'd0;
    s_busIdle=1'd0;
    
    repeat(2) @(negedge clock);

    /* READ COUNTER VALUES*/
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'd0;
    s_valueA=32'd1;

    @(negedge clock);
    s_valueA=32'd2;

    @(negedge clock);
    s_valueA=32'd3;



    /* RESET COUNTERS */
    @(negedge clock);
    s_ciN=8'd1;
    s_start=1'd1;
    s_valueB=32'b111100000000;

    repeat(2) @(negedge clock);




    $finish;                     /* finish the simulation */
  end

endmodule

