// =============================================================================
// File: tb_lob_event_decoder.v
// Description: Unit testbench for canonical event decoder and validation (Verilog-2001)
// =============================================================================

`timescale 1ns / 1ps

`include "lob_defines.vh"

module tb_lob_event_decoder;

    reg  [255:0] raw_event;
    wire [255:0] decoded_evt;
    wire         evt_valid;
    wire         evt_error;
    wire [7:0]   error_code;
    wire         is_add, is_exec, is_cancel, is_delete, is_replace, price_oow;

    lob_event_decoder dut (
        .raw_event(raw_event),
        .decoded_evt(decoded_evt),
        .evt_valid(evt_valid),
        .evt_error(evt_error),
        .error_code(error_code),
        .is_add(is_add),
        .is_exec(is_exec),
        .is_cancel(is_cancel),
        .is_delete(is_delete),
        .is_replace(is_replace),
        .price_oow(price_oow)
    );

    integer test_count;
    integer pass_count;

    task check;
        input [255:0] test_name;
        input cond;
        begin
            test_count = test_count + 1;
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end else begin
                $display("[FAIL] %0s (valid=%b, err=%b, code=0x%02h)", test_name, evt_valid, evt_error, error_code);
            end
        end
    endtask

    function [255:0] make_event;
        input [3:0]   ver;
        input [3:0]   op;
        input         side;
        input [6:0]   rsvd1;
        input [63:0]  oid;
        input [63:0]  noid;
        input [31:0]  shares;
        input [12:0]  pidx;
        input         oow;
        input [1:0]   rsvd2;
        input [31:0]  seq;
        input [31:0]  rsvd3;
        begin
            make_event = {ver, op, side, rsvd1, oid, noid, shares, pidx, oow, rsvd2, seq, rsvd3};
        end
    endfunction

    wire [63:0] dec_oid = decoded_evt[239:176];

    initial begin
        test_count = 0;
        pass_count = 0;
        $display("=== Starting tb_lob_event_decoder ===");

        // Test 1: Valid ADD Event
        raw_event = make_event(4'h1, `OP_ADD, `SIDE_BID, 7'd0, 64'd101, 64'd0, 32'd500, 13'd120, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Valid ADD event decoded", evt_valid && !evt_error && is_add && (dec_oid == 64'd101));

        // Test 2: Invalid Version
        raw_event = make_event(4'h2, `OP_ADD, `SIDE_BID, 7'd0, 64'd101, 64'd0, 32'd500, 13'd120, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Invalid version triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 3: Reserved bit non-zero
        raw_event = make_event(4'h1, `OP_ADD, `SIDE_BID, 7'h1, 64'd101, 64'd0, 32'd500, 13'd120, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Non-zero rsvd1 triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 4: ADD with 0 shares
        raw_event = make_event(4'h1, `OP_ADD, `SIDE_BID, 7'd0, 64'd101, 64'd0, 32'd0, 13'd120, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Zero shares triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 5: Valid EXECUTE
        raw_event = make_event(4'h1, `OP_EXECUTE, 1'b0, 7'd0, 64'd101, 64'd0, 32'd200, 13'd0, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Valid EXECUTE decoded", evt_valid && !evt_error && is_exec);

        // Test 6: EXECUTE with non-zero pidx should fail
        raw_event = make_event(4'h1, `OP_EXECUTE, 1'b0, 7'd0, 64'd101, 64'd0, 32'd200, 13'd10, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("EXECUTE with non-zero pidx rejected", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 7: Valid DELETE (shares must be 0)
        raw_event = make_event(4'h1, `OP_DELETE, 1'b0, 7'd0, 64'd101, 64'd0, 32'd0, 13'd0, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Valid DELETE decoded", evt_valid && !evt_error && is_delete);

        // Test 8: DELETE with shares > 0 should fail
        raw_event = make_event(4'h1, `OP_DELETE, 1'b0, 7'd0, 64'd101, 64'd0, 32'd50, 13'd0, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("DELETE with shares > 0 rejected", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 9: Valid REPLACE
        raw_event = make_event(4'h1, `OP_REPLACE, 1'b0, 7'd0, 64'd101, 64'd102, 32'd300, 13'd150, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Valid REPLACE decoded", evt_valid && !evt_error && is_replace);

        // Test 10: REPLACE with noid == 0 should fail
        raw_event = make_event(4'h1, `OP_REPLACE, 1'b0, 7'd0, 64'd101, 64'd0, 32'd300, 13'd150, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("REPLACE with noid==0 rejected", !evt_valid && evt_error && (error_code == `FAIL_EVT_FORMAT));

        // Test 11: Invalid opcode
        raw_event = make_event(4'h1, 4'h9, 1'b0, 7'd0, 64'd101, 64'd0, 32'd300, 13'd150, 1'b0, 2'd0, 32'd1, 32'd0);
        #1;
        check("Invalid opcode triggers FAIL_INVALID_OP", !evt_valid && evt_error && (error_code == `FAIL_INVALID_OP));

        $display("tb_lob_event_decoder: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) begin
            $display("Test failures detected!");
            $finish(1);
        end
        $finish;
    end

endmodule
