`timescale 1ns / 1ps

// Bundled-data clock crossing. src_data is copied into a holding register
// before a request toggle crosses; it remains stable until the destination
// acknowledges the transfer. New writes are sent after the acknowledgement.
module config_cdc #(
    parameter WIDTH = 80,
    parameter [WIDTH-1:0] RESET_VALUE = 0
) (
    input wire src_clk, src_rst_n,
    input wire [WIDTH-1:0] src_data,
    output wire src_busy,
    output wire src_ready,
    input wire dst_clk, dst_rst_n,
    output reg [WIDTH-1:0] dst_data,
    output reg dst_update
);
    reg [WIDTH-1:0] held_data;
    reg req_toggle, ack_toggle;
    (* ASYNC_REG = "TRUE" *) reg ack_sync1, ack_sync2;
    (* ASYNC_REG = "TRUE" *) reg req_sync1, req_sync2;
    assign src_busy = req_toggle != ack_sync2;
    assign src_ready = !src_busy && src_data == held_data;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            held_data <= RESET_VALUE;
            req_toggle <= 0;
            ack_sync1 <= 0;
            ack_sync2 <= 0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;
            if (!src_busy && src_data != held_data) begin
                held_data <= src_data;
                req_toggle <= ~req_toggle;
            end
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_data <= RESET_VALUE;
            dst_update <= 1'b0;
            req_sync1 <= 0;
            req_sync2 <= 0;
            ack_toggle <= 0;
        end else begin
            dst_update <= 1'b0;
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;
            if (req_sync2 != ack_toggle) begin
                dst_data <= held_data;
                dst_update <= 1'b1;
                ack_toggle <= req_sync2;
            end
        end
    end
endmodule
