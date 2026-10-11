// Exports the deck to an editable .pptx (native shapes, text and tables, no images).
// Run: pnpm export:pptx
import PptxGenJS from 'pptxgenjs'
import { ROWS, CYCLES, BUBBLES } from '../src/data/trace.ts'
import { NOTES } from '../src/data/notes.ts'

const PAPER = 'EFEFED', INK = '16181D', INK2 = '4A4E57', INK3 = '8B8F98', NAVY = '2A2E86'
const SANS = 'Arial', MONO = 'Courier New'
const OFF = 14 // top border of the stage, in css px
const P = (v) => v / 144 // 1920 css px -> 13.333 in

const pptx = new PptxGenJS()
pptx.layout = 'LAYOUT_16x9'
pptx.title = 'RV32IM + Hardware Limit Order Book'
pptx.author = 'Group 09'

const S = pptx.ShapeType

function T(slide, text, x, y, w, h, o = {}) {
  slide.addText(text, {
    x: P(x), y: P(y + OFF), w: P(w), h: P(h), margin: 0,
    fontFace: o.mono ? MONO : SANS, fontSize: (o.size ?? 28) / 2, bold: !!o.bold,
    color: o.color ?? INK, align: o.align ?? 'left', valign: o.valign ?? 'top',
    charSpacing: o.cs, lineSpacingMultiple: o.ls, fit: 'none', wrap: true, rotate: o.rotate,
  })
}

function R(slide, x, y, w, h, o = {}) {
  slide.addShape(o.shape ?? S.rect, {
    x: P(x), y: P(y + OFF), w: P(w), h: P(h),
    fill: o.fill ? { color: o.fill } : { type: 'none' },
    line: o.line === false ? { type: 'none' } : { color: o.line ?? INK, width: o.lw ?? 0.75, dashType: o.dash ?? 'solid' },
    rotate: o.rotate,
  })
}

function L(slide, x1, y1, x2, y2, o = {}) {
  slide.addShape(S.line, {
    x: P(Math.min(x1, x2)), y: P(Math.min(y1, y2) + OFF), w: P(Math.abs(x2 - x1)), h: P(Math.abs(y2 - y1)),
    flipH: x2 < x1, flipV: y2 < y1,
    line: { color: o.color ?? INK, width: o.lw ?? 0.75, dashType: o.dash ?? 'solid', endArrowType: o.arrow ? 'triangle' : undefined, beginArrowType: o.arrowStart ? 'triangle' : undefined },
  })
}

function poly(slide, pts, o = {}) {
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1])
  const minx = Math.min(...xs), miny = Math.min(...ys)
  const w = Math.max(...xs) - minx, h = Math.max(...ys) - miny
  const points = pts.map((p, i) => ({ x: P(p[0] - minx), y: P(p[1] - miny), moveTo: i === 0 }))
  points.push({ close: true })
  slide.addShape(S.custGeom, {
    x: P(minx), y: P(miny + OFF), w: P(w), h: P(h), points,
    fill: o.fill ? { color: o.fill } : { type: 'none' },
    line: { color: o.color ?? INK, width: o.lw ?? 0.9, dashType: o.dash ?? 'solid' },
  })
}

function chip(slide, cx, cy, label) {
  const t = 34
  const A = [-220, 0], B = [0, -110], C = [220, 0], D = [0, 110]
  const m = (p, dx = 0, dy = 0) => [cx + p[0] + dx, cy + p[1] + dy]
  const k = (s) => [m([-220 * s, 0]), m([0, -110 * s]), m([220 * s, 0]), m([0, 110 * s])]
  poly(slide, [m(A), m(B), m(C), m(D)])
  poly(slide, [m(A), m(D), m(D, 0, t), m(A, 0, t)])
  poly(slide, [m(D), m(C), m(C, 0, t), m(D, 0, t)])
  poly(slide, k(0.62))
  poly(slide, k(0.38), { color: INK2, dash: 'dash', lw: 0.7 })
  for (let i = 0; i < 9; i++) {
    const f = (i + 0.5) / 9
    const lx = A[0] + (D[0] - A[0]) * f, ly = A[1] + (D[1] - A[1]) * f
    const rx = D[0] + (C[0] - D[0]) * f, ry = D[1] + (C[1] - D[1]) * f
    L(slide, cx + lx, cy + ly + t, cx + lx - 6, cy + ly + t + 22)
    L(slide, cx + rx, cy + ry + t, cx + rx + 6, cy + ry + t + 22)
  }
  R(slide, cx - 157, cy - 7, 14, 14, { shape: S.ellipse })
  T(slide, label, cx - 80, cy - 20, 160, 40, { size: 30, bold: true, align: 'center', valign: 'middle', cs: 3, rotate: -27 })
}

