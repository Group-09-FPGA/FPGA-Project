// =============================================================================
// File: lob_event_decoder.sv
// Description: Canonical event decoder and validation engine
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §10
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_event_decoder (
    input  logic [255:0]     raw_event,

    output canonical_event_t decoded_evt,
    output logic             evt_valid,
    output logic             evt_error,
    output err_code_t        error_code,

    output logic             is_add,
    output logic             is_exec,
    output logic             is_cancel,
    output logic             is_delete,
    output logic             is_replace,
    output logic             price_oow
);

    canonical_event_t evt;
    assign evt = canonical_event_t'(raw_event);
    assign decoded_evt = evt;

    logic ver_ok;
    logic rsvd_ok;
    logic op_legal;

    assign ver_ok    = (evt.ver == EVT_VER);
    assign rsvd_ok   = (evt.rsvd1 == 7'b0) && (evt.rsvd2 == 2'b0) && (evt.rsvd3 == 32'b0);
    assign op_legal  = (evt.op >= 4'h1) && (evt.op <= 4'h5);

    assign is_add     = (evt.op == OP_ADD);
    assign is_exec    = (evt.op == OP_EXECUTE);
    assign is_cancel  = (evt.op == OP_CANCEL);
    assign is_delete  = (evt.op == OP_DELETE);
    assign is_replace = (evt.op == OP_REPLACE);
    assign price_oow  = evt.oow;

    always_comb begin
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
            case (evt.op)
                OP_ADD: begin
                    // ADD requires: oid != 0, shares >= 1, noid == 0.
                    // If oow == 1, pidx must be 0; if !oow, pidx < PRICE_LEVELS_PER_SIDE (13b covers 0..8191)
                    if (evt.oid == 64'd0 || evt.shares == 32'd0 || evt.noid != 64'd0 || (evt.oow && evt.pidx != 13'd0)) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_EXECUTE, OP_CANCEL: begin
                    // EXEC / CANCEL require: oid != 0, shares >= 1, noid == 0, pidx == 0, side == 0, oow == 0
                    if (evt.oid == 64'd0 || evt.shares == 32'd0 || evt.noid != 64'd0 ||
                        evt.pidx != 13'd0 || evt.side != 1'b0 || evt.oow != 1'b0) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_DELETE: begin
                    // DELETE requires: oid != 0, shares == 0, noid == 0, pidx == 0, side == 0, oow == 0
                    if (evt.oid == 64'd0 || evt.shares != 32'd0 || evt.noid != 64'd0 ||
                        evt.pidx != 13'd0 || evt.side != 1'b0 || evt.oow != 1'b0) begin
                        evt_error  = 1'b1;
                        error_code = FAIL_EVT_FORMAT;
                    end else begin
                        evt_valid  = 1'b1;
                    end
                end

                OP_REPLACE: begin
                    // REPLACE requires: oid != 0, noid != 0, shares >= 1, side == 0.
                    // If oow == 1, pidx must be 0.
                    if (evt.oid == 64'd0 || evt.noid == 64'd0 || evt.shares == 32'd0 ||
                        evt.side != 1'b0 || (evt.oow && evt.pidx != 13'd0)) begin
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
