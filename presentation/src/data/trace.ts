// Cycle trace derived from RTL simulation of cpu_core + sys_bus_interconnect + imem/dmem slaves.
// Figure 3 - Pipeline Timing: EX-to-EX Forwarding, Load-ALU Stall, Bus Wait & RV32M Multi-Cycle Ops
// Stages: IF/ID (Fetch+Decode), EX (Execute/M-Unit), MEM/WB (Bus/Writeback)

export type Kind = 'IF/ID' | 'EX' | 'M' | 'D' | 'MEM/WB' | 'STALL' | 'HOLD' | 'FLUSH'

export interface TraceRow {
  pc: string
  asm: string
  cells: Record<number, Kind>
  fwd?: number[]
}

export interface CycleCol {
  id: number
  label: string
  isFold?: boolean
  foldText?: string
}

export interface ForwardingArrow {
  fromRow: number
  toRow: number
  fromCol: number
  toCol: number
  label?: string
}

export interface SignalDef {
  name: string
  label: string
  color: string
  // Values for each of the 30 columns (0 = LOW, 1 = HIGH)
  values: number[]
  badges?: Record<number, string>
}

// 30 display columns: T0..T24 (0..24), Fold T25-T52 (25), T53..T56 (26..29)
export const CYCLES = 30

export const COLS: CycleCol[] = [
  ...Array.from({ length: 25 }, (_, i) => ({ id: i, label: `T${i}` })),
  { id: 25, label: '~', isFold: true, foldText: 'T25 - T52: Radix-2 Divider (33 cyc stall)' },
  { id: 26, label: 'T53' },
  { id: 27, label: 'T54' },
  { id: 28, label: 'T55' },
  { id: 29, label: 'T56' },
]

const span = (from: number, to: number, k: Kind): Record<number, Kind> =>
  Object.fromEntries(Array.from({ length: to - from + 1 }, (_, i) => [from + i, k]))

export const ROWS: TraceRow[] = [
  {
    pc: '0x00',
    asm: 'addi x1, x0, 7',
    cells: { 0: 'IF/ID', 1: 'EX', 2: 'MEM/WB' },
  },
  {
    pc: '0x04',
    asm: 'addi x2, x1, 2',
    cells: { 1: 'IF/ID', 2: 'EX', 3: 'MEM/WB' },
    fwd: [2],
  },
  {
    pc: '0x08',
    asm: 'lui x5, 0x20000',
    cells: { 2: 'IF/ID', 3: 'EX', 4: 'MEM/WB' },
  },
  {
    pc: '0x0c',
    asm: 'mul x3, x1, x2',
    cells: { 3: 'IF/ID', 4: 'M', 5: 'M', 6: 'M', 7: 'M', 8: 'MEM/WB' },
  },
  {
    pc: '0x10',
    asm: 'add x4, x3, x1',
    cells: { 4: 'IF/ID', 5: 'HOLD', 6: 'HOLD', 7: 'HOLD', 8: 'EX', 9: 'MEM/WB' },
    fwd: [8],
  },
  {
    pc: '0x14',
    asm: 'sw x4, 0(x5)',
    cells: { 9: 'IF/ID', 10: 'EX', 11: 'MEM/WB' },
  },
  {
    pc: '0x18',
    asm: 'lw x6, 0(x5)',
    cells: { 10: 'IF/ID', 11: 'EX', 12: 'MEM/WB' },
  },
  {
    pc: '0x1c',
    asm: 'add x7, x6, x1',
    cells: { 11: 'IF/ID', 12: 'STALL', 13: 'EX', 14: 'MEM/WB' },
    fwd: [13],
  },
  {
    pc: '0x20',
    asm: 'beq x0, x0, +16',
    cells: { 13: 'IF/ID', 14: 'EX', 15: 'MEM/WB' },
  },
  {
    pc: '0x24',
    asm: 'addi x8, x0, 1',
    cells: { 14: 'IF/ID', 15: 'FLUSH' },
  },
  {
    pc: '0x30',
    asm: 'div x9, x4, x1',
    cells: {
      15: 'IF/ID',
      ...span(16, 24, 'D'),
      25: 'D',
      26: 'D',
      27: 'D',
      28: 'MEM/WB',
    },
  },
  {
    pc: '0x34',
    asm: 'addi x10, x9, 1',
    cells: {
      16: 'IF/ID',
      ...span(17, 24, 'HOLD'),
      25: 'HOLD',
      26: 'HOLD',
      27: 'HOLD',
      28: 'EX',
      29: 'MEM/WB',
    },
    fwd: [28],
  },
]

// Forwarding arrows (EX-to-EX in green)
export const FORWARDING_ARROWS: ForwardingArrow[] = [
  { fromRow: 0, toRow: 1, fromCol: 1, toCol: 2, label: 'EX-EX' },
  { fromRow: 3, toRow: 4, fromCol: 7, toCol: 8, label: 'EX-EX' },
  { fromRow: 6, toRow: 7, fromCol: 12, toCol: 13, label: 'EX-EX' },
  { fromRow: 10, toRow: 11, fromCol: 27, toCol: 28, label: 'EX-EX' },
]

// Bubbles observed during pipeline execution (Load-ALU stall at T12)
export const BUBBLES = [12]

// Hardware control signals & bus protocol (10 signals from sim)
const makeValues = (highIndices: number[]): number[] => {
  const arr = Array(CYCLES).fill(0)
  for (const idx of highIndices) {
    if (idx >= 0 && idx < CYCLES) arr[idx] = 1
  }
  return arr
}

