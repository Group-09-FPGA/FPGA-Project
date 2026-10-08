`timescale 1ns/1ps

module cpu_core
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input         clk,
    input         reset,
    input         stall,
    output reg    exception,
    output [31:0] pc_out,

    input         inst_mem_is_valid,
    input  [31:0] inst_mem_read_data,
    output [31:0] inst_mem_address,

    input  [31:0] dmem_read_data_temp,
    input         dmem_write_valid,
    input         dmem_read_valid,
    output        dmem_read_ready,
    output [31:0] dmem_read_address,
    output        dmem_write_ready,
    output [31:0] dmem_write_address,
    output [31:0] dmem_write_data,
    output [ 3:0] dmem_write_byte
);
    `include "opcode.vh"

    // --------------------------------------------------------
    // STALL AND HAZARD LOGIC
    // --------------------------------------------------------
    reg stall_read;
    always @(posedge clk or negedge reset) begin
        if (!reset) stall_read <= 1'b0;
        else        stall_read <= stall;
    end

    wire wb_stall_first, wb_stall_second, wb_stall;
    reg wb_mem_to_reg, wb_branch;
    
    hazard_unit u_hazard (
        .clk(clk),
        .reset(reset),
        .stall_read_i(stall_read),
        .wb_mem_to_reg_i(wb_mem_to_reg),
        .dmem_read_valid_i(dmem_read_valid),
        .wb_branch_i(wb_branch),
        .wb_stall_first_o(wb_stall_first),
        .wb_stall_second_o(wb_stall_second),
        .wb_stall_o(wb_stall)
    );

    wire branch_stall = wb_stall_first || wb_branch;

    // --------------------------------------------------------
    // FETCH STAGE
    // --------------------------------------------------------
    reg [31:0] fetch_pc;
    wire [31:0] next_pc;
    wire branch_taken;

    always @(posedge clk or negedge reset) begin
        if (!reset)
            fetch_pc <= RESET;
        else if (!stall_read) begin
            fetch_pc <= branch_stall ? fetch_pc + 4 : next_pc;
        end
    end

    assign inst_mem_address = fetch_pc;
    assign pc_out = fetch_pc;

    wire [31:0] instruction = stall_read ? NOP : inst_mem_read_data;

    reg [31:0] id_pc;
    always @(posedge clk or negedge reset) begin
        if (!reset) id_pc <= RESET;
        else if (!stall_read) id_pc <= fetch_pc;
    end

    wire illegal_inst;
    always @(posedge clk or negedge reset) begin
        if (!reset) exception <= 1'b0;
        else if (illegal_inst || fetch_pc[1:0] != 2'b00) exception <= 1'b1;
        else exception <= 1'b0;
    end

    // --------------------------------------------------------
    // DECODE STAGE
    // --------------------------------------------------------
    wire [4:0] id_rs1, id_rs2, id_rd;
    wire [2:0] id_funct3;
    wire [31:0] id_imm;
    wire id_imm_sel, id_alu, id_lui, id_jal, id_jalr;
    wire id_branch, id_mem_write, id_mem_to_reg, id_arithsubtype;

    decoder u_decoder (
        .instruction(instruction),
        .rs1(id_rs1), .rs2(id_rs2), .rd(id_rd), .funct3(id_funct3),
        .immediate(id_imm), .immediate_sel(id_imm_sel),
        .alu(id_alu), .lui(id_lui), .jal(id_jal), .jalr(id_jalr),
        .branch(id_branch), .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg), .arithsubtype(id_arithsubtype),
        .illegal_inst(illegal_inst)
    );

    // --------------------------------------------------------
    // ID -> EX PIPELINE REGISTERS
    // --------------------------------------------------------
    reg [31:0] ex_pc, ex_imm;
    reg [4:0] ex_rd, ex_rs1, ex_rs2;
    reg [2:0] ex_alu_op;
    reg ex_imm_sel, ex_alu, ex_lui, ex_jal, ex_jalr, ex_branch;
    reg ex_mem_write, ex_mem_to_reg, ex_arithsubtype;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            ex_pc <= 32'h0; ex_imm <= 32'h0;
            ex_rd <= 5'h0; ex_rs1 <= 5'h0; ex_rs2 <= 5'h0; ex_alu_op <= 3'h0;
            ex_imm_sel <= 1'b0; ex_alu <= 1'b0; ex_lui <= 1'b0; ex_jal <= 1'b0; ex_jalr <= 1'b0;
            ex_branch <= 1'b0; ex_mem_write <= 1'b0; ex_mem_to_reg <= 1'b0; ex_arithsubtype <= 1'b0;
        end else if (!stall_read) begin
            ex_pc <= id_pc; ex_imm <= id_imm;
            ex_rd <= id_rd; ex_rs1 <= id_rs1; ex_rs2 <= id_rs2; ex_alu_op <= id_funct3;
            ex_imm_sel <= id_imm_sel; ex_alu <= id_alu; ex_lui <= id_lui; ex_jal <= id_jal;
            ex_jalr <= id_jalr; ex_branch <= id_branch; ex_mem_write <= id_mem_write;
            ex_mem_to_reg <= id_mem_to_reg; ex_arithsubtype <= id_arithsubtype;
        end
    end

    // --------------------------------------------------------
    // REGISTER FILE & FORWARDING (IN EX STAGE!)
    // --------------------------------------------------------
    wire [31:0] reg_rdata1_raw, reg_rdata2_raw;
    wire [31:0] ex_rdata1, ex_rdata2;
    reg wb_reg_write_en;
    reg [4:0] wb_dest_reg_sel;
    reg [31:0] wb_result;
    wire [31:0] wb_read_data;

    reg_file u_reg_file (
        .clk(clk), .reset(reset),
        .read_addr1(ex_rs1), .read_data1(reg_rdata1_raw),
        .read_addr2(ex_rs2), .read_data2(reg_rdata2_raw),
        .write_enable(wb_reg_write_en && !stall_read && !wb_stall),
        .write_addr(wb_dest_reg_sel),
        .write_data(wb_mem_to_reg ? wb_read_data : wb_result)
    );

    forwarding_unit u_forwarding (
        .rs1(ex_rs1), .rs2(ex_rs2),
        .reg_rdata1_raw(reg_rdata1_raw), .reg_rdata2_raw(reg_rdata2_raw),
        .wb_reg_write_en(wb_reg_write_en), .wb_rd(wb_dest_reg_sel),
        .wb_result(wb_result), .wb_mem_to_reg(wb_mem_to_reg),
        .wb_read_data(wb_read_data), .wb_stall(wb_stall),
        .rdata1(ex_rdata1), .rdata2(ex_rdata2)
    );

    // --------------------------------------------------------
    // EXECUTE STAGE
    // --------------------------------------------------------
    wire [31:0] alu_operand1 = ex_rdata1;
    wire [31:0] alu_operand2 = ex_imm_sel ? ex_imm : ex_rdata2;
    wire [31:0] alu_out;
    
    alu u_alu (
        .operand1(alu_operand1), .operand2(alu_operand2),
        .alu_op(ex_alu_op), .arithsubtype(ex_arithsubtype),
        .result(alu_out)
    );

    wire branch_cond_met;
    branch_unit u_branch_cond (
        .operand1(alu_operand1), .operand2(alu_operand2),
        .branch_op(ex_alu_op), .condition_met(branch_cond_met)
    );

    wire [31:0] ex_mem_address = alu_operand1 + ex_imm;

    reg [31:0] ex_result;
    always @(*) begin
        if (ex_mem_write) ex_result = alu_operand2;
        else if (ex_jal || ex_jalr) ex_result = ex_pc + 4;
        else if (ex_lui) ex_result = ex_imm;
        else if (ex_alu) ex_result = alu_out;
        else ex_result = 32'h0;
    end

    // branch decisions
    assign branch_taken = !branch_stall && (
        ex_jal || ex_jalr || (ex_branch && branch_cond_met)
    );
    
    wire [31:0] next_pc_comb;
    assign next_pc_comb = 
        ex_jal ? ex_pc + ex_imm :
        ex_jalr ? alu_operand1 + ex_imm :
        (ex_branch && branch_cond_met) ? ex_pc + ex_imm :
        fetch_pc + 4;
    assign next_pc = next_pc_comb;
    
    assign dmem_read_address = ex_mem_address;

    // --------------------------------------------------------
    // EX -> WB PIPELINE REGISTERS
    // --------------------------------------------------------
    reg wb_mem_write, wb_branch_nxt;
    reg [2:0] wb_alu_operation;
    reg [31:0] wb_mem_address, wb_reg_rdata2;
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            wb_result <= 32'h0; wb_mem_write <= 1'b0; wb_reg_write_en <= 1'b0;
            wb_dest_reg_sel <= 5'h0; wb_branch <= 1'b0; wb_branch_nxt <= 1'b0;
            wb_mem_to_reg <= 1'b0; wb_alu_operation <= 3'h0;
            wb_mem_address <= 32'h0; wb_reg_rdata2 <= 32'h0;
        end else if (!stall_read) begin
            wb_result <= ex_result;
            wb_mem_write <= ex_mem_write && !branch_stall;
            wb_reg_write_en <= ex_alu || ex_lui || ex_jal || ex_jalr || ex_mem_to_reg;
            wb_dest_reg_sel <= ex_rd;
            wb_branch <= branch_taken;
            wb_branch_nxt <= wb_branch; // 2nd cycle of branch stall
            wb_mem_to_reg <= ex_mem_to_reg;
            wb_alu_operation <= ex_alu_op;
            wb_mem_address <= ex_mem_address;
            wb_reg_rdata2 <= ex_rdata2;
        end
    end

    // --------------------------------------------------------
    // WRITEBACK STAGE (LOAD / STORE ALIGNMENT)
    // --------------------------------------------------------
    assign dmem_read_ready = ex_mem_to_reg;
    assign dmem_write_ready = wb_mem_write;
    assign dmem_write_address = wb_mem_address;
    
    reg [31:0] wb_write_data;
    reg [3:0]  wb_write_byte;
    always @* begin
        wb_write_data = 32'h0;
        wb_write_byte = 4'h0;
        if (!stall_read && !wb_stall && wb_mem_write) begin
            case (wb_alu_operation)
                SB: begin
                    wb_write_data = {4{wb_reg_rdata2[7:0]}};
                    case (wb_mem_address[1:0])
                        2'b00: wb_write_byte = 4'b0001;
                        2'b01: wb_write_byte = 4'b0010;
                        2'b10: wb_write_byte = 4'b0100;
                        2'b11: wb_write_byte = 4'b1000;
                    endcase
                end
                SH: begin
                    wb_write_data = {2{wb_reg_rdata2[15:0]}};
                    wb_write_byte = wb_mem_address[1] ? 4'b1100 : 4'b0011;
                end
                SW: begin
                    wb_write_data = wb_reg_rdata2;
                    wb_write_byte = 4'b1111;
                end
                default: begin
                    wb_write_data = 32'hx;
                    wb_write_byte = 4'hx;
                end
            endcase
        end
    end
    assign dmem_write_data = wb_write_data;
    assign dmem_write_byte = wb_write_byte;

    wire [1:0] wb_read_address = wb_mem_address[1:0];
    wire [31:0] dmem_rdata = dmem_read_data_temp;
    reg [31:0] wb_read_data_out;
    always @* begin
        case (wb_alu_operation)
            LB: begin
                case (wb_read_address)
                    2'b00: wb_read_data_out = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                    2'b01: wb_read_data_out = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: wb_read_data_out = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: wb_read_data_out = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            LH: wb_read_data_out = wb_read_address[1] ? {{16{dmem_rdata[31]}}, dmem_rdata[31:16]} : {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            LW: wb_read_data_out = dmem_rdata;
            LBU: begin
                case (wb_read_address)
                    2'b00: wb_read_data_out = {24'h0, dmem_rdata[7:0]};
                    2'b01: wb_read_data_out = {24'h0, dmem_rdata[15:8]};
                    2'b10: wb_read_data_out = {24'h0, dmem_rdata[23:16]};
                    2'b11: wb_read_data_out = {24'h0, dmem_rdata[31:24]};
                endcase
            end
            LHU: wb_read_data_out = wb_read_address[1] ? {16'h0, dmem_rdata[31:16]} : {16'h0, dmem_rdata[15:0]};
            default: wb_read_data_out = 32'd0;
        endcase
    end
    assign wb_read_data = wb_read_data_out;

endmodule
