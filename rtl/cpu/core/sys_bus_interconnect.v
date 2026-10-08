`timescale 1ns/1ps

module sys_bus_interconnect (
    input clk,
    input reset,

    // Master (CPU) Interface
    input         cpu_req_valid,
    input         cpu_req_write,
    input  [31:0] cpu_req_addr,
    input  [31:0] cpu_req_wdata,
    input  [ 3:0] cpu_req_wstrb,
    
    output        cpu_rsp_valid,
    output [31:0] cpu_rsp_rdata,
    output        cpu_rsp_error,

    // Slave 0: IMEM (0x00000000 - 0x00003FFF)
    output        imem_req_valid,
    output        imem_req_write,
    output [31:0] imem_req_addr,
    output [31:0] imem_req_wdata,
    output [ 3:0] imem_req_wstrb,
    input         imem_rsp_valid,
    input  [31:0] imem_rsp_rdata,

    // Slave 1: DMEM (0x20000000 - 0x20003FFF)
    output        dmem_req_valid,
    output        dmem_req_write,
    output [31:0] dmem_req_addr,
    output [31:0] dmem_req_wdata,
    output [ 3:0] dmem_req_wstrb,
    input         dmem_rsp_valid,
    input  [31:0] dmem_rsp_rdata
);

    // Address Decoding
    wire sel_imem = (cpu_req_addr[31:28] == 4'h0);
    wire sel_dmem = (cpu_req_addr[31:28] == 4'h2) || (cpu_req_addr[31:28] == 4'hF);
    
    // We only have one outstanding transaction, so we need to track which slave was selected
    // to route the response back.
    reg [1:0] slave_sel;
    localparam SEL_NONE = 2'd0;
    localparam SEL_IMEM = 2'd1;
    localparam SEL_DMEM = 2'd2;
    localparam SEL_ERR  = 2'd3;
    
    wire active_transaction = (slave_sel != SEL_NONE);
    wire req_en = cpu_req_valid && (!active_transaction || cpu_rsp_valid);
    
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            slave_sel <= SEL_NONE;
        end else begin
            if (req_en) begin
                if (sel_imem) slave_sel <= SEL_IMEM;
                else if (sel_dmem) slave_sel <= SEL_DMEM;
                else slave_sel <= SEL_ERR;
            end else if (cpu_rsp_valid) begin
                // Transaction complete
                slave_sel <= SEL_NONE;
            end
        end
    end

    // Route Request
    
    assign imem_req_valid = req_en && sel_imem;
    assign imem_req_write = cpu_req_write;
    assign imem_req_addr  = cpu_req_addr;
    assign imem_req_wdata = cpu_req_wdata;
    assign imem_req_wstrb = cpu_req_wstrb;

    assign dmem_req_valid = req_en && sel_dmem;
    assign dmem_req_write = cpu_req_write;
    assign dmem_req_addr  = cpu_req_addr;
    assign dmem_req_wdata = cpu_req_wdata;
    assign dmem_req_wstrb = cpu_req_wstrb;

    // Route Response
    // For unmapped addresses, we generate a 1-cycle error response.
    reg err_rsp_valid;
    always @(posedge clk or negedge reset) begin
        if (!reset) err_rsp_valid <= 1'b0;
        else if (req_en && !sel_imem && !sel_dmem) err_rsp_valid <= 1'b1;
        else err_rsp_valid <= 1'b0;
    end

    assign cpu_rsp_valid = (slave_sel == SEL_IMEM) ? imem_rsp_valid :
                           (slave_sel == SEL_DMEM) ? dmem_rsp_valid :
                           (slave_sel == SEL_ERR)  ? err_rsp_valid : 1'b0;

    assign cpu_rsp_rdata = (slave_sel == SEL_IMEM) ? imem_rsp_rdata :
                           (slave_sel == SEL_DMEM) ? dmem_rsp_rdata : 32'h0;

    assign cpu_rsp_error = (slave_sel == SEL_ERR) ? err_rsp_valid : 1'b0;

endmodule
