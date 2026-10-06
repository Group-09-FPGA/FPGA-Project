`timescale 1ns/1ps

////////////////////////////////////////////////////////////// Stage 2: Execute////////////////////////////////////////////////////////////
module execute
#(
	parameter [31:0] RESET = 32'h0000_0000
)
(
	input clk,
	input reset,

	// -----------------------------	// FROM ID/EX	// -----------------------------
	input  [31:0] reg_rdata1,
	input  [31:0] reg_rdata2,
	input  [31:0] execute_imm,
	input  [31:0] pc,
	input  [31:0] fetch_pc,
	input     	immediate_sel,
	input     	mem_write,
	input     	jal,
	input     	jalr,
	input     	lui,
	input     	alu,
	input     	branch,
	input     	arithsubtype,
	input     	mem_to_reg,
	input     	stall_read,

	input  [4:0]  dest_reg_sel,
	input  [2:0]  alu_op,
	input  [1:0]  dmem_raddr,

	// -----------------------------	// FROM WB	// -----------------------------
	input     	wb_branch_i,
	input     	wb_branch_nxt_i,

	// -----------------------------	// EX → PIPE	// -----------------------------
	output [31:0] alu_operand1,
	output [31:0] alu_operand2,
	output [31:0] mem_address, // renamed from mem_address
	output    	branch_stall,

	output reg [31:0] next_pc,
	output reg    	branch_taken,

	// -----------------------------  // EX → WB	// -----------------------------
	output [31:0] wb_result,
	output    	wb_mem_write,
	// NAMING FIX: was 'wb_alu_to_reg' — misleading because LOADs also assert this.
	// This is the global register-file write-enable (RegWrite in textbooks).
	output    	wb_reg_write_en,
	output [4:0]  wb_dest_reg_sel,
	output    	wb_branch,
	output    	wb_branch_nxt,
	output    	wb_mem_to_reg,
	output [1:0]  wb_read_address,
	output [2:0]  mem_alu_operation,
	// BUG fixed: registered store data (RS2) and store address exposed from pipeline register
	output [31:0] wb_reg_rdata2,    // registered RS2 value = actual payload to write to memory
	output [31:0] wb_mem_address // renamed from wb_mem_address  // registered store address = rs1 + imm
);

//////////////// Including OPCODES ////////////////////////////
`include "opcode.vh"

////////////////////////////////////////////////////////////// LOCAL INTERNAL SIGNALS/////////////////////////////////

reg  [31:0] ex_result;
wire [32:0] ex_result_subs;
wire [32:0] ex_result_subu;

////////////////////////////////////////////////////////////// Operand selection///////////////////////////////////////////////////////

// Select ALU operands

assign alu_operand1 = reg_rdata1;
assign alu_operand2 = immediate_sel
	                    	? execute_imm   // TODO completed, description: immediate operand selected
	                    	: reg_rdata2;   // TODO completed, description: register operand 2 selected

////////////////////////////////////////////////////////////// Subtractions////////////////////////////////////////////////////////////


// TODO-EX-2 completed, description: Generate subtraction results for signed and unsigned branch comparisons
// - One result (ex_result_subs) must treat both operands as signed values
// - Another result (ex_result_subu) must treat both operands as unsigned values
// - The results must be wide enough to capture the sign/borrow bit
// - These results will be used later to evaluate branch conditions

assign ex_result_subs =
	{alu_operand1[31], alu_operand1} -
	{alu_operand2[31], alu_operand2};

