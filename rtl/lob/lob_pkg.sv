// =============================================================================
// File: lob_pkg.sv
// Description: Shared package for Hardware Limit Order Book (LOB) Accelerator
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md
// =============================================================================

package lob_pkg;

    // -------------------------------------------------------------------------
    // Architecture Capacities and Parameters
    // -------------------------------------------------------------------------
    localparam int unsigned EVT_VER                 = 4'h1;
    localparam int unsigned EVT_DATA_WIDTH          = 256;

    localparam int unsigned NUM_SLOTS               = 2048;
    localparam int unsigned SLOT_ADDR_W             = 11;

    localparam int unsigned HASH_SETS               = 1024;
    localparam int unsigned HASH_SET_W              = 10;
    localparam int unsigned HASH_WAYS               = 8;
    localparam int unsigned HASH_WAY_W              = 3;
    localparam int unsigned STASH_ENTRIES           = 8;
    localparam int unsigned STASH_ADDR_W            = 3;

    localparam int unsigned PRICE_LEVELS_PER_SIDE   = 8192;
    localparam int unsigned PRICE_INDEX_W           = 13;
    localparam int unsigned TOTAL_PRICE_LEVELS      = 16384;
    localparam int unsigned PRICE_ADDR_W            = 14;

    localparam int unsigned OCC_LEAF_WORDS          = 256;
    localparam int unsigned OCC_LEAF_ADDR_W         = 8;
    localparam int unsigned OCC_L1_BITS             = 256;
    localparam int unsigned OCC_L0_BITS             = 8;

    // -------------------------------------------------------------------------
    // Event Opcodes
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        OP_INVALID = 4'h0,
        OP_ADD     = 4'h1,
        OP_EXECUTE = 4'h2,
        OP_CANCEL  = 4'h3,
        OP_DELETE  = 4'h4,
        OP_REPLACE = 4'h5
    } opcode_t;

    // -------------------------------------------------------------------------
    // Order Side
    // -------------------------------------------------------------------------
    typedef enum logic {
        SIDE_BID = 1'b0,
        SIDE_ASK = 1'b1
    } side_t;

    // -------------------------------------------------------------------------
    // Error & Failure Codes (Fail-Stop Policy)
    // -------------------------------------------------------------------------
    typedef enum logic [7:0] {
        FAIL_NONE        = 8'h00,
        FAIL_EVT_FORMAT  = 8'h01,
        FAIL_DUP_OID     = 8'h02,
        FAIL_MISSING_OID = 8'h03,
        FAIL_NO_SLOT     = 8'h04,
        FAIL_HASH_FULL   = 8'h05,
        FAIL_QTY_OVF     = 8'h06,
        FAIL_QTY_UF      = 8'h07,
        FAIL_PRICE_OOW   = 8'h08,
        FAIL_INVALID_OP  = 8'h09
    } err_code_t;

    // -------------------------------------------------------------------------
    // Canonical 256-bit Event Layout (v7 §10)
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [3:0]   ver;     // [255:252] Event schema version (must be 4'h1)
        logic [3:0]   op;      // [251:248] 1=ADD, 2=EXEC, 3=CANCEL, 4=DELETE, 5=REPLACE
        logic         side;    // [247]     0=Bid, 1=Ask (ADD only)
        logic [6:0]   rsvd1;   // [246:240] Must be 7'b0
        logic [63:0]  oid;     // [239:176] 64-bit order ID
        logic [63:0]  noid;    // [175:112] 64-bit new order ID (REPLACE only)
        logic [31:0]  shares;  // [111:80]  Shares quantity
        logic [12:0]  pidx;    // [79:67]   13-bit normalized price index (0..8191)
        logic         oow;     // [66]      Price out-of-window flag
        logic [1:0]   rsvd2;   // [65:64]   Must be 2'b0
        logic [31:0]  seq;     // [63:32]   MoldUDP64 32-bit sequence number
        logic [31:0]  rsvd3;   // [31:0]    Must be 32'b0
    } canonical_event_t;

    // -------------------------------------------------------------------------
    // Slot Table Entry (47 bits)
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;   // [46]
        logic        side;    // [45]
        logic [12:0] pidx;    // [44:32]
        logic [31:0] shares;  // [31:0]
    } slot_entry_t;

    // -------------------------------------------------------------------------
    // Hash Table Entry (76 bits)
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;   // [75]
        logic [10:0] slot;    // [74:64]
        logic [63:0] key;     // [63:0]
    } hash_entry_t;

    // -------------------------------------------------------------------------
    // XOR-Folding Hash Function (v7 §12)
    // -------------------------------------------------------------------------
    function automatic logic [9:0] hash_oid(input logic [63:0] oid);
        return oid[9:0]   ^
               oid[19:10] ^
               oid[29:20] ^
               oid[39:30] ^
               oid[49:40] ^
               oid[59:50] ^
               {6'b0, oid[63:60]};
    endfunction

endpackage: lob_pkg