export const SIGNALS: SignalDef[] = [
  {
    name: 'clk',
    label: 'System Clock (100 MHz)',
    color: '#16181d',
    values: Array(CYCLES).fill(1), // square wave rendered specially
  },
  {
    name: 'stall_pipeline',
    label: 'Global pipeline freeze',
    color: '#b91c1c',
    values: makeValues([4, 5, 6, 7, 12, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]),
  },
  {
    name: 'm_start',
    label: 'RV32M unit trigger pulse',
    color: '#2563eb',
    values: makeValues([4, 16]),
  },
  {
    name: 'm_busy',
    label: 'RV32M internal compute active',
    color: '#2563eb',
    values: makeValues([4, 5, 6, 7, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]),
  },
  {
    name: 'm_done',
    label: 'RV32M operation complete',
    color: '#16a34a',
    values: makeValues([8, 28]),
  },
  {
    name: 'fwd_a / fwd_b',
    label: 'EX-to-EX forwarding multiplexer selects',
    color: '#15803d',
    values: makeValues([2, 8, 13, 28]),
    badges: { 2: 'EX-EX', 8: 'EX-EX', 13: 'EX-EX', 28: 'EX-EX' },
  },
  {
    name: 'bus_req_valid',
    label: 'Interconnect bus request',
    color: '#ea580c',
    values: makeValues([0, 1, 2, 3, 8, 9, 10, 11, 13, 14, 15, 28, 29]),
  },
  {
    name: 'bus_rsp_valid',
    label: 'Interconnect slave response',
    color: '#ea580c',
    values: makeValues([1, 2, 3, 4, 9, 10, 11, 12, 13, 14, 15, 29]),
  },
  {
    name: 'branch_taken',
    label: 'Branch evaluate true (EX)',
    color: '#b91c1c',
    values: makeValues([14]),
  },
  {
    name: 'wb_stall',
    label: 'Bus load/store wait in WB stage',
    color: '#991b1b',
    values: makeValues([15, 16]),
  },
]

export const CAPTIONS: string[] = [
  'T0: Reset released. Fetch addi x1 (0x00) into IF/ID. Bus interconnect initiates imem request.',
  'T1: addi x1 enters EX. Fetch addi x2 (0x04) into IF/ID. Bus slave returns first instruction.',
  'T2: EX-to-EX Forwarding: addi x1 (WB) feeds x1=7 to addi x2 in EX. RAW bubble eliminated!',
  'T3: addi x2 in MEM/WB. lui x5 enters EX. Fetch mul x3 into IF/ID.',
  'T4: MUL starts: m_start pulses HIGH, m_busy & stall_pipeline assert. lui x5 writes back. add x4 frozen in IF/ID.',
  'T5: MUL computing (cycle 2/4). Pipeline frozen; add x4 held in IF/ID skid buffer.',
  'T6: MUL computing (cycle 3/4). Pipeline freeze holds fetched instructions in the skid buffer.',
  'T7: MUL computing (cycle 3/4). Final multiplier partial-product accumulation in RV32M unit.',
  'T8: MUL done: m_done pulses HIGH. EX-to-EX Forwarding feeds x3 product to add x4 in EX!',
  'T9: add x4 enters MEM/WB. sw x4 fetched into IF/ID. Pipeline resumes normal throughput.',
  'T10: sw x4 computes store address in EX. lw x6 fetched into IF/ID.',
  'T11: sw x4 in MEM/WB bus store. lw x6 computes load address in EX. add x7 fetched into IF/ID.',
  'T12: Load-ALU Stall: lw x6 data not ready in MEM/WB. stall_pipeline freezes pipeline for 1 bubble cycle (STALL).',
  'T13: Stall released! EX-to-EX Forwarding supplies loaded x6 directly to add x7 in EX. beq fetched.',
  'T14: Branch evaluate: beq in EX branch taken! branch_taken pulses HIGH. Wrong path addi x8 (0x24) fetched.',
  'T15: Branch squash: addi x8 flushed (FLUSH). Target div x9 (0x30) fetched into IF/ID. wb_stall asserts.',
  'T16: DIV starts: m_start pulses HIGH, m_busy & stall_pipeline assert. addi x10 frozen in IF/ID.',
  'T17: DIV computing (iteration 2). Pipeline frozen; addi x10 held in IF/ID skid buffer.',
  'T18: DIV computing. 32-iteration Radix-2 divider processes quotient while pipeline remains frozen.',
  'T19: DIV computing. Restoring/Radix-2 divider steps continue. Interconnect bus idle.',
  'T20: DIV computing. Divider active in EX stage.',
  'T21: DIV computing. Frontend held; skid buffer preserves decoded addi x10.',
  'T22: DIV computing. Quotient bit accumulation continues.',
  'T23: DIV computing. EX stage frozen by active M-unit division.',
  'T24: DIV iteration 9 complete before the 33-cycle divider stall break fold.',
  'T25–T52 (Fold): Radix-2 divider computes for 33 stall cycles. Frontend holds addi x10 frozen.',
  'T53: DIV penultimate iteration. 32-bit quotient nearly resolved.',
  'T54: DIV final compute cycle (34 cycles total). RV32M divider prepares complete result.',
  'T55: DIV done: m_done pulses HIGH; div enters MEM/WB. EX-to-EX Forwarding feeds quotient x9 to addi x10 in EX!',
  'T56: addi x10 enters MEM/WB. Final writeback completes the cycle-accurate trace execution.',
]
