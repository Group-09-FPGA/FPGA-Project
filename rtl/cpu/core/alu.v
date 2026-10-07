`timescale 1ns/1ps

module alu(
    input  [31:0] operand1,
    input  [31:0] operand2,
    input  [2:0]  alu_op,
    input         arithsubtype,
    output reg [31:0] result
);
    `include "opcode.vh"

    wire [32:0] ex_result_subs = {operand1[31], operand1} - {operand2[31], operand2};
    wire [32:0] ex_result_subu = {1'b0, operand1} - {1'b0, operand2};

    always @(*) begin
        case (alu_op)
            ADD : result = arithsubtype ? (operand1 - operand2) : (operand1 + operand2);
            SLL : result = operand1 << operand2[4:0];
            SLT : result = {31'b0, ex_result_subs[32]};
            SLTU: result = {31'b0, ex_result_subu[32]};
            XOR : result = operand1 ^ operand2;
            SR  : result = arithsubtype ? ($signed(operand1) >>> operand2[4:0]) : (operand1 >> operand2[4:0]);
            OR  : result = operand1 | operand2;
            AND : result = operand1 & operand2;
            default: result = 32'hx;
        endcase
    end
endmodule