function nut(slide, cx, cy) {
  R(slide, cx - 38, cy - 38, 76, 76, { shape: S.hexagon })
  R(slide, cx - 30, cy - 30, 60, 60, { shape: S.hexagon })
  R(slide, cx - 16, cy - 16, 32, 32, { shape: S.ellipse })
}

function gear(slide, cx, cy, r) {
  R(slide, cx - r * 1.15, cy - r * 1.15, r * 2.3, r * 2.3, { shape: S.gear6 })
  R(slide, cx - r * 0.55, cy - r * 0.55, r * 1.1, r * 1.1, { shape: S.ellipse })
  R(slide, cx - r * 0.22, cy - r * 0.22, r * 0.44, r * 0.44, { shape: S.ellipse })
}

function frame(n, kicker, title) {
  const s = pptx.addSlide()
  s.background = { color: PAPER }
  s.addShape(S.rect, { x: 0, y: 0, w: P(1920), h: P(OFF), fill: { color: NAVY }, line: { type: 'none' } })
  s.addShape(S.rect, { x: 0, y: P(1080 - OFF), w: P(1920), h: P(OFF), fill: { color: NAVY }, line: { type: 'none' } })
  T(s, kicker.toUpperCase(), 96, 56, 1500, 30, { size: 22, bold: true, color: INK3, cs: 2 })
  T(s, title, 96, 88, 1500, title.includes('\n') ? 150 : 80, { size: 66, bold: true, ls: 0.9 })
  T(s, `${String(n).padStart(3, '0')} \u00b7 GROUP 09 \u00b7 FPGA LOB`, 96, 1004, 700, 28, { size: 20, mono: true, color: INK3 })
  for (let i = 0; i < 7; i++) {
    R(s, 1694 + i * 20, 1012, 10, 10, { shape: S.ellipse, fill: i + 1 === n ? NAVY : undefined, line: i + 1 === n ? NAVY : INK3, lw: 1 })
  }
  const nt = NOTES[n - 1]
  s.addNotes(`Target time: ${nt.time}\n\n${nt.points.map((p) => '- ' + p).join('\n')}\n\nLikely questions:\n${nt.qa.map((p) => '- ' + p).join('\n')}`)
  return s
}

const label = (s, text, x, y, w = 600) => T(s, text.toUpperCase(), x, y, w, 30, { size: 22, bold: true, color: NAVY, cs: 2 })
const bullets = (s, items, x, y, w, h, size = 32) =>
  s.addText(items.map((t) => ({ text: t, options: { bullet: { characterCode: '25C7', indent: 22 }, breakLine: true, paraSpaceAfter: 8 } })), {
    x: P(x), y: P(y + OFF), w: P(w), h: P(h), margin: 0, fontFace: SANS, fontSize: size / 2, color: INK, valign: 'top',
  })

// ---------- 1 ----------
{
  const s = frame(1, 'Project overview \u00b7 scope', 'RV32IM + Hardware\nLimit Order Book')
  L(s, 980, 1052, 1920, 160, { color: INK2, lw: 1 })
  chip(s, 1510, 450, 'LOB')
  nut(s, 1755, 925)
  label(s, 'Problem', 96, 262)
  T(s, 'Software order books spend a variable, CPU-bound cost on every market message.', 96, 296, 1040, 90, { size: 30 })
  label(s, 'System', 96, 400)
  bullets(s, ['RV32IM softcore on a Nexys A7-100T', 'Pure-hardware limit order book, bounded cycles per event', 'CPU configures it and reads best bid / ask over MMIO'], 96, 438, 1040, 150, 30)
  label(s, 'System scope', 96, 590)
  const rows = [
    ['Commitment', NAVY, ['Python golden model + canonical event contract', 'Hardware order book: hash, slots, free list, price RAM']],
    ['Goal', INK, ['BBO hierarchy + MMIO: CPU reads live best bid / ask', 'FPGA demo on Nexys A7-100T, BBO on the display']],
    ['Stretch', INK3, ['Ethernet RMII + MoldUDP64 + ITCH feed into the book']],
  ]
  rows.forEach(([tag, c, items], i) => {
    const y = 632 + i * 108
    L(s, 96, y, 1140, y)
    T(s, tag.toUpperCase(), 96, y + 14, 220, 30, { size: 22, bold: true, mono: true, color: c })
    T(s, items.join('\n'), 316, y + 10, 830, 90, { size: 27, ls: 1.1 })
  })
}

