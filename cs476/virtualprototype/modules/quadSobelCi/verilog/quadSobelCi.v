module quadSobelCi
#(
    parameter [7:0] customId = 8'd0
)
(
    input  wire        clk,
    input  wire        start,
    input  wire [31:0] valueA,
    input  wire [31:0] valueB,
    input  wire [7:0]  iseId,

    output wire        done,
    output wire [31:0] result
);

    //------------------------------------------------------------
    // 3x6 sliding buffer
    //------------------------------------------------------------

    reg [7:0] row0 [0:5];
    reg [7:0] row1 [0:5];
    reg [7:0] row2 [0:5];

    wire myIse = start && (iseId == customId);

    //------------------------------------------------------------
    // Push operation
    //------------------------------------------------------------

    always @(posedge clk)
    begin
        if (myIse && (valueA[0] == 1'd0))
        begin
            row0[0] <= row0[1];
            row0[1] <= row0[2];
            row0[2] <= row0[3];
            row0[3] <= row0[4];
            row0[4] <= row0[5];
            row0[5] <= valueB[7:0];

            row1[0] <= row1[1];
            row1[1] <= row1[2];
            row1[2] <= row1[3];
            row1[3] <= row1[4];
            row1[4] <= row1[5];
            row1[5] <= valueB[15:8];

            row2[0] <= row2[1];
            row2[1] <= row2[2];
            row2[2] <= row2[3];
            row2[3] <= row2[4];
            row2[4] <= row2[5];
            row2[5] <= valueB[23:16];
        end
    end

    //------------------------------------------------------------
    // Sobel helper
    //------------------------------------------------------------

    function [7:0] sobel3x3;
        input [7:0] p00,p01,p02;
        input [7:0] p10,p11,p12;
        input [7:0] p20,p21,p22;

        reg signed [10:0] gx;
        reg signed [10:0] gy;

        reg [10:0] abs_gx;
        reg [10:0] abs_gy;

        reg [11:0] mag;

        begin

            gx =
                -$signed({1'b0,p00})
                +$signed({1'b0,p02})
                -($signed({1'b0,p10}) <<< 1)
                +($signed({1'b0,p12}) <<< 1)
                -$signed({1'b0,p20})
                +$signed({1'b0,p22});

            gy =
                 $signed({1'b0,p00})
                +($signed({1'b0,p01}) <<< 1)
                + $signed({1'b0,p02})
                - $signed({1'b0,p20})
                -($signed({1'b0,p21}) <<< 1)
                - $signed({1'b0,p22});

            abs_gx = gx[10] ? -gx : gx;
            abs_gy = gy[10] ? -gy : gy;

            mag = abs_gx + abs_gy;

            if (mag > 12'd255)
                sobel3x3 = 8'd255;
            else
                sobel3x3 = mag[7:0];
        end
    endfunction

    //------------------------------------------------------------
    // Four parallel Sobels
    //------------------------------------------------------------

    wire [7:0] sob0;
    wire [7:0] sob1;
    wire [7:0] sob2;
    wire [7:0] sob3;

    assign sob0 =
        sobel3x3(
            row0[0], row0[1], row0[2],
            row1[0], row1[1], row1[2],
            row2[0], row2[1], row2[2]
        );

    assign sob1 =
        sobel3x3(
            row0[1], row0[2], row0[3],
            row1[1], row1[2], row1[3],
            row2[1], row2[2], row2[3]
        );

    assign sob2 =
        sobel3x3(
            row0[2], row0[3], row0[4],
            row1[2], row1[3], row1[4],
            row2[2], row2[3], row2[4]
        );

    assign sob3 =
        sobel3x3(
            row0[3], row0[4], row0[5],
            row1[3], row1[4], row1[5],
            row2[3], row2[4], row2[5]
        );

    //------------------------------------------------------------
    // CI response
    //------------------------------------------------------------

    assign done = myIse;

    assign result =
        (myIse && (valueA[0] == 1'd1))
        ? {sob3, sob2, sob1, sob0}
        : 32'd0;

endmodule