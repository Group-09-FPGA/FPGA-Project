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
      'This trace comes from RTL simulation of the real CPU, not a drawing.',
      'MUL: 3 stall cycles. Point at the forwarding on add (x3) and mul x6 (x5).',
      'DIV: 32-iteration divider, 33 stall cycles. Skid buffer holds the fetched instruction.',
      'Use Play, or step with the Left and Right keys while the cursor is on this slide.',
    ],
    qa: [
      'Why a bubble after each M-op? Front end refills after the stall releases.',
      'Why no forwarding stall on load? BRAM data reaches WB while the user is in EX.',
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
    points: ['Four owners, four non-overlapping deliverables. Each can be tested alone.'],
    qa: ['Who integrates? D owns the FPGA top and the demo, B and C hand over tested modules.'],
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
