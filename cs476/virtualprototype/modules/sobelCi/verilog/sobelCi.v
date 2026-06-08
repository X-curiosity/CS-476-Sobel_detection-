module sobelCi #(parameter [7:0] customId = 8'd0 )
  ( input wire         start,
    input wire [31:0]  valueA,
    valueB,
    input wire [7:0]   iseId,
    output wire        done,
    output wire [31:0] result );

  wire [7:0] p0 = valueA[7:0];
  wire [7:0] p1 = valueA[15:8];
  wire [7:0] p2 = valueA[23:16];
  wire [7:0] p3 = valueA[31:24];

  wire [7:0] p5 = valueB[7:0];
  wire [7:0] p6 = valueB[15:8];
  wire [7:0] p7 = valueB[23:16];
  wire [7:0] p8 = valueB[31:24];

  wire signed [10:0] gx =
       -$signed({1'b0,p0})
       +$signed({1'b0,p2})
       -($signed({1'b0,p3}) <<< 1)
       +($signed({1'b0,p5}) <<< 1)
       -$signed({1'b0,p6})
       +$signed({1'b0,p8});

  wire signed [10:0] gy =
       $signed({1'b0,p0})
       +($signed({1'b0,p1}) <<< 1)
       + $signed({1'b0,p2})
       - $signed({1'b0,p6})
       -($signed({1'b0,p7}) <<< 1)
       - $signed({1'b0,p8});

  wire [10:0] abs_gx = gx[10] ? -gx : gx;
  wire [10:0] abs_gy = gy[10] ? -gy : gy;

  wire [11:0] mag = abs_gx + abs_gy;
  wire [7:0] sobel =
       (mag > 12'd255) ? 8'd255 : mag[7:0];


  wire s_isMyIse = (iseId == customId) ? start : 1'b0;


  assign done   = s_isMyIse;
  assign result = (s_isMyIse == 1'b1) ? {24'd0 , sobel} : 32'd0;
endmodule
