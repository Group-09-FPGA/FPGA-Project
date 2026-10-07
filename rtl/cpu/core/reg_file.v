`timescale 1ns/1ps

module reg_file (
    input         clk,
    input         reset,
    
    input  [4:0]  read_addr1,
    output [31:0] read_data1,
    
    input  [4:0]  read_addr2,
    output [31:0] read_data2,
    
    input         write_enable,
    input  [4:0]  write_addr,
    input  [31:0] write_data
);

    reg [31:0] regs [31:1];
    integer i;
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end
        else if (write_enable && write_addr != 5'd0) begin
            regs[write_addr] <= write_data;
        end
    end

    assign read_data1 = (read_addr1 == 5'd0) ? 32'd0 : regs[read_addr1];
    assign read_data2 = (read_addr2 == 5'd0) ? 32'd0 : regs[read_addr2];

endmodule
