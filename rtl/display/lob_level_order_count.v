// Display-only order count per price level, independent of aggregate shares.
`timescale 1ns/1ps

module lob_level_order_count (
    input  wire        core_clk,
    input  wire        core_rst_n,
    input  wire        delta_valid,
    input  wire        delta_inc,
    input  wire [13:0] delta_addr,
    output reg         init_done,
    input  wire        read_clk,
    input  wire [13:0] read_addr,
    output reg  [11:0] read_count
);
    // The read/modify/write plus VGA read maps to LUT RAM in Vivado. The
    // standalone synth check uses about 2,800 LUT6s on the A7-100T.
    (* ram_style = "distributed" *) reg [11:0] counts [0:16383];
    reg [13:0] init_addr;
    reg [11:0] core_read_data;
    reg stage1_valid, stage1_inc;
    reg [13:0] stage1_addr;
    reg stage2_valid;
    reg [13:0] stage2_addr;
    reg [11:0] stage2_value;
    reg last_write_valid;
    reg [13:0] last_write_addr;
    reg [11:0] last_write_value;
    wire [11:0] forwarded_count =
        (stage2_valid && stage2_addr == stage1_addr) ? stage2_value :
        (last_write_valid && last_write_addr == stage1_addr) ? last_write_value :
        core_read_data;

    // One synchronous core read and one write; the VGA read clock uses a
    // separate read port. Vivado may replicate BRAM to supply both readers.
    always @(posedge core_clk) begin
        if (init_done && delta_valid)
            core_read_data <= counts[delta_addr];
    end

    always @(posedge core_clk) begin
        if (!init_done)
            counts[init_addr] <= 12'd0;
        else if (stage2_valid)
            counts[stage2_addr] <= stage2_value;
    end

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            init_done <= 1'b0;
            init_addr <= 14'd0;
            stage1_valid <= 1'b0;
            stage1_inc <= 1'b0;
            stage1_addr <= 14'd0;
            stage2_valid <= 1'b0;
            stage2_addr <= 14'd0;
            stage2_value <= 12'd0;
            last_write_valid <= 1'b0;
            last_write_addr <= 14'd0;
            last_write_value <= 12'd0;
        end else if (!init_done) begin
            if (init_addr == 14'd16383)
                init_done <= 1'b1;
            else
                init_addr <= init_addr + 14'd1;
        end else begin
            last_write_valid <= stage2_valid;
            if (stage2_valid) begin
                last_write_addr <= stage2_addr;
                last_write_value <= stage2_value;
            end
            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                stage2_addr <= stage1_addr;
                stage2_value <= stage1_inc ? forwarded_count + 12'd1
                                           : forwarded_count - 12'd1;
            end
            stage1_valid <= delta_valid;
            if (delta_valid) begin
                stage1_addr <= delta_addr;
                stage1_inc <= delta_inc;
            end
        end
    end

    always @(posedge read_clk)
        read_count <= counts[read_addr];
endmodule
