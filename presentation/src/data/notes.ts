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
]
