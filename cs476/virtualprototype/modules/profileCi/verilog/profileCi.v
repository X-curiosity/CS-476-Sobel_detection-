module profileCi #(
    parameter [7:0] customId = 8'h00
  ) (
    input wire start,clock,reset,stall,busIdle,
    input wire [31:0] valueA,valueB,
    input wire [7:0] ciN,
    output wire done,
    output wire [31:0] result
  );

  wire [31:0] count0,count1,count2,count3;
  reg en0,en1,en2,en3;
  reg res0,res1,res2,res3;

  wire act1,act2;
  assign done=(start == 1'b1 && ciN == customId); /* single cycle instr*/ 

  /* activate counters 1 and 2 only if stall/idle signals l */
  assign act1= en1 & stall;
  assign act2=en2 & busIdle;

  /*output result only if the correct instruction*/
  assign result = (ciN!=customId || start==1'd0)? 32'd0:
                    (valueA[1:0]==2'd0)? count0:
                    (valueA[1:0]==2'd1)? count1:
                    (valueA[1:0]==2'd2)? count2:
                    (valueA[1:0]==2'd3)? count3:
                    32'd0;



  counter #(
            .WIDTH(32)
          ) Counter0 (
            .reset(res0),
            .clock(clock),
            .enable(en0),
            .direction(1'b1),
            .counterValue(count0)
          );

  counter #(
            .WIDTH(32)
          ) Counter1 (
            .reset(res1),
            .clock(clock),
            .enable(act1),
            .direction(1'b1),
            .counterValue(count1)
          );

  counter #(
            .WIDTH(32)
          ) Counter2 (
            .reset(res2),
            .clock(clock),
            .enable(act2),
            .direction(1'b1),
            .counterValue(count2)
          );

  counter #(
            .WIDTH(32)
          ) Counter3 (
            .reset(res3),
            .clock(clock),
            .enable(en3),
            .direction(1'b1),
            .counterValue(count3)
          );


  always @(posedge clock)
  begin
    if(reset==1'b1) begin
        en0 <= 1'b0;
        en1 <= 1'b0;
        en2 <= 1'b0;
        en3 <= 1'b0;

        res0 <= 1'b1;
        res1 <= 1'b1;
        res2 <= 1'b1;
        res3 <= 1'b1;
    end

    if  (start == 1'b1 && ciN == customId) begin
        /* enabling counters*/
        if (valueB[0]==1'b1)
            en0<=1'b1;
        if (valueB[1]==1'b1)
            en1<=1'b1;
        if (valueB[2]==1'b1)
            en2<=1'b1;
        if (valueB[3]==1'b1)
            en3<=1'b1;
        
        /* disabling counters*/
        if (valueB[4]==1'b1)
            en0<=1'b0;
        if (valueB[5]==1'b1)
            en1<=1'b0;
        if (valueB[6]==1'b1)
            en2<=1'b0;
        if (valueB[7]==1'b1)
            en3<=1'b0;

        /* resetting counters*/
        if (valueB[8]==1'b1)
            res0<=1'b1;
        else
            res0<=1'b0;

        if (valueB[9]==1'b1)
            res1<=1'b1;
        else
            res1<=1'b0;

        if (valueB[10]==1'b1)
            res2<=1'b1;
        else
            res2<=1'b0;

        if (valueB[11]==1'b1)
            res3<=1'b1;
        else
            res3<=1'b0;

          

    end


  end

endmodule
