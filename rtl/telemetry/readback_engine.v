`timescale 1ns / 1ps

// Serves one UART RAM-readback request in the UI clock domain.
// Normal kinds wait four cycles for the RAM data; kind "B" scans all 1024
// hash sets (32 at a time) and returns a bitmap of the occupied ones.
module readback_engine (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         req_update,
    input  wire [22:0]  req,             // {toggle, kind[7:0], address[13:0]}
    input  wire [7:0]   hash_valid,      // valid bit of each hash way at the current set
    input  wire [607:0] data,            // RAM data selected for the requested kind
    output wire         active,
    output reg  [9:0]   scan_set,
    output reg  [630:0] rsp              // {req, data}
);
    wire [7:0] kind = req[21:14];
    reg  [2:0]  wait_cnt;
    reg         busy;
    reg  [4:0]  scan_index;
    reg  [31:0] scan_bits;

    wire [31:0] scan_next = scan_bits | ((|hash_valid) ? (32'd1 << scan_index) : 32'd0);
    assign active = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; wait_cnt <= 3'd0; rsp <= 631'd0;
            scan_set <= 10'd0; scan_index <= 5'd0; scan_bits <= 32'd0;
        end else if (req_update) begin
            busy <= 1'b1; wait_cnt <= 3'd0;
            scan_set <= {req[4:0], 5'b0};
            scan_index <= 5'd0; scan_bits <= 32'd0;
        end else if (busy) begin
            if (wait_cnt != 3) begin
                wait_cnt <= wait_cnt + 1'b1;
            end else if (kind == "B") begin
                scan_bits <= scan_next;
                if (scan_index == 31) begin
                    rsp  <= {req, 576'd0, scan_next};
                    busy <= 1'b0;
                end else begin
                    scan_index <= scan_index + 1'b1;
                    scan_set   <= scan_set + 1'b1;
                    wait_cnt   <= 3'd0;
                end
            end else begin
                rsp  <= {req, data};
                busy <= 1'b0;
            end
        end
    end
endmodule