// ---------- 2 ----------
{
  const s = frame(2, 'Existing CPU in grey \u00b7 new hardware in blue', 'System architecture')
  gear(s, 1760, 110, 46)
  const X = (x) => 96 + x, Y = (y) => 219 + y
  const box = (x, y, w, h, t, sub, isNew) => {
    R(s, X(x), Y(y), w, h, { fill: isNew ? 'E3E4F4' : 'F7F7F6', line: isNew ? NAVY : INK3, lw: isNew ? 1.5 : 1 })
    const runs = [{ text: t, options: { fontSize: 12.5, bold: true, color: isNew ? '101234' : INK2, breakLine: !!sub } }]
    if (sub) runs.push({ text: sub, options: { fontSize: 10, color: INK2 } })
    s.addText(runs, { x: P(X(x)), y: P(Y(y) + OFF), w: P(w), h: P(h), margin: 0, fontFace: SANS, align: 'center', valign: 'middle' })
  }
  const group = (x, y, w, h, lab, isNew) => {
    R(s, X(x), Y(y), w, h, { line: isNew ? NAVY : INK3, dash: 'dash', lw: 0.9 })
    if (lab) T(s, lab, X(x) + 14, Y(y) - 32, 700, 26, { size: 20, mono: true, bold: true, color: isNew ? NAVY : INK3 })
  }
  group(0, 30, 1000, 220, 'RV32IM CORE \u00b7 3 STAGES')
  box(24, 56, 210, 80, 'IF / ID', 'fetch + decode')
  box(395, 56, 210, 80, 'EX', 'ALU, branch, fwd')
  box(766, 56, 210, 80, 'MEM / WB', 'bus access')
  box(395, 152, 210, 72, 'RV32M unit', 'MUL 3 \u00b7 DIV 33')
  L(s, X(234), Y(96), X(393), Y(96), { color: '6B6F78', lw: 1.2, arrow: true })
  L(s, X(605), Y(96), X(764), Y(96), { color: '6B6F78', lw: 1.2, arrow: true })
  L(s, X(500), Y(136), X(500), Y(152), { color: '6B6F78', lw: 1.2 })
  group(1056, 30, 672, 130, 'MEMORY + I/O')
  box(1076, 56, 196, 80, 'IMEM', '4 KB')
  box(1292, 56, 196, 80, 'DMEM', '4 KB')
  box(1508, 56, 196, 80, '7-seg + LED')
  L(s, X(0), Y(330), X(1728), Y(330), { lw: 3 })
  T(s, 'SYSTEM BUS', X(0), Y(300), 400, 26, { size: 20, mono: true, bold: true, color: INK2 })
  ;[[500, 250], [1174, 160], [1390, 160], [1606, 160]].forEach(([x, y]) => L(s, X(x), Y(y), X(x), Y(330), { color: '6B6F78', lw: 1.2 }))
  T(s, 'NEW \u00b7 HARDWARE LIMIT ORDER BOOK', X(0), Y(384), 900, 26, { size: 20, mono: true, bold: true, color: NAVY })
  box(0, 440, 210, 130, 'Event source', 'replay, ITCH later', true)
  box(270, 440, 210, 130, 'Async FIFO', '50 \u2192 100 MHz', true)
  group(540, 425, 620, 190, '', true)
  box(562, 445, 266, 68, 'Hash + stash', '', true)
  box(872, 445, 266, 68, 'Slot table', '', true)
  box(562, 529, 266, 68, 'Free list', '', true)
  box(872, 529, 266, 68, 'Price RAM', '', true)
  box(1220, 440, 220, 130, 'BBO search', 'hierarchical', true)
  box(1500, 440, 228, 130, 'MMIO regs', '0x4000_0000', true)
  ;[[212, 268], [482, 538], [1162, 1218], [1442, 1498]].forEach(([a, b]) => L(s, X(a), Y(505), X(b), Y(505), { color: NAVY, lw: 1.5, arrow: true }))
  L(s, X(1680), Y(440), X(1680), Y(334), { color: NAVY, lw: 1.5, arrow: true })
  T(s, 'BBO read \u2191', X(1380), Y(392), 290, 26, { size: 20, mono: true, color: INK2, align: 'right' })
  const notes = [['Where it fits', 'One new MMIO slave on the existing bus. Pipeline unchanged.'], ['Data flow', 'Event \u2192 FIFO \u2192 book \u2192 BBO search \u2192 registers.'], ['Control flow', 'CPU configures and reads. It is never in the per-event path.']]
  notes.forEach(([h, b], i) => {
    const x = 96 + i * 592
    label(s, h, x, 880, 540)
    T(s, b, x, 914, 540, 90, { size: 25, ls: 1.1 })
  })
}

