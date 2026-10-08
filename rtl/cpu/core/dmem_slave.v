`timescale 1ns/1ps

module dmem_slave #(
    parameter DELAY_CYCLES = 0 // Extra delay cycles (0 means 1-cycle latency total)
)(
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

    // Artificial delay logic
    reg [3:0] delay_cnt;
    reg processing;
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            delay_cnt <= 0;
            processing <= 1'b0;
        end else begin
            if (req_valid && !processing) begin
                processing <= 1'b1;
                delay_cnt <= DELAY_CYCLES[3:0];
            end else if (processing) begin
                if (delay_cnt > 0) begin
                    delay_cnt <= delay_cnt - 1;
                end else begin
                    processing <= 1'b0; // Done
                end
            end
        end
    end
    
    // The inner memory gets the read/write enable ONLY on the cycle it completes.
    // Wait, the inner memory data_mem has a 1-cycle read latency itself.
    // So if DELAY_CYCLES = 0, we can just feed req_valid directly to data_mem,
    // and rsp_valid is the cycle after.
    // Let's restructure the delay to delay the ENABLES to data_mem.
    
    wire fire_mem = processing && (delay_cnt == 0);
    wire do_read = fire_mem && !req_write;
    wire do_write = fire_mem && req_write;
    
    // When fire_mem pulses, memory starts processing.
    // Response is valid in the next cycle.
    reg rsp_valid_reg;
    always @(posedge clk or negedge reset) begin
        if (!reset) rsp_valid_reg <= 1'b0;
        else rsp_valid_reg <= fire_mem;
    end
    
    assign rsp_valid = rsp_valid_reg;

    data_mem DMEM (
        .clk(clk),
        .re(do_read),
        .raddr(req_addr),
        .we(do_write),
        .waddr(req_addr),
        .wdata(req_wdata),
        .wstrb(req_wstrb),
        .rdata(rsp_rdata)
    );

endmodule
