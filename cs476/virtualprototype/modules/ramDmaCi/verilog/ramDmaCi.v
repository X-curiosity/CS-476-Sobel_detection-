module ramDmaCi #(
    parameter [7:0] customId = 8'h00
)(
    input  wire        start,
    input  wire        clock,
    input  wire        reset,
    input  wire [31:0] valueA,
    input  wire [31:0] valueB,
    input  wire [7:0]  ciN,
    output reg         done,
    output reg  [31:0] result,



    // -----------------------------

    //outputs to DMA controller

    // -----------------------------

    
    output wire [3:0] paramWE, // first bit to write memStart addr, 2nd for busStartAddr, etc..
    output wire [9:0] memStartAddr,
    output wire [31:0] busStartAddr,
    output wire [9:0] blockSize,
    output wire [7:0] burstSize,
    output wire [1:0] ctrlRegOut,
    output wire ctrlRegWE,
    output wire [31:0] memReadData,

    // -----------------------------

    //inputs from DMA controller

    // -----------------------------
    input wire [1:0] statusRegIn,
    input wire [9:0] memAddr,
    input wire [31:0] memWriteData,
    input wire memWE


);
   // ############################
   // PORT A Variables 
  // ############################

    reg        mem_we_a;
    reg  [9:0] mem_addr_a;
    wire [31:0] mem_dout_a;

    // ############################
   // PORT B Variables 
  // ############################
  // -----------------------------

    //reg        mem_we_b;
    //reg  [8:0] mem_addr_b;
    //reg [31:0] mem_din_b;
    //wire [31:0] mem_dout_b; 


    //DMA interface registers
    reg [3:0] r_paramWE;
    reg [9:0] r_memStartAddr;
    reg [31:0] r_busStartAddr;
    reg [9:0] r_blockSize;
    reg [7:0] r_burstSize;
    reg [1:0] r_ctrlRegOut;
    reg r_ctrlRegWE;

    assign paramWE= r_paramWE;
    assign memStartAddr=r_memStartAddr;
    assign busStartAddr=r_busStartAddr;
    assign blockSize=r_blockSize;
    assign burstSize=r_burstSize;
    assign ctrlRegOut=r_ctrlRegOut;
    assign ctrlRegWE=r_ctrlRegWE;

    reg [1:0] read_state; //reg to delay read 

    wire clockB_inv = ~clock; // to clock port b of ssram on negedge
    dualPortSSRAM #(
        .bitwidth(32),
        .nrOfEntries(1024),
        .readAfterWrite(0)
    ) mem (
        .clockA(clock),
        .clockB(clockB_inv),
        .writeEnableA(mem_we_a),
        .writeEnableB(memWE), //straight from DMA controller
        .addressA(mem_addr_a),
        .addressB(memAddr), //straight from DMA controller
        .dataInA(valueB),
        .dataInB(memWriteData), //straight from DMA controller
        .dataOutA(mem_dout_a),
        .dataOutB(memReadData) //straight to DMA controller
    );

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            done       <= 1'b0;
            result     <= 32'd0;
            mem_we_a   <= 1'b0;
            mem_addr_a <= 9'd0;
            read_state <= 1'd0;
        end else begin
            done     <= 1'b0;
            result   <= 32'd0;
            mem_we_a <= 1'b0;
            r_paramWE<=4'b0;
            r_ctrlRegWE<=1'b0;

            if (read_state==2'd1)
            begin
                read_state<=2'd2;
            end
            if (read_state==2'd2)
            begin
                result     <= mem_dout_a;
                done       <= 1'b1;
                read_state <= 1'b0;
            end
                

            if (start && (ciN == customId)&& (valueA[31:14] == 21'd0)) begin //verify if Ci format correct
                case (valueA[13:11] )
                    3'b000: //read or write to memory (PORT A)
                    begin
                        mem_addr_a <= valueA[9:0];
                        if (valueA[10]) begin
                            mem_we_a <= 1'b1;
                            done     <= 1'b1;
                        end else begin
                            read_state <= 1'b1;
                        end
                    end

                    3'b001: // read or write bus start addr
                    begin
                        if (valueA[10]) begin
                            r_busStartAddr<=valueB;
                            r_paramWE<=4'b0010;
                            done<=1'b1;
                        end else begin
                            result<=r_busStartAddr;
                            done<=1'b1;
                        end
                    end

                    3'b010: //read or write mem start addr
                    begin
                        if (valueA[10]) begin
                            r_memStartAddr<=valueB[9:0];
                            r_paramWE<=4'b0001;
                            done<=1'b1;
                        end else begin
                            result[9:0]<=r_memStartAddr;
                            done<=1'b1;
                        end
                    end

                    3'b011: //read or write block size
                    begin
                        if (valueA[10]) begin
                            r_blockSize<=valueB[9:0];
                            r_paramWE<=4'b0100;
                            done<=1'b1;
                        end else begin
                            result[9:0]<=r_blockSize;
                            done<=1'b1;
                        end
                    end

                    3'b100: //read or write burst size
                    begin
                        if (valueA[10]) begin
                            r_burstSize<=valueB[7:0];
                            r_paramWE<=4'b1000;
                            done<=1'b1;
                        end else begin
                            result[7:0]<=r_burstSize;
                            done<=1'b1;
                        end
                    end

                    3'b101: //read sreg or write creg
                    begin
                        if (valueA[10]) begin
                            r_ctrlRegOut<=valueB[1:0];
                            r_ctrlRegWE<=1'b1;
                            done<=1'b1;
                        end else begin
                            result[1:0]<=statusRegIn;
                            done<=1'b1;
                        end
                        
                    end

                endcase

                
            end
        end
    end

    

endmodule