// ---------- 3 ----------
{
  const s = frame(3, 'RTL simulation trace \u00b7 25 cycles', 'Timing diagram: MUL and DIV in the pipeline')
  const gx = 96, gy = 176, lw = 400, cw = 52, rh = 41
  for (let c = 0; c < CYCLES; c++) T(s, String(c), gx + lw + c * cw, gy, cw, rh, { size: 20, mono: true, bold: true, color: INK3, align: 'center', valign: 'middle' })
  L(s, gx, gy + rh, gx + lw + CYCLES * cw, gy + rh, { lw: 1 })
  const style = {
    'IF/ID': { fill: 'E5E6F5', line: INK, color: INK },
    IF: { fill: 'FFFFFF', line: INK, color: INK }, ID: { fill: 'E5E6F5', line: INK, color: INK },
    EX: { fill: 'C8E6C9', line: '2E7D32', color: '1B5E20' },
    M: { fill: '0D3B66', line: '062340', color: 'FFFFFF' },
    D: { fill: '0D3B66', line: '062340', color: 'FFFFFF' },
    'MEM/WB': { fill: 'FFE0B2', line: 'FB8C00', color: 'E65100' },
    WB: { fill: INK, line: INK, color: 'FFFFFF' },
    STALL: { fill: 'FEF3C7', line: 'D97706', color: 'B45309' },
    HOLD: { fill: undefined, line: INK3, color: INK3, dash: 'dash' },
    FLUSH: { fill: 'FFE4E6', line: 'E11D48', color: 'BE123C' },
  }
  const cell = (c, y, k, text, fwd) => {
    const st = style[k] ?? { fill: undefined, line: INK, color: INK }
    const x = gx + lw + c * cw + 3, yy = y + 4
    R(s, x, yy, 46, 32, { fill: st.fill, line: fwd ? '1F7A4D' : st.line, lw: fwd ? 2.25 : 0.9, dash: st.dash })
    T(s, text, x, yy, 46, 32, { size: 20, mono: true, bold: k !== 'HOLD', color: st.color, align: 'center', valign: 'middle' })
  }
  ROWS.forEach((row, i) => {
    const y = gy + rh * (i + 1)
    T(s, row.pc, gx + 4, y, 40, rh, { size: 20, mono: true, color: INK3, valign: 'middle' })
    T(s, row.asm, gx + 56, y, 340, rh, { size: 22, mono: true, valign: 'middle' })
    L(s, gx, y + rh, gx + lw + CYCLES * cw, y + rh, { color: 'C9C9C5' })
    for (const [c, k] of Object.entries(row.cells)) cell(+c, y, k, k === 'HOLD' ? '\u2013' : k, row.fwd?.includes(+c))
  })
  const by = gy + rh * (ROWS.length + 1)
  T(s, 'EX bubble', gx + 56, by, 340, rh, { size: 22, mono: true, color: 'B4451F', valign: 'middle' })
  BUBBLES.forEach((c) => {
    R(s, gx + lw + c * cw + 3, by + 4, 46, 32, { line: 'B4451F', lw: 0.9 })
    T(s, '\u00d7', gx + lw + c * cw + 3, by + 4, 46, 32, { size: 20, mono: true, bold: true, color: 'B4451F', align: 'center', valign: 'middle' })
  })
  const ly = by + rh + 34
  const leg = [['IF', 'fetch', 120], ['ID', 'decode', 150], ['EX', 'execute', 160], ['M', 'RV32M busy', 230], ['WB', 'writeback', 180], ['HOLD', 'held', 130], ['FWD', 'forwarded operand', 320]]
  let lx = 96
  leg.forEach(([k, txt, w]) => {
    const st = style[k] ?? { fill: undefined, line: '1F7A4D' }
    R(s, lx, ly + 3, 24, 18, { fill: st.fill, line: st.line, lw: k === 'FWD' ? 2.25 : 0.9, dash: st.dash })
    T(s, txt, lx + 34, ly, w - 34, 26, { size: 20, mono: true, color: INK2 })
    lx += w
  })
  const pts = [['Multi-cycle', 'MUL stalls EX for 3 cycles. DIV stalls for 33.'], ['Stall behaviour', 'Front end is held. Skid buffer keeps the fetched word.'], ['Forwarding', 'add uses x3 and mul x6 uses x5 straight from WB, no extra stall.']]
  pts.forEach(([h, b], i) => {
    const x = 96 + i * 592
    label(s, h, x, ly + 60, 540)
    T(s, b, x, ly + 94, 540, 90, { size: 25, ls: 1.1 })
  })
}

