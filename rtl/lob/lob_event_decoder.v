// Canonical event decoder and validation engine
// See docs/rtl_reference.md for how this block fits in the LOB.

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_event_decoder (
    input  wire [255:0] raw_event,

    output wire [255:0] decoded_evt,
    output reg          evt_valid,
    output reg          evt_error,
    output reg  [7:0]   error_code,

    output wire         is_add,
    output wire         is_exec,
    output wire         is_cancel,
    output wire         is_delete,
    output wire         is_replace,
    output wire         price_oow
);

    localparam [3:0] OP_INVALID = `OP_INVALID;
    localparam [3:0] OP_ADD     = `OP_ADD;
    localparam [3:0] OP_EXECUTE = `OP_EXECUTE;
    localparam [3:0] OP_CANCEL  = `OP_CANCEL;
    localparam [3:0] OP_DELETE  = `OP_DELETE;
    localparam [3:0] OP_REPLACE = `OP_REPLACE;

    localparam [7:0] FAIL_NONE       = `FAIL_NONE;
    localparam [7:0] FAIL_EVT_FORMAT = `FAIL_EVT_FORMAT;
    localparam [7:0] FAIL_INVALID_OP = `FAIL_INVALID_OP;

    assign decoded_evt = raw_event;

    wire [3:0]  evt_ver    = raw_event[`EVT_VER_SLICE];
    wire [3:0]  evt_op     = raw_event[`EVT_OP_SLICE];
    wire        evt_side   = raw_event[`EVT_SIDE_BIT];
    wire [6:0]  evt_rsvd1  = raw_event[`EVT_RSVD1_SLICE];
    wire [63:0] evt_oid    = raw_event[`EVT_OID_SLICE];
    wire [63:0] evt_noid   = raw_event[`EVT_NOID_SLICE];
    wire [31:0] evt_shares = raw_event[`EVT_SHARES_SLICE];
    wire [12:0] evt_pidx   = raw_event[`EVT_PIDX_SLICE];
    wire        evt_oow    = raw_event[`EVT_OOW_BIT];
    wire [1:0]  evt_rsvd2  = raw_event[`EVT_RSVD2_SLICE];
    wire [31:0] evt_seq    = raw_event[`EVT_SEQ_SLICE];
    wire [31:0] evt_rsvd3  = raw_event[`EVT_RSVD3_SLICE];

    wire ver_ok   = (evt_ver == `EVT_VER);
    wire rsvd_ok  = (evt_rsvd1 == 7'b0) && (evt_rsvd2 == 2'b0) && (evt_rsvd3 == 32'b0);
    wire op_legal = (evt_op >= 4'h1) && (evt_op <= 4'h5);

    assign is_add     = (evt_op == OP_ADD);
    assign is_exec    = (evt_op == OP_EXECUTE);
    assign is_cancel  = (evt_op == OP_CANCEL);
    assign is_delete  = (evt_op == OP_DELETE);
    assign is_replace = (evt_op == OP_REPLACE);
    assign price_oow  = evt_oow;

    always @* begin
        evt_valid  = 1'b0;
        evt_error  = 1'b0;
        error_code = FAIL_NONE;

        if (!ver_ok || !rsvd_ok) begin
            evt_error  = 1'b1;
            error_code = FAIL_EVT_FORMAT;
        end else if (!op_legal) begin
            evt_error  = 1'b1;
            error_code = FAIL_INVALID_OP;
        end else begin
            case (evt_op)
                OP_ADD: begin
                    // ADD requires: oid != 0, shares >= 1, noid == 0.
                    // If oow == 1, pidx must be 0; if !oow, pidx < PRICE_LEVELS_PER_SIDE (13b covers 0..8191)
                    if (evt_oid == 64'd0 || evt_shares == 32'd0 || evt_noid != 64'd0 || (evt_oow && evt_pidx != 13'd0)) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_EXECUTE, OP_CANCEL: begin
                    // EXEC / CANCEL require: oid != 0, shares >= 1, noid == 0, pidx == 0, side == 0, oow == 0
                    if (evt_oid == 64'd0 || evt_shares == 32'd0 || evt_noid != 64'd0 ||
                        evt_pidx != 13'd0 || evt_side != 1'b0 || evt_oow != 1'b0) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_DELETE: begin
                    // DELETE requires: oid != 0, shares == 0, noid == 0, pidx == 0, side == 0, oow == 0
                    if (evt_oid == 64'd0 || evt_shares != 32'd0 || evt_noid != 64'd0 ||
                        evt_pidx != 13'd0 || evt_side != 1'b0 || evt_oow != 1'b0) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_REPLACE: begin
                    // REPLACE requires: oid != 0, noid != 0, shares >= 1, side == 0.
                    // If oow == 1, pidx must be 0.
                    if (evt_oid == 64'd0 || evt_noid == 64'd0 || evt_shares == 32'd0 ||
                        evt_side != 1'b0 || (evt_oow && evt_pidx != 13'd0)) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                default: begin
                    evt_error  = 1'b1;
                    error_code = FAIL_INVALID_OP;
                end
            endcase
        end
    end

endmodule
