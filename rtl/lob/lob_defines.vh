// =============================================================================
// File: lob_defines.vh
// Description: Standard Verilog definitions header for Limit Order Book (LOB)
// Architecture Capacities, Bit-slices, Encodings, and Macros
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C (IEEE 1364-2001 Pure Verilog)
// Layouts here are mirrored by the Python packer in sim/golden and tools/.
// =============================================================================

`ifndef LOB_DEFINES_VH
`define LOB_DEFINES_VH

// -----------------------------------------------------------------------------
// Architecture Capacities and Parameters
// -----------------------------------------------------------------------------
`define EVT_VER                     4'h1
`define EVT_DATA_WIDTH              256

`define NUM_SLOTS                   2048
`define SLOT_ADDR_W                 11

`define HASH_SETS                   1024
`define HASH_SET_W                  10
`define HASH_WAYS                   8
`define HASH_WAY_W                  3
`define STASH_ENTRIES               8
`define STASH_ADDR_W                3

`define PRICE_LEVELS_PER_SIDE       8192
`define PRICE_INDEX_W               13
`define TOTAL_PRICE_LEVELS          16384
`define PRICE_ADDR_W                14

`define OCC_LEAF_WORDS              256
`define OCC_LEAF_ADDR_W             8
`define OCC_L1_BITS                 256
`define OCC_L0_BITS                 8

// -----------------------------------------------------------------------------
// Event Opcodes
// -----------------------------------------------------------------------------
`define OP_INVALID                  4'h0
`define OP_ADD                      4'h1
`define OP_EXECUTE                  4'h2
`define OP_CANCEL                   4'h3
`define OP_DELETE                   4'h4
`define OP_REPLACE                  4'h5

// -----------------------------------------------------------------------------
// Order Side
// -----------------------------------------------------------------------------
`define SIDE_BID                    1'b0
`define SIDE_ASK                    1'b1

// -----------------------------------------------------------------------------
// Error & Failure Codes (Fail-Stop Policy)
// -----------------------------------------------------------------------------
`define FAIL_NONE                   8'h00
`define FAIL_EVT_FORMAT             8'h01
`define FAIL_DUP_OID                8'h02
`define FAIL_MISSING_OID            8'h03
`define FAIL_NO_SLOT                8'h04
`define FAIL_HASH_FULL              8'h05
`define FAIL_QTY_OVF                8'h06
`define FAIL_QTY_UF                 8'h07
`define FAIL_PRICE_OOW              8'h08
`define FAIL_INVALID_OP             8'h09
`define FAIL_FEED_LOSS              8'h0A

// -----------------------------------------------------------------------------
// Canonical 256-bit Event Layout Bit-Slices
// -----------------------------------------------------------------------------
`define EVT_VER_SLICE               255:252
`define EVT_OP_SLICE                251:248
`define EVT_SIDE_BIT                247
`define EVT_RSVD1_SLICE             246:240
`define EVT_OID_SLICE               239:176
`define EVT_NOID_SLICE              175:112
`define EVT_SHARES_SLICE            111:80
`define EVT_PIDX_SLICE              79:67
`define EVT_OOW_BIT                 66
`define EVT_RSVD2_SLICE             65:64
`define EVT_SEQ_SLICE               63:32
`define EVT_RSVD3_SLICE             31:0

// -----------------------------------------------------------------------------
// Slot Table Entry (47 bits) Layout
// -----------------------------------------------------------------------------
`define SLOT_ENTRY_WIDTH            47
`define SLOT_VALID_BIT              46
`define SLOT_SIDE_BIT               45
`define SLOT_PIDX_SLICE             44:32
`define SLOT_SHARES_SLICE           31:0

// -----------------------------------------------------------------------------
// Hash Table Entry (76 bits) Layout
// -----------------------------------------------------------------------------
`define HASH_ENTRY_WIDTH            76
`define HASH_VALID_BIT              75
`define HASH_SLOT_SLICE             74:64
`define HASH_KEY_SLICE              63:0

// -----------------------------------------------------------------------------
// XOR-Folding Hash Function Macro
// -----------------------------------------------------------------------------
`define HASH_OID(oid) ( \
    (oid)[9:0]   ^ \
    (oid)[19:10] ^ \
    (oid)[29:20] ^ \
    (oid)[39:30] ^ \
    (oid)[49:40] ^ \
    (oid)[59:50] ^ \
    {6'b0, (oid)[63:60]} \
)

`endif // LOB_DEFINES_VH
