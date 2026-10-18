export interface Notes {
  time: string
  points: string[]
  qa: string[]
}

// ORDER MATCHES App.tsx slides[] array:
// [0]  Slide 1  — Project Overview
// [1]  Slide 2  — System Architecture
// [2]  Slide 8  — ITCH Parsing
// [3]  Slide 9  — LOB Engine
// [4]  Slide 10 — BBO Priority Tree
// [5]  Slide 3  — Timing Diagram
// [6]  Slide 11 — MUL Unit
// [7]  Slide 12 — DIV Unit
// [8]  Slide 4  — Design + Verification
// [9]  Slide 5  — Timeline
// [10] Slide 6  — Team
// [11] Slide 7  — Demo Plan

export const NOTES: Notes[] = [
  // [0] Project Overview
  {
    time: '1:00 - 1:30',
    points: [
      'Problem first: software order books take variable time per message.',
      'CPU is already built and verified. The new work is the hardware book.',
      'Walk the three scope tiers. Commitment is what we will certainly deliver.',
    ],
    qa: ['Why a softcore at all? It owns configuration, recovery and readout. Hot path is pure hardware.'],
  },
  // [1] System Architecture
  {
    time: '2:00',
    points: [
      'Left to right: network chain, then the book, then MMIO into the existing bus.',
      'Grey line-art boxes are existing and verified. Navy boxes are new.',
      'The CPU never sits in the per-message path. It only reads BBO through MMIO.',
    ],
    qa: [
      'Clock domains? 50 MHz Ethernet side, 100 MHz core, async FIFO between.',
      'Is the Ethernet part built? No. It is the stretch tier, stated honestly.',
    ],
  },
  // [2] ITCH Parsing
  {
    time: '1:30',
    points: [
      'Five pipeline stages: RMII RX (2-bit dibits) → Net Parser (Eth/IPv4/UDP) → MoldUDP64 → ITCH 5.0 → 256-bit canonical event.',
      'All five stages run at 50 MHz. Async FIFO bridges to the 100 MHz LOB core.',
      "Type 'A' Add Order byte layout: [0]=type, [5-10]=48-bit timestamp ns, [11-18]=OID, [24-27]=price.",
      'Division-free pidx: (price − base) × 274877907 >> 38. No divider needed in the 50 MHz domain.',
      'Canonical event carries 256 bits: version, opcode, side, OID, qty, pidx, timestamp.',
    ],
    qa: [
      'What is throughput? One 36-byte ITCH Add Order per ~3.7 µs at 100 Mbps.',
      'Why division-free? A fixed reciprocal shift-multiply avoids a slow divide unit on the 50 MHz Ethernet path.',
    ],
  },
  // [3] LOB Engine
  {
    time: '1:30',
    points: [
      'LOB core: 7 pipelined hardware modules — hash table → slot table → free list → price RAM → occupancy bitmaps → BBO engine → MMIO.',
      'Hash table: 1024 sets × 8 ways + 8-entry CAM stash. Set index = OID[9:0] XOR OID[19:10] XOR OID[29:20].',
      'ADD flow (6 cycles): pop free slot, write slot BRAM, update Price RAM bank, set occupancy bit, check BBO.',
      'Fail-stop policy: 9 error codes; hardware freezes on error; CPU reads REG_LOB_ERROR_CODE at 0x4000_0028.',
      'Resources: 37 BRAMs, 18 DSP48E1s, 20,604 LUTs, 35,347 registers on Artix-7.',
    ],
    qa: [
      'Can two events arrive simultaneously? No; the upstream async FIFO serialises them.',
      'How many orders? 2,048 active orders (slot table). Extendable with more BRAM.',
    ],
  },
  // [4] BBO Priority Tree
  {
    time: '1:30',
    points: [
      'Three-level hierarchy: L0 (8-bit master) → L1 (256-bit summary) → L2 (256×32-bit leaves) = 8,192 occupancy bits.',
      'Best Bid = leading-1 encoder on L0→L1→L2. Best Ask = trailing-1. O(1) regardless of book depth.',
      'Each level takes 1 cycle. Then 2-stage DSP48 gives final price = base + pidx × tick.',
      'Software equivalent would scan 8,192 levels — 273× slower than hardware.',
      'BBO update triggered on every event that changes qty at the best price level.',
    ],
    qa: [
      'What if no orders? L0 == 0; priority encoder outputs INVALID.',
      'Is BBO always coherent? Occupancy bits updated atomically before BBO re-search triggers.',
    ],
  },
  // [5] Timing Diagram
  {
    time: '2:00',
    points: [
      'This trace comes from cycle-accurate RTL simulation of cpu_core + interconnect + slaves.',
      'EX-to-EX Forwarding: T2, T8, T13, and T49 bypass RAW stalls directly into the ALU.',
      'Hazards: Load-ALU bubble at T12 (1 stall cycle) and branch squash at T15 (FLUSH).',
      'MUL completes in 4 cycles (T4–T7); Radix-2 DIV completes 33 cycles after its T15 launch, at T48.',
      'Cycle-by-cycle hardware signals match sim: stall_pipeline, m_busy, fwd selects, bus handshakes.',
    ],
    qa: [
      'Why 1-cycle bubble on load-use? DMEM data arrives in MEM/WB at T12, forwarded to EX at T13 for add x7.',
      'How does branch squashing work? beq evaluates in EX at T14; wrong +4 fetch (addi x8) is flushed at T15.',
      'Why does DIV take 33 cycles? The radix-2 divider uses 32 iterations plus 1 initialization cycle.',
    ],
  },
  // [6] MUL Unit
  {
    time: '1:30',
    points: [
      'DSP48E1 gives 3 fixed pipeline cycles: M1 (operand latch) → M2 (25×18 multiply core) → M3 (post-adder, PREG).',
      'Trace example: mul x3, x1, x2 with x1=7, x2=9 → x3=63 (0x0000003F).',
      'stall_pipeline asserted for 4 cycles (T4–T7). Skid buffer preserves add x4 decoded state.',
      'EX-to-EX forwarding at T8 supplies the product directly to add x4 without stalling.',
      '236 unit test vectors + 31 pipeline checks cover all four MUL variants and signed overflow.',
    ],
    qa: [
      'Why 4 stall cycles for a 3-cycle MUL? Result available at end of M3 (T7); consumer resumes T8.',
      'Does throughput suffer? Only with a RAW hazard on the result. Independent instructions could overlap.',
    ],
  },
  // [7] DIV Unit
  {
    time: '1:30',
    points: [
      'Radix-2 non-restoring serial divider: 32 bit-iterations + 1 init = 33 cycles from launch to completion.',
      'Trace: div x9, x4, x1 with x4=63, x1=7 → quotient=9, remainder=0. Launch T15; completion T48.',
      'Hardware: 32-bit shift register for partial remainder; 33-bit quotient accumulator; state counter FSM.',
      "Signed fixup: 2's complement pre-negation on dividend/divisor; sign-correct result.",
      'RISC-V spec edge cases hardwired: x/0 = −1, −2³¹ / −1 = −2³¹ rem=0.',
    ],
    qa: [
      'Why 33 and not 32 cycles? 32 bit-iterations plus 1 cycle to initialise the partial remainder register.',
      'Could you pipeline the divider? Yes (SRT), but 10–15× more LUTs and not needed for correctness.',
    ],
  },
  // [8] Design + Verification
  {
    time: '1:30 - 2:00',
    points: [
      'Each step ends in a testbench result, so progress is checkable.',
      'Golden model is the oracle for every hardware test.',
      'RV32M corner cases are already verified: 236 unit vectors, 31 pipeline checks.',
    ],
    qa: ['How do you know the LOB is right? Bit-exact BBO against the Python model on random streams.'],
  },
  // [9] Timeline
  {
    time: '1:00 - 1:30',
    points: [
      'Two hard dates: 25 Oct and 1 Nov. Both have a named, checkable deliverable.',
      'Dates are proposed by the team and need confirming against the course schedule.',
    ],
    qa: ['What slips first? The Ethernet stretch. The core demo does not depend on it.'],
  },
  // [10] Team
  {
    time: '1:00',
    points: [
      'Five owners matched directly to our Project Abstract.',
      'The right side shows the strict sequential execution order.',
    ],
    qa: [
      'Why is bus access collision-free? 4-state non-preemptive arbiter with wait-states and dual-port BRAM controllers.',
      'Who verifies? Each member owns standalone Verilog testbenches before main bus integration.',
    ],
  },
  // [11] Demo Plan
  {
    time: '1:00 - 1:30',
    points: [
      'Input, processing, output. Output is visible on the 7-segment display.',
      'Challenges are real ones: overflow, hash capacity, BBO consistency, 100 MHz timing.',
      'CPU has only ever run at 1 Hz on the board. 100 MHz is unproven on hardware.',
    ],
    qa: ['Why is timing a risk? Post-synthesis margin was +0.42 ns. Nothing routed at 100 MHz yet.'],
  },
]
