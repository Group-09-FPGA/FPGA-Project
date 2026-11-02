// Laptop -> FPGA read-only memory query: ?S0001\n
// FPGA -> laptop response: @S0001=<fixed-width hexadecimal>\r\n
// S slot, H hash set (all eight ways), X stash, P price quantity,
// F free stack, L level order count, Q quote ring, E event ring,
// B 32-bit bitmap of occupied hash sets (address is group of 32 sets).
`timescale 1ns/1ps
module uart_readback #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115_200
) (
    input wire clk, rst_n, uart_rxd,
    output reg req_toggle,
    output reg [7:0] req_kind,
    output reg [13:0] req_addr,
    input wire rsp_update,
    input wire [630:0] rsp_payload,
    output wire tx_valid,
    output reg [7:0] tx_byte,
    input wire tx_ready
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    reg rx_meta, rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_count;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg rx_byte_valid;
    reg [7:0] rx_byte;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1; rx_sync <= 1; rx_state <= 0;
            rx_count <= 0; rx_bit <= 0; rx_shift <= 0;
            rx_byte_valid <= 0; rx_byte <= 0;
        end else begin
            rx_meta <= uart_rxd;
            rx_sync <= rx_meta;
            rx_byte_valid <= 0;
            case (rx_state)
                0: if (!rx_sync) begin
                    rx_count <= CLKS_PER_BIT/2;
                    rx_state <= 1;
                end
                1: if (rx_count == 0) begin
                    if (!rx_sync) begin
                        rx_count <= CLKS_PER_BIT-1;
                        rx_bit <= 0;
                        rx_state <= 2;
                    end else rx_state <= 0;
                end else rx_count <= rx_count-1'b1;
                2: if (rx_count == 0) begin
                    rx_shift[rx_bit] <= rx_sync;
                    rx_count <= CLKS_PER_BIT-1;
                    if (rx_bit == 7) rx_state <= 3;
                    else rx_bit <= rx_bit+1'b1;
                end else rx_count <= rx_count-1'b1;
                3: if (rx_count == 0) begin
                    if (rx_sync) begin
                        rx_byte <= rx_shift;
                        rx_byte_valid <= 1;
                    end
                    rx_state <= 0;
                end else rx_count <= rx_count-1'b1;
            endcase
        end
    end

    function [4:0] from_hex;
        input [7:0] c;
        begin
            if (c >= "0" && c <= "9") from_hex = {1'b0, c[3:0]};
            else if (c >= "A" && c <= "F") from_hex = {1'b0, c - "A" + 8'd10};
            else if (c >= "a" && c <= "f") from_hex = {1'b0, c - "a" + 8'd10};
            else from_hex = 5'b10000;
        end
    endfunction
    function [7:0] to_hex;
        input [3:0] n;
        begin to_hex = n < 10 ? "0" + n : "A" + n - 4'd10; end
    endfunction
    function valid_kind;
        input [7:0] k;
        begin
            valid_kind = k == "S" || k == "H" || k == "X" || k == "P" ||
                         k == "F" || k == "L" || k == "Q" || k == "E" || k == "B";
        end
    endfunction
    reg [2:0] parse_step;
    reg [7:0] parse_kind;
    reg [13:0] parse_addr;
    wire [4:0] parsed_hex = from_hex(rx_byte);
    reg waiting_rsp;
    reg [7:0] tx_kind;
    reg [13:0] tx_addr;
    reg [607:0] tx_data;
    reg [7:0] tx_step;
    reg [7:0] tx_digits;
    reg tx_busy;
    assign tx_valid = tx_busy;
    always @(*) begin
        tx_byte = 8'h20;
        if (tx_step == 0) tx_byte = "@";
        else if (tx_step == 1) tx_byte = tx_kind;
        else if (tx_step >= 2 && tx_step <= 5)
            tx_byte = to_hex(({2'b0, tx_addr} >> ((5-tx_step)*4)) & 4'hF);
        else if (tx_step == 6) tx_byte = "=";
        else if (tx_step < 7 + tx_digits)
            tx_byte = to_hex((tx_data >> ((tx_digits - 1 - (tx_step-7))*4)) & 4'hF);
        else if (tx_step == 7 + tx_digits) tx_byte = 8'h0D;
        else tx_byte = 8'h0A;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_step <= 0; parse_kind <= 0; parse_addr <= 0;
            req_toggle <= 0; req_kind <= 0; req_addr <= 0;
            waiting_rsp <= 0; tx_kind <= 0; tx_addr <= 0;
            tx_data <= 0; tx_step <= 0; tx_digits <= 0; tx_busy <= 0;
        end else begin
            if (rx_byte_valid) begin
                if (rx_byte == "?") parse_step <= 1;
                else if (parse_step == 1) begin
                    if (valid_kind(rx_byte)) begin
                        parse_kind <= rx_byte;
                        parse_addr <= 0;
                        parse_step <= 2;
                    end else parse_step <= 0;
                end else if (parse_step >= 2 && parse_step <= 5) begin
                    if (parsed_hex[4]) parse_step <= 0;
                    else begin
                        parse_addr <= {parse_addr[9:0], parsed_hex[3:0]};
                        parse_step <= parse_step + 1'b1;
                    end
                end else if (parse_step == 6) begin
                    parse_step <= 0;
                    if (rx_byte == 8'h0A && !waiting_rsp && !tx_busy) begin
                        req_kind <= parse_kind;
                        req_addr <= parse_addr;
                        req_toggle <= ~req_toggle;
                        waiting_rsp <= 1;
                    end
                end
            end
            if (rsp_update && waiting_rsp) begin
                tx_kind <= rsp_payload[629:622];
                tx_addr <= rsp_payload[621:608];
                tx_data <= rsp_payload[607:0];
                case (rsp_payload[629:622])
                    "S": tx_digits <= 12;
                    "H": tx_digits <= 152;
                    "X": tx_digits <= 19;
                    "P", "B": tx_digits <= 8;
                    "F", "L": tx_digits <= 3;
                    "Q": tx_digits <= 44;
                    "E": tx_digits <= 99;
                    default: tx_digits <= 1;
                endcase
                tx_step <= 0;
                tx_busy <= 1;
                waiting_rsp <= 0;
            end else if (tx_busy && tx_ready) begin
                if (tx_step == 8 + tx_digits) tx_busy <= 0;
                else tx_step <= tx_step + 1'b1;
            end
        end
    end
endmodule
