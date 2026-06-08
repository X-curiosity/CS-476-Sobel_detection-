module dualPortSSRAM #(
  parameter bitwidth = 32,
  parameter nrOfEntries = 512,
  parameter readAfterWrite=0
)(
  input wire clockA, clockB,
  input wire writeEnableA, writeEnableB,
  input wire [$clog2(nrOfEntries)-1:0] addressA, addressB,
  input wire [bitwidth-1:0] dataInA, dataInB,
  output reg [bitwidth-1:0] dataOutA, dataOutB
);

  reg [bitwidth-1:0] memoryContent [0:nrOfEntries-1];

  // Port A
  always @(posedge clockA) begin
    if (writeEnableA)
      memoryContent[addressA] <= dataInA;

    dataOutA <= memoryContent[addressA];
  end

  // Port B
  always @(posedge clockB) begin
    if (writeEnableB)
      memoryContent[addressB] <= dataInB;

    dataOutB <= memoryContent[addressB];
  end

endmodule