// ---------- 4 ----------
{
  const s = frame(4, 'How we build it and prove it', 'Design + verification plan')
  gear(s, 1790, 100, 44)
  label(s, 'Implementation plan', 96, 236)
  const steps = [
    ['Golden model + event contract', 'Python book, canonical events, test vectors'],
    ['Hash, slot table, free list', 'Modules + testbench, checked against the model'],
    ['Price RAM + occupancy + BBO', 'Module + testbench, best bid / ask match'],
    ['MMIO + CPU integration', 'Integrated simulation: C program reads BBO'],
  ]
  steps.forEach(([h, b], i) => {
    const y = 282 + i * 132
    L(s, 96, y, 876, y)
    T(s, String(i + 1), 96, y + 20, 70, 60, { size: 40, mono: true, bold: true, color: NAVY })
    T(s, h, 178, y + 22, 700, 44, { size: 34, bold: true })
    T(s, b, 178, y + 70, 700, 36, { size: 28, color: INK2 })
  })
  label(s, 'Verification plan', 1000, 236)
  const checks = [
    ['Module level', ['Each module vs golden model vectors', 'Random event streams, bit-exact BBO']],
    ['Edge cases', ['Duplicate / missing order ID, quantity underflow', 'Hash set full, empty book, signed / unsigned, divide by zero']],
    ['Processor level', ['C programs on the CPU, compared against reference logs', 'RV32M already passes 236 unit + 31 pipeline checks']],
  ]
  checks.forEach(([h, items], i) => {
    const y = 282 + i * 180
    L(s, 1000, y, 1824, y)
    T(s, h, 1000, y + 22, 800, 44, { size: 34, bold: true })
    T(s, items.join('\n'), 1000, y + 76, 824, 90, { size: 29, ls: 1.1 })
  })
}

