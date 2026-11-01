// Board-owned history for VGA: 128 quote samples and 256 storage events.
// The read clock may be the 25 MHz VGA clock; writes use the 50 MHz core clock.
`timescale 1ns / 1ps

module lob_display_journal (
    input  wire         core_clk,
    input  wire         core_rst_n,
    input  wire         event_done,
    input  wire [31:0]  completed_count,
    input  wire [315:0] storage_trace,
    input  wire         book_valid,
    input  wire         bid_valid,
    input  wire [31:0]  bid_price,
    input  wire [31:0]  bid_qty,
    input  wire         ask_valid,
    input  wire [31:0]  ask_price,
    input  wire [31:0]  ask_qty,
    input  wire [11:0]  active_orders,
    input  wire         read_clk,
    input  wire [6:0]   quote_read_addr,
    output reg  [174:0] quote_read_data,
    input  wire [7:0]   event_read_addr,
    output reg  [347:0] event_read_data,
    output reg  [7:0]   quote_count,
    output reg  [8:0]   event_count,
    output reg  [6:0]   quote_next,
    output reg  [7:0]   event_next
);
    // Same 175-bit layout as the existing VGA BBO snapshot, event number last.
    (* ram_style = "block" *) reg [174:0] quote_mem [0:127];
    // 32-bit event number + 316-bit committed storage trace.
    (* ram_style = "block" *) reg [347:0] event_mem [0:255];

    // Core completion precedes the final BBO settling. The trace becomes
    // stable on the next edge; quote values are sampled eight edges later.
    reg [7:0] done_pipe;
    reg [31:0] seq_pipe [0:7];
    always @(posedge core_clk) begin
        if (core_rst_n && done_pipe[1])
            event_mem[event_next] <= {seq_pipe[1], storage_trace};
        if (core_rst_n && done_pipe[7])
            quote_mem[quote_next] <= {book_valid, bid_valid,
                bid_price, bid_qty, ask_valid, ask_price, ask_qty,
                active_orders, seq_pipe[7]};
    end
    integer i;
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            done_pipe <= 8'd0;
            for (i = 0; i < 8; i = i + 1)
                seq_pipe[i] <= 32'd0;
            quote_count <= 8'd0;
            event_count <= 9'd0;
            quote_next <= 7'd0;
            event_next <= 8'd0;
        end else begin
            done_pipe <= {done_pipe[6:0], event_done};
            seq_pipe[0] <= completed_count + 32'd1;
            for (i = 1; i < 8; i = i + 1)
                seq_pipe[i] <= seq_pipe[i-1];
            if (done_pipe[1]) begin
                event_next <= event_next + 8'd1;
                if (event_count < 9'd256)
                    event_count <= event_count + 9'd1;
            end
            if (done_pipe[7]) begin
                quote_next <= quote_next + 7'd1;
                if (quote_count < 8'd128)
                    quote_count <= quote_count + 8'd1;
            end
        end
    end

    always @(posedge read_clk) begin
        quote_read_data <= quote_mem[quote_read_addr];
        event_read_data <= event_mem[event_read_addr];
    end
endmodule
