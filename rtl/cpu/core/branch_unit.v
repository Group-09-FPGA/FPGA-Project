`timescale 1ns/1ps

module branch_unit(
    input  [31:0] operand1,
    input  [31:0] operand2,
    input  [2:0]  branch_op,
    output reg    condition_met
);
    `include "opcode.vh"

    wire [32:0] diff_s = {operand1[31], operand1} - {operand2[31], operand2};
    wire [32:0] diff_u = {1'b0, operand1} - {1'b0, operand2};

    always @(*) begin
        case (branch_op)
            BEQ : condition_met = (diff_s == 0);
            BNE : condition_met = (diff_s != 0);
            BLT : condition_met = diff_s[32];
            BGE : condition_met = !diff_s[32];
            BLTU: condition_met = diff_u[32];
            BGEU: condition_met = !diff_u[32];
            default: condition_met = 1'b0;
        endcase
    end
endmodule
