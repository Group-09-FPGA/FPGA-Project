export interface Notes {
  time: string
  points: string[]
  qa: string[]
}

export const NOTES: Notes[] = [
  {
    time: '1:00 - 1:30',
    points: [
      'Problem first: software order books take variable time per message.',
      'CPU is already built and verified. The new work is the hardware book.',
      'Walk the three scope tiers. Commitment is what we will certainly deliver.',
    ],
    qa: ['Why a softcore at all? It owns configuration, recovery and readout. Hot path is pure hardware.'],
  },
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
  {
    time: '2:00',
    points: [
      'This trace comes from cycle-accurate RTL simulation of cpu_core + interconnect + slaves.',
      'EX-to-EX Forwarding: T2, T8, T13, and T55 bypass RAW stalls directly into the ALU.',
      'Hazards: Load-ALU bubble at T12 (1 stall cycle) and branch squash at T15 (FLUSH).',
      'Multi-Cycle RV32M: MUL completes in 4 cycles; Radix-2 DIV computes over 34 cycles (33 stall cycles).',
      'Cycle-by-cycle hardware control signals match sim: stall_pipeline, m_busy, fwd selects, bus handshakes.',
    ],
    qa: [
      'Why a 1-cycle bubble on load-use? Data from DMEM arrives in MEM/WB at T12, forwarded to EX at T13 for add x7.',
      'How does branch squashing work? beq evaluates in EX at T14; wrong +4 fetch (addi x8) is flushed at T15 as target (div x9) is fetched.',
      'Why does DIV take 34 cycles? 32-iteration restoring/radix-2 divider computes while frontend is held in skid buffer.',
    ],
  },
  {
    time: '1:30 - 2:00',
    points: [
      'Each step ends in a testbench result, so progress is checkable.',
      'Golden model is the oracle for every hardware test.',
      'RV32M corner cases are already verified: 236 unit vectors, 31 pipeline checks.',
    ],
    qa: ['How do you know the LOB is right? Bit-exact BBO against the Python model on random streams.'],
  },
  {
    time: '1:00 - 1:30',
    points: [
      'Two hard dates: 25 Oct and 1 Nov. Both have a named, checkable deliverable.',
      'Dates are proposed by the team and need confirming against the course schedule.',
    ],
    qa: ['What slips first? The Ethernet stretch. The core demo does not depend on it.'],
  },
  {
    time: '1:00',
    points: [
      'Five owners matched directly to our Project Abstract: Ronit (Bus/VGA), Akshit (RV32M), Aditya K (LOB Datapath), Aditya M (BRAM Queues/BBO), Aditeya G (C Drivers/Telemetry).',
      'The right side shows the strict sequential execution order: Aditeya G (Workload) -> Aditya K (Parsing/LOB) -> Aditya M (BBO) -> Ronit (Bus Arbiter) -> Akshit/Ronit (CPU & VGA).',
    ],
    qa: [
      'Why is bus access collision-free? 4-state non-preemptive arbiter with wait-states and dual-port BRAM controllers.',
      'Who verifies? Each member owns standalone Verilog testbenches before main bus integration.',
    ],
  },
  {
    time: '1:00 - 1:30',
    points: [
      'Input, processing, output. Output is visible on the 7-segment display.',
      'Challenges are real ones: overflow, hash capacity, BBO consistency, 100 MHz timing.',
      'CPU has only ever run at 1 Hz on the board. 100 MHz is unproven on hardware.',
    ],
    qa: ['Why is timing a risk? Post-synthesis margin was +0.42 ns. Nothing routed at 100 MHz yet.'],
  },
  {
    time: '1:30',
    points: [
      'Five pipeline stages: RMII RX (2-bit dibits) → Net Parser (Eth/IPv4/UDP) → MoldUDP64 → ITCH 5.0 decoder → 256-bit canonical event.',
      'Clock domain: all five stages run at 50 MHz; async FIFO bridges to the 100 MHz LOB core.',
      'Type \'A\' Add Order byte layout: [0]=type, [5-10]=48-bit timestamp ns, [11-18]=OID, [24-27]=price.',
      'Division-free pidx: price index = (price - base) × 274877907 >> 38. No hardware divider needed in the 50 MHz domain.',
      'The canonical event carries 256 bits including version, opcode, side, OID, qty, pidx, timestamp.',
    ],
    qa: [
      'What is the throughput? One 36-byte ITCH message per ~3.7 µs at 100 Mbps Ethernet.',
      'Why division-free? A reciprocal shift multiplier avoids a slow divide unit on the 50 MHz Ethernet path.',
    ],
  },
  {
    time: '1:30',
    points: [
      'LOB core is 7 pipelined hardware modules: hash table → slot table → free list → price RAM → occupancy bitmaps → BBO engine → MMIO.',
      'Hash table: 1024 sets × 8 ways + 8-entry CAM stash; set index = OID[9:0] XOR OID[19:10] XOR OID[29:20].',
      'ADD flow: pop free slot, write slot BRAM, update price RAM bank, set occupancy bit, check BBO.',
      'Fail-stop policy: 9 error codes; hardware freezes on error; CPU reads REG_LOB_ERROR_CODE at 0x4000_0028.',
      'Resource budget: 37 BRAMs, 18 DSP48s, 20,604 LUTs, 35,347 registers on Artix-7.',
    ],
    qa: [
      'Can two events arrive simultaneously? No; the upstream async FIFO serializes them before the LOB core.',
      'How many orders can the book hold? 2048 active orders (slot table capacity). Can be extended with more BRAM.',
    ],
  },
  {
    time: '1:30',
    points: [
      'Three-level hierarchy: L0 (8-bit master) → L1 (256-bit summary) → L2 (256 × 32-bit leaves) = 8,192 price tick occupancy bits.',
      'Best Bid = leading-1 priority encoder on L0 → L1 → L2. Best Ask = trailing-1 encoder. O(1) regardless of book depth.',
      'Result: L0 (1 cycle) → L1 (1 cycle) → L2 (1 cycle) → pidx; then 2-stage DSP48 multiplier gives final price = base + pidx × tick.',
      'Software equivalent would scan up to 8,192 price levels — 273× slower than our hardware.',
      'BBO update is triggered on every order event that changes qty at the best price level.',
    ],
    qa: [
      'What if there are no orders? All bits are 0; priority encoder detects empty via L0 == 0 and outputs INVALID.',
      'Is BBO always coherent? Yes; occupancy bits are updated atomically before BBO re-search is triggered.',
    ],
  },
  {
    time: '1:30',
    points: [
      'RV32M MUL maps to DSP48E1 dedicated silicon multiplier — 3 fixed pipeline cycles: M1 (input latch) → M2 (25×18 multiply core) → M3 (post-adder, PREG).',
      'Trace example: mul x3, x1, x2 where x1=7, x2=9 → x3=63 (0x0000003F). Result forwarded EX-to-EX to add x4 at T8.',
      'stall_pipeline is asserted for the full 4 cycles (T4–T7). Frontend skid buffer preserves add x4 decoded state.',
      'Four MUL variants: MUL (lower 32), MULH (upper 32 signed×signed), MULHU (unsigned), MULHSU (signed×unsigned).',
      '236 unit test vectors + 31 pipeline integration checks pass, including signed overflow edge cases.',
    ],
    qa: [
      'Why 4 stall cycles for a 3-cycle MUL? The result is available at end of M3 (T7). add x4 resumes at T8 with EX-to-EX forwarding.',
      'Does throughput suffer? Only when a RAW hazard exists on the MUL result. Independent instructions could overlap.',
    ],
  },
  {
    time: '1:30',
    points: [
      'Radix-2 non-restoring serial divider: 32 bit-iterations + 1 init = 33 stall cycles.',
      'Trace example: div x9, x4, x1 where x4=63, x1=7 → quotient=9, remainder=0. Stall from T16 to T55 (33 cycles).',
      'Hardware: 32-bit shift register for partial remainder; 33-bit quotient accumulator; state counter drives FSM.',
      'Signed fixup: 2\'s complement pre-negation on dividend/divisor; sign-correct result at the end.',
      'RISC-V spec edge cases hardwired: x/0 = -1 with rem=x; -2³¹ / -1 = -2³¹ with rem=0.',
    ],
    qa: [
      'Why 33 and not 32 cycles? 32 bit-iterations plus 1 cycle for initializing the partial remainder register.',
      'Could you pipeline the divider? Yes (SRT or digit-recurrence), but that costs 10–15× more LUTs and was not needed for correctness.',
    ],
  },
]
