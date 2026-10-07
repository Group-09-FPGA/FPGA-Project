`timescale 1ns/1ps

module hazard_unit(
    input  clk,
    input  reset,
    
    input  stall_read_i,
    input  wb_mem_to_reg_i,
    input  dmem_read_valid_i,
    input  wb_branch_i,
    
    output reg wb_stall_first_o,
    output reg wb_stall_second_o,
    output     wb_stall_o
);

    assign wb_stall_o = wb_stall_first_o || wb_stall_second_o;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            wb_stall_first_o  <= 1'b0;
            wb_stall_second_o <= 1'b0;
        end
        else if (!stall_read_i && !((wb_mem_to_reg_i && !dmem_read_valid_i))) begin
            wb_stall_first_o  <= wb_branch_i;
            wb_stall_second_o <= wb_stall_first_o;
        end
    end
endmodule
