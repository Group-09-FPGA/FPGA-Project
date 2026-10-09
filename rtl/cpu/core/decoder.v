`timescale 1ns/1ps

module decoder(
    input  [31:0] instruction,
    
    // Extracted fields
    output [4:0]  rs1,
    output [4:0]  rs2,
    output [4:0]  rd,
    output [2:0]  funct3,
    
    // Control signals
    output reg [31:0] immediate,
    output            immediate_sel,
    output            alu,
    output            lui,
    output            jal,
    output            jalr,
    output            branch,
    output            mem_write,
    output            mem_to_reg,
    output            arithsubtype,
    output            m_op,
    output reg        illegal_inst
);
    `include "opcode.vh"

    assign rs1 = instruction[`RS1];
    assign rs2 = instruction[`RS2];
    assign rd  = instruction[`RD];
    assign funct3 = instruction[`FUNC3];

    wire [6:0] opcode = instruction[`OPCODE];
    wire [6:0] funct7 = instruction[31:25];

    assign m_op          = (opcode == ARITHR) && (funct7 == 7'b0000001);
    assign immediate_sel = (opcode == JALR) || (opcode == LOAD) || (opcode == ARITHI) || (opcode == STORE);
    assign alu           = (opcode == ARITHI) || ((opcode == ARITHR) && !m_op);
    assign lui           = (opcode == LUI);
    assign jal           = (opcode == JAL);
    assign jalr          = (opcode == JALR);
    assign branch        = (opcode == BRANCH);
    assign mem_write     = (opcode == STORE);
    assign mem_to_reg    = (opcode == LOAD);
    
    // Subtype distinguishes ADD/SUB, SRL/SRA
    assign arithsubtype  = instruction[`SUBTYPE] && !(opcode == ARITHI && funct3 == ADD);

    always @(*) begin
        immediate    = 32'h0;
        illegal_inst = 1'b0;

        case (opcode)
            JALR  : immediate = {{20{instruction[31]}}, instruction[31:20]};
            BRANCH: immediate = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            LOAD  : immediate = {{20{instruction[31]}}, instruction[31:20]};
            STORE : immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            ARITHI: immediate = (funct3 == SLL || funct3 == SR) ? {27'b0, instruction[24:20]} : {{20{instruction[31]}}, instruction[31:20]};
            ARITHR: begin
                immediate = 32'h0;
                if (funct7 != 7'b0000000 && funct7 != 7'b0100000 && funct7 != 7'b0000001) begin
                    illegal_inst = 1'b1;
                end
            end
            LUI   : immediate = {instruction[31:12], 12'b0};
            JAL   : immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
            default: illegal_inst = 1'b1;
        endcase
    end
endmodule
