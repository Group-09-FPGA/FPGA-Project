// Cycle trace derived from RTL simulation (xsim) of cpu_core running the
// program in sim/unit/core/tb_rv32m_pipeline.v. Stage occupancy was read from
// fetch_pc / id_pc / ex_pc / ex_m / m_stalling / wb_dest_reg_sel each cycle.

export type Kind = 'IF' | 'ID' | 'EX' | 'M' | 'WB' | 'HOLD'

export interface TraceRow {
  pc: string
  asm: string
  cells: Record<number, Kind>
  fwd?: number[]
}

export const CYCLES = 25

const span = (from: number, to: number, k: Kind): Record<number, Kind> =>
  Object.fromEntries(Array.from({ length: to - from + 1 }, (_, i) => [from + i, k]))

export const ROWS: TraceRow[] = [
  { pc: '00', asm: 'addi x1, x0, 7', cells: { 0: 'IF', 1: 'ID', 2: 'EX', 3: 'WB' } },
  { pc: '04', asm: 'addi x2, x0, 9', cells: { 1: 'IF', 2: 'ID', 3: 'EX', 4: 'WB' } },
  { pc: '08', asm: 'mul  x3, x1, x2', cells: { 2: 'IF', 3: 'ID', ...span(4, 6, 'M'), 7: 'EX', 8: 'WB' } },
  { pc: '0c', asm: 'add  x4, x3, x1', cells: { 3: 'IF', 4: 'ID', ...span(5, 7, 'HOLD'), 8: 'EX', 9: 'WB' }, fwd: [8] },
  { pc: '10', asm: 'mul  x5, x3, x4', cells: { 4: 'IF', ...span(5, 7, 'HOLD'), 8: 'ID', 9: 'HOLD', ...span(10, 12, 'M'), 13: 'EX', 14: 'WB' } },
  { pc: '14', asm: 'mul  x6, x5, x1', cells: { 9: 'IF', 10: 'ID', ...span(11, 13, 'HOLD'), ...span(14, 16, 'M'), 17: 'EX', 18: 'WB' }, fwd: [14] },
  { pc: '18', asm: 'div  x7, x6, x2', cells: { 10: 'IF', ...span(11, 13, 'HOLD'), 14: 'ID', ...span(15, 18, 'HOLD'), ...span(19, 24, 'M') } },
  { pc: '1c', asm: 'mul  x8, x7, x2', cells: { 18: 'IF', 19: 'ID', ...span(20, 24, 'HOLD') } },
]

// EX-stage bubbles observed after an M-unit stall releases.
export const BUBBLES = [9, 18]

export const CAPTIONS: string[] = [
  'Reset released. Fetch addi x1.',
  'Fetch addi x2, decode addi x1.',
  'Fetch mul, execute addi x1.',
  'Execute addi x2, decode mul.',
  'MUL starts in the RV32M unit. EX freezes for 3 cycles.',
  'MUL stall 2 of 3. Fetched instructions held by the skid buffer.',
  'MUL stall 3 of 3.',
  'MUL done. Result captured, EX released.',
  'add runs now. x3 is forwarded from WB, avoiding data hazard.',
  'One bubble in EX while the pipeline refills.',
  'mul x5 starts. x4 comes from the register file.',
  'MUL stall 2 of 3.',
  'MUL stall 3 of 3.',
  'MUL done.',
  'mul x6 starts. x5 is forwarded from WB.',
  'MUL stall 2 of 3.',
  'MUL stall 3 of 3.',
  'MUL done.',
  'Bubble in EX. x6 written back.',
  'DIV starts: 32-iteration restoring divider launched.',
  'DIV iteration. EX frozen, front end held.',
  'DIV iteration. EX frozen, front end held.',
  'DIV iteration. EX frozen, front end held.',
  'DIV iteration. EX frozen, front end held.',
  'DIV continues: 33 stall cycles in total, then result is latched.',
]