assign ex_result_subu =
	{1'b0, alu_operand1} -
	{1'b0, alu_operand2};

////////////////////////////////////////////////////////////// Address & branch stall////////////////////////////////////////

assign mem_address = alu_operand1 + execute_imm; // renamed from mem_address
assign branch_stall  = wb_branch_nxt_i || wb_branch_i;

////////////////////////////////////////////////////////////// Next PC logic////////////////////////////////////////////////////////////


// TODO-EX-3 completed, description: Compute next PC and branch decisions for JAL, JALR, and conditional branches
always @(*) begin
	next_pc  	= fetch_pc + 4;
	branch_taken = !branch_stall;

	case (1'b1)
    	jal  : next_pc = pc + execute_imm;          // TODO completed, description: JAL target pc + imm
    	jalr : next_pc = alu_operand1 + execute_imm; // TODO completed, description: JALR target rs1 + imm

    	branch: begin
        	case (alu_op)
            	BEQ:  begin
                	next_pc = (ex_result_subs == 0)  // BEQ: taken if A == B (difference is zero)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (ex_result_subs != 0)
                    	branch_taken = 1'b0;          // condition failed: not equal
            	end
            	BNE:  begin                           // TODO completed, description: BNE condition evaluation
                	next_pc = (ex_result_subs != 0)  // taken if A != B (difference is non-zero)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (ex_result_subs == 0)
                    	branch_taken = 1'b0;          // condition failed: operands were equal
            	end
            	BLT:  begin
                	next_pc = ex_result_subs[32]     // BLT: bit32=1 means negative → A < B (signed)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (!ex_result_subs[32])
                    	branch_taken = 1'b0;          // condition failed: A >= B signed
            	end
            	BGE:  begin                           // TODO completed, description: BGE condition evaluation
                	next_pc = (!ex_result_subs[32])  // taken if bit32=0 → A >= B (signed, no negative result)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (ex_result_subs[32])
                    	branch_taken = 1'b0;          // condition failed: A < B signed
            	end
            	BLTU: begin
                	next_pc = ex_result_subu[32]     // BLTU: bit32=1 means borrow → A < B (unsigned)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (!ex_result_subu[32])
                    	branch_taken = 1'b0;          // condition failed: A >= B unsigned
            	end
            	BGEU: begin                           // TODO completed, description: BGEU condition evaluation
                	next_pc = (!ex_result_subu[32])  // taken if bit32=0 → no borrow → A >= B (unsigned)
                          	? pc + execute_imm
                          	: fetch_pc + 4;
                	if (ex_result_subu[32])
                    	branch_taken = 1'b0;          // condition failed: A < B unsigned
            	end
            	default: next_pc = fetch_pc + 4;     // bug fix: was fetch_pc (missing +4); unknown alu_op still advances sequentially
        	endcase
    	end

    	default: begin     	 
        	next_pc  	= fetch_pc + 4;
        	branch_taken = 1'b0;
    	end
	endcase
end

////////////////////////////////////////////////////////////// ALU result logic////////////////////////////////////////////////////////////

// TODO-EX-4:
// Generate the execute-stage result (ex_result)
// Guidelines:
// - For store instructions, forward the value that will be written to memory
// - For jump instructions (JAL/JALR), produce the return address (PC + 4)
// - LUI must place the immediate value directly into the destination register
// - For ALU instructions, compute the result based on the decoded ALU operation
// - The arithmetic subtype signal selects between related operations


always @(*) begin
	case (1'b1)
    	mem_write: ex_result = alu_operand2;
    	jal,
    	jalr:  	ex_result = pc + 4;
    	lui:   	ex_result = execute_imm;

    	alu: begin
        	case (alu_op)
            	ADD : ex_result =                                        // bug fix: ADD/SUB share opcode; arithsubtype=1 selects SUB
                  arithsubtype
                  ? alu_operand1 - alu_operand2
                  : alu_operand1 + alu_operand2;
            	SLL : ex_result = alu_operand1 << alu_operand2[4:0];     // TODO completed, description: logical left shift
            	// BUG fixed, description: SLT 1-bit comparison result was not zero-extended to 32 bits
            	SLT : ex_result = {31'b0, ex_result_subs[32]};           // signed compare: bit32 of sign-extended subtraction = 1 means A<B
            	SLTU: ex_result = {31'b0, ex_result_subu[32]};           // TODO completed, description: unsigned compare
            	XOR : ex_result = alu_operand1 ^ alu_operand2;           // TODO completed, description: bitwise XOR
            	SR  : ex_result =
                  arithsubtype
                  ? $signed(alu_operand1) >>> alu_operand2[4:0]      // SRA: arithmetic right shift (sign-extends)
            	            	  : alu_operand1 >> alu_operand2[4:0];               // TODO completed, description: logical right shift
            	OR  : ex_result = alu_operand1 | alu_operand2;           // TODO completed, description: bitwise OR
            	AND : ex_result = alu_operand1 & alu_operand2;           // TODO completed, description: bitwise AND
            	default: ex_result = 'hx;
        	endcase
    	end

    	default: ex_result = 'hx;
	endcase
end


////////////////////////////////////////////////////////////// EX → WB pipeline register/////////////////////////////////////////

ex_mem_wb_reg u_ex_mem_wb (
	.clk        	(clk),
	.reset_n    	(reset),
	.stall_n    	(stall_read),

	.ex_result  	(ex_result),

	// BUG fixed: reg_rdata2 (actual RS2 value = store payload) and mem_address
	// must be registered through this pipeline register so that the WB stage
	// reads the values from the CURRENT instruction, not the next one in EX.
	// Previously they bypassed this register entirely (combinational paths).
	.reg_rdata2_i   (reg_rdata2),    // store data: raw RS2, not alu_operand2
	.mem_address_i(mem_address), // renamed from mem_address_i(mem_address), // store address: rs1 + imm

	.mem_write  	(mem_write && !branch_stall),
	// NAMING FIX: 'alu_to_reg' renamed to 'reg_write_en'.
	// LOADs set mem_to_reg=1, which is included here, so the old name 'alu_to_reg' was misleading.
	// This is purely a register-file write-enable (RegWrite), not an ALU-specific signal.
	.reg_write_en	(alu | lui | jal |
                  	jalr | mem_to_reg),
	.dest_reg_sel   (dest_reg_sel),
	.branch_taken   (branch_taken),
	.mem_to_reg 	(mem_to_reg),
	.read_address   (dmem_raddr),
	.alu_operation  (alu_op),

	.ex_mem_result    	(wb_result),
	.ex_mem_mem_write 	(wb_mem_write),
	.ex_mem_reg_write_en	(wb_reg_write_en),
	.ex_mem_dest_reg_sel  (wb_dest_reg_sel),
	.ex_mem_branch    	(wb_branch),
	.ex_mem_branch_nxt	(wb_branch_nxt),
	.ex_mem_mem_to_reg	(wb_mem_to_reg),
	.ex_mem_read_address  (wb_read_address),
	.ex_mem_alu_operation (mem_alu_operation),
	.ex_mem_reg_rdata2    (wb_reg_rdata2),   // registered store data → wb.v
	.ex_mem_mem_address (wb_mem_address) // renamed from ex_mem_mem_address (wb_mem_address) // registered store address → wb.v
);

endmodule


module ex_mem_wb_reg (
	input     	clk,
	input     	reset_n,
	input     	stall_n,

	// Data
	input  [31:0] ex_result,

	// BUG fixed: store data (RS2) and store address must be registered here
	input  [31:0] reg_rdata2_i,    // actual store payload (raw RS2)
	input  [31:0] mem_address_i, // renamed from mem_address_i // computed store address (rs1 + imm)

	// Control inputs from EX/MEM
	input     	mem_write,
	// NAMING FIX: was 'alu_to_reg'; renamed to 'reg_write_en' (register-file write enable)
	input     	reg_write_en,
	input  [4:0]  dest_reg_sel,
	input     	branch_taken,
	input     	mem_to_reg,
	input  [1:0]  read_address,
	input  [2:0]  alu_operation,

	// Outputs to WB
	output reg [31:0] ex_mem_result,
	output reg    	ex_mem_mem_write,
	output reg    	ex_mem_reg_write_en,
	output reg [4:0]  ex_mem_dest_reg_sel,
	output reg    	ex_mem_branch,
	output reg    	ex_mem_branch_nxt,
	output reg    	ex_mem_mem_to_reg,
	output reg [1:0]  ex_mem_read_address,
	output reg [2:0]  ex_mem_alu_operation,
	output reg [31:0] ex_mem_reg_rdata2,    // registered store data
	output reg [31:0] ex_mem_mem_address // renamed from ex_mem_mem_address  // registered store address
);

always @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
    	ex_mem_result        <= 32'h0;
    	ex_mem_mem_write     <= 1'b0;
    	ex_mem_reg_write_en  <= 1'b0;
    	ex_mem_dest_reg_sel  <= 5'h0;
    	ex_mem_branch        <= 1'b0;
    	ex_mem_branch_nxt    <= 1'b0;
    	ex_mem_mem_to_reg    <= 1'b0;
    	ex_mem_read_address  <= 2'h0;
    	ex_mem_alu_operation <= 3'h0;
    	ex_mem_reg_rdata2    <= 32'h0; // BUG fixed: reset store data register
    	ex_mem_mem_address <= 32'h0; // renamed from ex_mem_mem_address // BUG fixed: reset store address register
	end
	else if (!stall_n) begin
    	ex_mem_result        <= ex_result;
    	ex_mem_mem_write     <= mem_write;
    	ex_mem_reg_write_en  <= reg_write_en;
    	ex_mem_dest_reg_sel  <= dest_reg_sel;
    	ex_mem_branch        <= branch_taken;
    	ex_mem_branch_nxt    <= ex_mem_branch;
    	ex_mem_mem_to_reg    <= mem_to_reg;
    	ex_mem_read_address  <= read_address;
    	ex_mem_alu_operation <= alu_operation;
    	ex_mem_reg_rdata2    <= reg_rdata2_i;    // BUG fixed: register actual store data (RS2)
    	ex_mem_mem_address <= mem_address_i; // renamed from ex_mem_mem_address <= mem_address_i // BUG fixed: register store address
	end
end

endmodule