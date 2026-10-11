// =============================================================================
// File: tb_lob_event_decoder.sv
// Description: Unit testbench for canonical event decoder and validation
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_event_decoder;

    logic [255:0]     raw_event;
    canonical_event_t decoded_evt;
    logic             evt_valid;
    logic             evt_error;
    err_code_t        error_code;
    logic             is_add, is_exec, is_cancel, is_delete, is_replace, price_oow;

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

    int test_count = 0;
    int pass_count = 0;

    task check(input string test_name, input logic cond);
        test_count++;
        if (cond) begin
            pass_count++;
            $display("[PASS] %s", test_name);
        end else begin
            $display("[FAIL] %s (valid=%b, err=%b, code=0x%02h)", test_name, evt_valid, evt_error, error_code);
        end
    endtask

    canonical_event_t test_evt;

    initial begin
        $display("=== Starting tb_lob_event_decoder ===");

        // Test 1: Valid ADD Event
        test_evt = '0;
        test_evt.ver = 4'h1;
        test_evt.op = 4'h1; // ADD
        test_evt.side = 1'b0; // BID
        test_evt.oid = 64'd101;
        test_evt.shares = 32'd500;
        test_evt.pidx = 13'd120;
        test_evt.seq = 32'd1;
        raw_event = test_evt;
        #1;
        check("Valid ADD event decoded", evt_valid && !evt_error && is_add && decoded_evt.oid == 64'd101);

        // Test 2: Invalid Version
        test_evt.ver = 4'h2;
        raw_event = test_evt;
        #1;
        check("Invalid version triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);

        // Test 3: Reserved bit non-zero
        test_evt.ver = 4'h1;
        test_evt.rsvd1 = 7'h1;
        raw_event = test_evt;
        #1;
        check("Non-zero rsvd1 triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);
        test_evt.rsvd1 = 7'h0;

        // Test 4: ADD with 0 shares
        test_evt.shares = 32'd0;
        raw_event = test_evt;
        #1;
        check("Zero shares triggers FAIL_EVT_FORMAT", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);
        test_evt.shares = 32'd100;

        // Test 5: Valid EXECUTE
        test_evt = '0;
        test_evt.ver = 4'h1;
        test_evt.op = 4'h2; // EXECUTE
        test_evt.oid = 64'd101;
        test_evt.shares = 32'd200;
        raw_event = test_evt;
        #1;
        check("Valid EXECUTE decoded", evt_valid && !evt_error && is_exec);

        // Test 6: EXECUTE with non-zero pidx should fail
        test_evt.pidx = 13'd10;
        raw_event = test_evt;
        #1;
        check("EXECUTE with non-zero pidx rejected", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);
        test_evt.pidx = 13'd0;

        // Test 7: Valid DELETE (shares must be 0)
        test_evt = '0;
        test_evt.ver = 4'h1;
        test_evt.op = 4'h4; // DELETE
        test_evt.oid = 64'd101;
        test_evt.shares = 32'd0;
        raw_event = test_evt;
        #1;
        check("Valid DELETE decoded", evt_valid && !evt_error && is_delete);

        // Test 8: DELETE with shares > 0 should fail
        test_evt.shares = 32'd50;
        raw_event = test_evt;
        #1;
        check("DELETE with shares > 0 rejected", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);

        // Test 9: Valid REPLACE
        test_evt = '0;
        test_evt.ver = 4'h1;
        test_evt.op = 4'h5; // REPLACE
        test_evt.oid = 64'd101;
        test_evt.noid = 64'd102;
        test_evt.shares = 32'd300;
        test_evt.pidx = 13'd150;
        raw_event = test_evt;
        #1;
        check("Valid REPLACE decoded", evt_valid && !evt_error && is_replace);

        // Test 10: REPLACE with noid == 0 should fail
        test_evt.noid = 64'd0;
        raw_event = test_evt;
        #1;
        check("REPLACE with noid==0 rejected", !evt_valid && evt_error && error_code == FAIL_EVT_FORMAT);

        // Test 11: Invalid opcode
        test_evt.op = 4'h9;
        raw_event = test_evt;
        #1;
        check("Invalid opcode triggers FAIL_INVALID_OP", !evt_valid && evt_error && error_code == FAIL_INVALID_OP);

        $display("tb_lob_event_decoder: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
