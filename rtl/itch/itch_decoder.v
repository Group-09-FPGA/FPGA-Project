`timescale 1ns / 1ps
`include "lob_defines.vh"

// One message is buffered while a bounded, sequential price conversion runs.
// The output valid flag is held until the event FIFO accepts the result.
module itch_decoder #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK = 32'd1000,
    parameter [15:0] DEFAULT_LOCATE = 16'd1
) (
    input wire clk, rst_n,
    input wire itch_msg_valid,
    input wire [15:0] itch_msg_len,
    input wire [7:0] itch_msg_byte,
    input wire [63:0] itch_msg_seq,
    input wire itch_msg_start, itch_msg_last,
    output wire itch_msg_ready,
    input wire [15:0] cfg_stock_locate,
    input wire [31:0] cfg_price_base, cfg_tick,
    output reg canon_event_valid,
    output reg [255:0] canon_event_data,
    input wire canon_event_ready,
    output reg decode_error,
    output reg [31:0] cnt_itch_total_msgs,
    output reg [31:0] cnt_itch_order_events,
    output reg [31:0] cnt_itch_filtered_msgs,
    output reg [31:0] cnt_itch_admin_msgs,
    output reg [31:0] cnt_itch_oow_events
);
    localparam [1:0] COLLECT=0, DECODE=1, DIVIDE=2, SEND=3;
    reg [1:0] state;
    assign itch_msg_ready = state == COLLECT;
    wire [15:0] locate = cfg_stock_locate != 0 ? cfg_stock_locate : DEFAULT_LOCATE;
    wire [31:0] base = cfg_price_base != 0 ? cfg_price_base : DEFAULT_PRICE_BASE;
    wire [31:0] tick = cfg_tick != 0 ? cfg_tick : DEFAULT_TICK;

    reg [7:0] msg_buffer [0:47];
    reg [15:0] length, count;
    reg [63:0] msg_sequence;
    reg [7:0] msg_type;
    reg [15:0] msg_locate;
    reg [255:0] pending;
    reg [31:0] dividend, divisor, quotient;
    reg [32:0] remainder;
    reg [5:0] steps;
    wire [32:0] trial = {remainder[31:0], dividend[31]};
    wire take = trial >= {1'b0, divisor};
    wire [32:0] remainder_next = take ? trial - {1'b0, divisor} : trial;
    wire [31:0] quotient_next = {quotient[30:0], take};

    reg [63:0] oid, noid;
    reg [31:0] shares, price;
    reg side, known_type, priced_type;
    reg [7:0] expected_length;
    reg malformed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= COLLECT;
            length <= 0; count <= 0; msg_sequence <= 0;
            msg_type <= 0; msg_locate <= 0;
            pending <= 0; dividend <= 0; divisor <= 1;
            quotient <= 0; remainder <= 0; steps <= 0;
            canon_event_valid <= 0; canon_event_data <= 0; decode_error <= 0;
            cnt_itch_total_msgs <= 0; cnt_itch_order_events <= 0;
            cnt_itch_filtered_msgs <= 0; cnt_itch_admin_msgs <= 0;
            cnt_itch_oow_events <= 0;
        end else case (state)
            COLLECT: if (itch_msg_valid) begin
                if (itch_msg_start) begin
                    msg_sequence <= itch_msg_seq;
                    length <= itch_msg_len;
                    count <= 16'd1;
                    msg_buffer[0] <= itch_msg_byte;
                end else begin
                    if (count < 16'd48) msg_buffer[count[5:0]] <= itch_msg_byte;
                    count <= count + 16'd1;
                end
                if (itch_msg_last) begin
                    cnt_itch_total_msgs <= cnt_itch_total_msgs + 1'b1;
                    state <= DECODE;
                end
            end

            DECODE: begin
                msg_type <= msg_buffer[0];
                msg_locate <= {msg_buffer[1],msg_buffer[2]};
                oid = {msg_buffer[11],msg_buffer[12],msg_buffer[13],msg_buffer[14],msg_buffer[15],msg_buffer[16],msg_buffer[17],msg_buffer[18]};
                noid = 0; shares = 0; price = 0; side = 0;
                known_type = 1; priced_type = 0; expected_length = 0;
                case (msg_buffer[0])
                    "A", "F": begin
                        expected_length = msg_buffer[0] == "A" ? 8'd36 : 8'd40;
                        side = msg_buffer[19] == "S";
                        shares = {msg_buffer[20],msg_buffer[21],msg_buffer[22],msg_buffer[23]};
                        price = {msg_buffer[32],msg_buffer[33],msg_buffer[34],msg_buffer[35]};
                        priced_type = 1;
                    end
                    "E", "C": begin
                        expected_length = msg_buffer[0] == "E" ? 8'd31 : 8'd36;
                        shares = {msg_buffer[19],msg_buffer[20],msg_buffer[21],msg_buffer[22]};
                    end
                    "X": begin
                        expected_length = 8'd23;
                        shares = {msg_buffer[19],msg_buffer[20],msg_buffer[21],msg_buffer[22]};
                    end
                    "D": expected_length = 8'd19;
                    "U": begin
                        expected_length = 8'd35;
                        noid = {msg_buffer[19],msg_buffer[20],msg_buffer[21],msg_buffer[22],msg_buffer[23],msg_buffer[24],msg_buffer[25],msg_buffer[26]};
                        shares = {msg_buffer[27],msg_buffer[28],msg_buffer[29],msg_buffer[30]};
                        price = {msg_buffer[31],msg_buffer[32],msg_buffer[33],msg_buffer[34]};
                        priced_type = 1;
                    end
                    default: known_type = 0;
                endcase
                malformed = count != length ||
                    (known_type && length != {8'd0,expected_length}) ||
                    ((msg_buffer[0] == "A" || msg_buffer[0] == "F") &&
                     msg_buffer[19] != "B" && msg_buffer[19] != "S");
                if (malformed) begin
                    decode_error <= 1;
                    state <= COLLECT;
                end else if (!known_type) begin
                    cnt_itch_admin_msgs <= cnt_itch_admin_msgs + 1'b1;
                    state <= COLLECT;
                end else if ({msg_buffer[1],msg_buffer[2]} != locate) begin
                    cnt_itch_filtered_msgs <= cnt_itch_filtered_msgs + 1'b1;
                    state <= COLLECT;
                end else begin
                    case (msg_buffer[0])
                        "A", "F": pending <= {4'h1,`OP_ADD,side,7'd0,oid,64'd0,shares,
                                              13'd0,1'b0,2'd0,msg_sequence[31:0],32'd0};
                        "E", "C": pending <= {4'h1,`OP_EXECUTE,1'b0,7'd0,oid,64'd0,shares,
                                              13'd0,1'b0,2'd0,msg_sequence[31:0],32'd0};
                        "X": pending <= {4'h1,`OP_CANCEL,1'b0,7'd0,oid,64'd0,shares,
                                         13'd0,1'b0,2'd0,msg_sequence[31:0],32'd0};
                        "D": pending <= {4'h1,`OP_DELETE,1'b0,7'd0,oid,64'd0,32'd0,
                                         13'd0,1'b0,2'd0,msg_sequence[31:0],32'd0};
                        "U": pending <= {4'h1,`OP_REPLACE,1'b0,7'd0,oid,noid,shares,
                                         13'd0,1'b0,2'd0,msg_sequence[31:0],32'd0};
                        default: pending <= 0;
                    endcase
                    cnt_itch_order_events <= cnt_itch_order_events + 1'b1;
                    if (priced_type) begin
                        dividend <= price < base ? 0 : price - base;
                        divisor <= price < base ? 0 : tick;
                        quotient <= 0; remainder <= 0; steps <= 0;
                        state <= DIVIDE;
                    end else state <= SEND;
                end
            end

            DIVIDE: if (divisor == 0) begin
                canon_event_data <= {pending[255:67],1'b1,pending[65:0]};
                cnt_itch_oow_events <= cnt_itch_oow_events + 1'b1;
                canon_event_valid <= 1;
                state <= SEND;
            end else begin
                dividend <= {dividend[30:0],1'b0};
                quotient <= quotient_next;
                remainder <= remainder_next;
                steps <= steps + 1'b1;
                if (steps == 6'd31) begin
                    canon_event_data <= {pending[255:80],quotient_next[12:0],
                        (remainder_next != 0 || quotient_next >= 32'd8192),pending[65:0]};
                    if (remainder_next != 0 || quotient_next >= 32'd8192)
                        cnt_itch_oow_events <= cnt_itch_oow_events + 1'b1;
                    canon_event_valid <= 1;
                    state <= SEND;
                end
            end

            SEND: if (!canon_event_valid) begin
                canon_event_data <= pending;
                canon_event_valid <= 1;
            end else if (canon_event_ready) begin
                canon_event_valid <= 0;
                state <= COLLECT;
            end
            default: state <= COLLECT;
        endcase
    end
endmodule
