`timescale 1ns/1ps

module imem_slave (
    input         clk,
    input         reset,
    
    input         req_valid,
    input         req_write,
    input  [31:0] req_addr,
    input  [31:0] req_wdata,
    input  [ 3:0] req_wstrb,
    
    output        rsp_valid,
    output [31:0] rsp_rdata
);

    // IMEM is read-only.
    // The request is accepted immediately when req_valid is high.
    // Memory has 1-cycle latency.
    
    reg valid_d;
    always @(posedge clk or negedge reset) begin
        if (!reset) valid_d <= 1'b0;
        else valid_d <= req_valid && !req_write;
    end
    
    assign rsp_valid = valid_d;

    // Instantiate existing instruction memory
    instr_mem IMEM (
        .clk(clk),
        .pc(req_addr),
        .instr(rsp_rdata)
    );

endmodule
