module DMA (
    //general inputs
    input wire clock, reset,

    //bus interface inputs
    input wire[31:0] addressDataIn,
    input wire endTransactionIn, busErrorIn, dataValidIn,busyIn,arbiterGranted,

    //SSRAM Ci inputs
    input wire [3:0] paramWE, // first bit to write memStart addr, 2nd for busStartAddr, etc..
    input wire [9:0] memStartAddr,
    input wire [31:0] busStartAddr,
    input wire [9:0] blockSize,
    input wire [7:0] burstSize,
    input wire [1:0] ctrlRegIn,
    input wire ctrlRegWE,
    input wire [31:0] memReadData,

    //SSRAM Ci outputs
    output wire [1:0] statusRegOut,
    output wire [9:0] memAddr,
    output wire [31:0] memWriteData,
    output wire memWE,

    //bus interface outputs
    output wire[31:0] addressDataOut,
    output wire [3:0] byteEnablesOut,
    output wire[7:0] burstSizeOut,
    output wire dataValidOut,endTransactionOut, readNotWriteOut,beginTransactionOut,busRequest

  );

  //GENERAL DMA STATES
  localparam IDLE  = 2'b00;
  localparam FROM_CI = 2'b01;
  localparam TO_CI   = 2'b10;
  //localparam ERROR  = 2'b11;

  reg [1:0] DMAstate;

  //BUS TRANSFER SPECIFIC STATES
  localparam WAITING_ACCESS = 2'b00;
  localparam ADDRESS = 2'b01;
  localparam TRANSFER = 2'b10;
  localparam RECEIVE = 2'b11;
  reg [1:0] busTranferState;

  //DATA TRANSFER COUNTERS
  reg [9:0] remaining_words;
  reg [31:0] curr_bus_addr;
  reg [9:0] curr_mem_addr;
  reg [7:0] burst_counter;

  //ssram flip flops
  reg [31:0] r_memWriteData;
  reg r_memWE;

  reg [9:0] mem_addr_write; // delayed register for negative edge clocking
  assign memAddr=mem_addr_write;

  assign memWriteData=r_memWriteData;
  assign memWE=r_memWE;

  //control reg / status reg flip flop:
  reg [1:0] r_ctrlReg;
  reg [1:0] r_statusReg;
  assign statusRegOut = r_statusReg;

  //transaction parameter flip flops
  reg [9:0] r_memStartAddr;
  reg [31:0] r_busStartAddr;
  reg [9:0] r_blockSize;
  reg [7:0] r_burstSize;

  //////// flip flops for bus crit_path reduction ///////////////
  reg [31:0] r_addressDataIn,r_addressDataOut;
  reg [3:0] r_byteEnablesOut;
  reg[7:0] r_burstSizeOut;
  reg r_dataValidOut,r_endTransactionOut, r_readNotWriteOut,r_beginTransactionOut,r_endTransactionIn,
      r_busErrorIn, r_dataValidIn,r_busyIn,r_arbiterGranted,r_busRequest;

  assign addressDataOut= r_addressDataOut;
  assign byteEnablesOut= r_byteEnablesOut;
  assign burstSizeOut=r_burstSizeOut;
  assign dataValidOut= r_dataValidOut;
  assign endTransactionOut =r_endTransactionOut;
  assign readNotWriteOut = r_readNotWriteOut;
  assign beginTransactionOut= r_beginTransactionOut;
  assign busRequest=r_busRequest;
  always @(posedge clock )
  begin
    r_addressDataIn<= addressDataIn ;
    r_endTransactionIn<= endTransactionIn;
    r_busErrorIn<=busErrorIn;
    r_dataValidIn<=dataValidIn;
    r_busyIn<=busyIn;
    r_arbiterGranted<=arbiterGranted;
  end


  /////////// STATE MANAGEMENT //////
  always @(posedge clock or posedge reset)
  begin
    //base state of bus transfer registers
    r_addressDataOut<=31'd0;
    r_byteEnablesOut<=4'd0;
    r_burstSizeOut<=8'd0;
    r_readNotWriteOut<=1'd0;
    r_beginTransactionOut<=1'd0;
    r_endTransactionOut<=1'd0;
    r_dataValidOut<=1'd0;


    r_memWE<=1'd0;

    if (reset)
    begin
      DMAstate <= IDLE;
      r_statusReg <= 0;
      // handle other regs
      r_busRequest<=1'b0;
    end
    else
    begin

      // IDLE => WAIT AND LOOK FOR START TRANSACTION INSTRUCTION
      if (DMAstate==IDLE)
      begin

        // update control reg if needed
        if (ctrlRegWE==1'b1)
        begin
          r_ctrlReg<=ctrlRegIn;
          if (ctrlRegIn==2'd1)
          begin
            DMAstate<=TO_CI;
            r_statusReg[0]<=1'd1;
            busTranferState<=WAITING_ACCESS;
            remaining_words<=r_blockSize;
            curr_bus_addr<=r_busStartAddr;
            curr_mem_addr<=r_memStartAddr;
            r_ctrlReg<=2'd0; //reset CR
            //burst_counter<=r_burstSize;


          end
          else if (ctrlRegIn==2'd2)
          begin
            DMAstate<=FROM_CI;
            r_statusReg[0]<=1'd1;
            busTranferState<=WAITING_ACCESS;
            remaining_words<=r_blockSize;
            curr_bus_addr<=r_busStartAddr;
            curr_mem_addr<=r_memStartAddr;
            r_ctrlReg<=2'd0;
          end
        end

        case (paramWE) //one-hot encoding, (could be more opti but good for clarity)
          4'b0001 :
            r_memStartAddr<=memStartAddr;
          4'b0010:
            r_busStartAddr<=busStartAddr;
          4'b0100:
            r_blockSize<= blockSize;
          4'b1000:
            r_burstSize<=burstSize;
        endcase

      end
      // from Ci mem => for each burst: request bus then read data from mem, wrtie data to bus + increment addrs
      else if  (DMAstate==FROM_CI)
      begin

        if (busTranferState==WAITING_ACCESS)
        begin
          if (remaining_words!=10'd0)
          begin
            r_busRequest<=1'b1;
            if (r_arbiterGranted==1'd1)
            begin
              //busTranferState<=ADDRESS;
              busTranferState<=TRANSFER;
              r_busRequest<=1'b0;

              if (remaining_words<=r_burstSize+1)
              begin
                burst_counter<=remaining_words;
                r_burstSizeOut<=remaining_words-1;
              end
              else
              begin
                burst_counter<=r_burstSize+1;
                r_burstSizeOut<=r_burstSize;
              end


              r_addressDataOut<=curr_bus_addr;
              r_byteEnablesOut<=4'b1111;

              r_readNotWriteOut<=1'd0;
              r_beginTransactionOut<=1'd1;
              busTranferState<=TRANSFER;

            end
          end
          else
          begin
            DMAstate<=IDLE;
            r_statusReg[0]<=1'd0;
          end
        end
        /*
        else if (busTranferState==ADDRESS) begin
          r_addressDataOut<=curr_bus_addr;
          r_byteEnablesOut<=4'b1111;
          r_burstSizeOut<=burst_counter-1;
          r_readNotWriteOut<=1'd0;
          r_beginTransactionOut<=1'd1;
          busTranferState<=TRANSFER;
        end
        */
        else if (busTranferState == TRANSFER)
        begin
          r_dataValidOut <= 1;
          //swap to big endian for the bus
          r_addressDataOut<={memReadData[7:0], memReadData[15:8], memReadData[23:16], memReadData[31:24]};
          //r_addressDataOut<=32'hffff;

          // if slave not busy, increment addr, fetch next datum and update counters
          if (burst_counter != 0 && busyIn == 0) //have to use non_registered version otherwise update lag and breaks
          begin
            mem_addr_write<=curr_mem_addr;
            curr_mem_addr <=curr_mem_addr+1;
            curr_bus_addr <= curr_bus_addr+4;
            burst_counter <= burst_counter-1;
            remaining_words <= remaining_words-1;
          end
          if (burst_counter == 0 && busyIn == 0)
          begin
            r_dataValidOut <= 0;
            r_endTransactionOut <= 1;
            busTranferState <= WAITING_ACCESS;
          end
        end




      end
      // to Ci mem => for each burst: request bus then read data from bus, write to mem + increment addrs
      else if (DMAstate==TO_CI)
      begin
        if (remaining_words!=10'd0)
        begin
          if (busTranferState==WAITING_ACCESS)
          begin
            r_busRequest<=1'b1;

            if (r_arbiterGranted==1'd1)
            begin
              //busTranferState<=ADDRESS;
              busTranferState<=RECEIVE;
              r_busRequest<=1'b0;

              if (remaining_words<=r_burstSize+1)
              begin
                burst_counter<=remaining_words;
                r_burstSizeOut<=remaining_words-1;
              end
              else
              begin
                burst_counter<=r_burstSize+1;
                r_burstSizeOut<=remaining_words-1;
              end

              r_addressDataOut<=curr_bus_addr;
              r_byteEnablesOut<=4'b1111;

              r_readNotWriteOut<=1'd1;
              r_beginTransactionOut<=1'd1;
            end
          end
          /*
          else if (busTranferState==ADDRESS)
          begin
            r_addressDataOut<=curr_bus_addr;
            r_byteEnablesOut<=4'b1111;
            r_burstSizeOut<=burst_counter-1;
            r_readNotWriteOut<=1'd1;
            r_beginTransactionOut<=1'd1;
            busTranferState<=RECEIVE;
          end
          */
          else if (busTranferState==RECEIVE)
          begin
            if (r_dataValidIn==1'd1)
            begin
              //WRITE DATA TO ssram
              r_memWE<=1'd1;
              //swap to little endian for Ci memory
              r_memWriteData<={r_addressDataIn[7:0], r_addressDataIn[15:8], r_addressDataIn[23:16], r_addressDataIn[31:24]};
              //r_memWriteData<=32'hffff;
              //update counters
              mem_addr_write<=curr_mem_addr; //"latch" memory address for negedge
              curr_mem_addr<=curr_mem_addr+1; //word aligned addr
              curr_bus_addr<=curr_bus_addr+4; //byte aligned addrs
              burst_counter<=burst_counter-1;
              remaining_words<=remaining_words-1;
            end
            if (r_endTransactionIn==1'd1)
            begin
              busTranferState<=WAITING_ACCESS;
            end
            if (r_busErrorIn==1'd1)
            begin
              r_endTransactionOut<=1'd1;
              DMAstate<=IDLE;
              r_statusReg<=2'b10;
            end


          end

        end
        else
        begin
          DMAstate<=IDLE;
          r_statusReg[0]<=1'd0;
        end
      end
    end
  end

endmodule