// ---------- 5 ----------
{
  const s = frame(5, 'Milestones', 'Timeline')
  const y0 = 610
  L(s, 96, y0, 1824, y0, { lw: 1.5 })
  const items = [
    { x: 40, up: true, num: '01', date: '11 Oct', txt: 'CPU + RV32M verified, architecture audit done' },
    { x: 380, up: false, num: '02', date: '18 Oct', txt: 'Golden model + event vectors in repo' },
    { x: 720, up: true, num: '03', date: '25 Oct', txt: 'Hash, slot table, free list pass their testbenches', ms: true },
    { x: 1060, up: false, num: '04', date: '1 Nov', txt: 'Minimum system: book + BBO + MMIO, CPU reads BBO in simulation', ms: true },
    { x: 1400, up: true, num: '05', date: 'Final phase', txt: 'Integration, 100 MHz timing, FPGA demo', ms: true },
  ]
  items.forEach((it) => {
    const cx = 96 + it.x + 20
    L(s, cx, y0, cx, it.up ? y0 - 70 : y0 + 70)
    R(s, cx - 17, y0 - 17, 34, 34, { shape: S.diamond, fill: it.ms ? NAVY : PAPER, line: it.ms ? NAVY : INK, lw: 1.25 })
    const tx = 96 + it.x, ty = it.up ? y0 - 70 - 205 : y0 + 82
    T(s, it.num, tx, ty, 100, 68, { size: 54, bold: true })
    if (it.ms) {
      R(s, tx + 100, ty + 18, 150, 30, { fill: NAVY, line: false })
      T(s, 'MILESTONE', tx + 100, ty + 18, 150, 30, { size: 18, mono: true, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle' })
    }
    T(s, it.date, tx, ty + 70, 330, 34, { size: 24, mono: true, bold: true, color: NAVY })
    T(s, it.txt, tx, ty + 110, 320, 110, { size: 27, color: INK2, ls: 1.05 })
  })
  T(s, 'Stretch (Ethernet + ITCH) starts only after milestone 04 is met.', 96, 950, 1500, 30, { size: 22, mono: true, color: INK2 })
}

// ---------- 6 ----------
{
  const s = frame(6, 'Non-overlapping ownership', 'Team responsibilities')
  nut(s, 1760, 150)
  const hd = (t) => ({ text: t.toUpperCase(), options: { fontFace: MONO, fontSize: 11, bold: true, color: INK3, charSpacing: 2, border: [{ type: 'none' }, { type: 'none' }, { pt: 1, color: INK }, { type: 'none' }] } })
  const bd = { type: 'none' }, bb = { pt: 0.75, color: 'C4C4C0' }
  const rows = [
    ['A', 'Golden model', 'Python book, event contract, test vectors. Then stretch: Ethernet + ITCH parser.'],
    ['B', 'LOB core', 'Hash + stash, slot table, free list, price RAM, with testbenches.'],
    ['C', 'BBO + MMIO + firmware', 'Occupancy hierarchy, MMIO slave, bus decode, C test programs.'],
    ['D', 'FPGA + demo', '100 MHz clocking, XDC constraints, synthesis, timing closure, demo.'],
  ]
  const cellOpts = (o) => ({ valign: 'middle', border: [bd, bd, bb, bd], margin: [0, 8, 0, 8], ...o })
  const body = rows.map(([m, r, d]) => [
    { text: m, options: cellOpts({ fontFace: MONO, fontSize: 32, bold: true, color: NAVY }) },
    { text: r, options: cellOpts({ fontFace: SANS, fontSize: 16, bold: true, color: INK }) },
    { text: d, options: cellOpts({ fontFace: SANS, fontSize: 16, color: INK2 }) },
  ])
  s.addTable([[hd('Member'), hd('Responsibility'), hd('Deliverable')], ...body], {
    x: P(96), y: P(260 + OFF), w: P(1728), colW: [P(130), P(520), P(1078)], rowH: [P(50), ...rows.map(() => P(150))],
  })
  T(s, 'Roles are proposed for this plan. Replace with the real team split.', 96, 940, 1500, 30, { size: 20, mono: true, color: INK3 })
}

// ---------- 7 ----------
{
  const s = frame(7, 'Visible on the FPGA', 'Demo plan + challenges')
  chip(s, 1610, 270, 'FPGA')
  label(s, 'Demo plan', 96, 236)
  const flow = [['Input', 'Recorded order events replayed into the book'], ['Processing', 'Hardware LOB update, BBO search, CPU reads BBO over MMIO'], ['Output', 'Best bid / ask on the 7-segment display, status on LEDs']]
  flow.forEach(([h, t], i) => {
    const y = 276 + i * 104
    L(s, 96, y, 1096, y)
    T(s, h.toUpperCase(), 96, y + 20, 220, 36, { size: 26, mono: true, bold: true, color: NAVY, cs: 1 })
    T(s, t, 316, y + 16, 780, 80, { size: 32, ls: 1.05 })
  })
  label(s, 'Challenges', 96, 620)
  bullets(s, [
    'Quantity overflow and underflow: fail-stop, never a corrupt book',
    'Hash collisions: bounded sets plus stash, capacity proven',
    'BBO consistency while the book is updating',
    'FPGA timing: CPU has only run at 1 Hz on the board so far',
  ], 96, 664, 1500, 280, 32)
}

import { fileURLToPath } from 'url'
await pptx.writeFile({ fileName: fileURLToPath(new URL('../FPGA-LOB-presentation.pptx', import.meta.url)) })
console.log('wrote FPGA-LOB-presentation.pptx')
