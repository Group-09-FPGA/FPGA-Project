`timescale 1ns/1ps

module forwarding_unit (
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    
    // Register file raw outputs
    input  [31:0] reg_rdata1_raw,
    input  [31:0] reg_rdata2_raw,
    
    // WB stage signals for forwarding
    input         wb_reg_write_en,
    input  [4:0]  wb_rd,
    input  [31:0] wb_result,
    input         wb_mem_to_reg,
    input  [31:0] wb_read_data,
    input         wb_stall,
    
    // Forwarded values
    output [31:0] rdata1,
    output [31:0] rdata2
);

    wire [31:0] wb_forward_val = wb_mem_to_reg ? wb_read_data : wb_result;

    assign rdata1 = (rs1 == 5'd0) ? 32'd0 :
                    (!wb_stall && wb_reg_write_en && (wb_rd == rs1)) ? wb_forward_val :
                    reg_rdata1_raw;

    assign rdata2 = (rs2 == 5'd0) ? 32'd0 :
                    (!wb_stall && wb_reg_write_en && (wb_rd == rs2)) ? wb_forward_val :
                    reg_rdata2_raw;

endmodule
