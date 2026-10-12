import { useState } from 'react'
import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// ── Sub-components ────────────────────────────────────────────────────────────
interface BoxProps { x:number; y:number; w:number; h:number; t:string; s?:string; isNew?:boolean; d?:number }
function Box({ x, y, w, h, t, s, isNew, d=0 }: BoxProps) {
  const cy = y + h / 2
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h}
        fill={isNew ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
        stroke={isNew ? 'var(--navy)' : '#8b8f98'}
        strokeWidth={isNew ? 2.6 : 1.6} rx={2} />
      <text x={x + w / 2} y={s ? cy - 7 : cy + 8} textAnchor="middle"
        style={{ font: '600 22px var(--font)', fill: isNew ? '#101234' : 'var(--ink-2)' }}>
        {t}
      </text>
      {s && (
        <text x={x + w / 2} y={cy + 16} textAnchor="middle"
          style={{ font: '400 16px var(--font)', fill: 'var(--ink-2)' }}>
          {s}
        </text>
      )}
    </g>
  )
}

function Arrow({ d, isNew }: { d: string; isNew?: boolean }) {
  return (
    <path d={d} fill="none"
      stroke={isNew ? 'var(--navy)' : '#6b6f78'}
      strokeWidth={2.4}
      markerEnd={`url(#ah11${isNew ? 'n' : 'g'})`} />
  )
}

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 20px/1.35 var(--font)', marginTop: 6 }}>{children}</p>
    </div>
  )
}

// ── Data ──────────────────────────────────────────────────────────────────────
const EXAMPLES = [
  { label: '7 × 9',           a: 7,      b: 9,      result: 63,         hex: '0x0000003F' },
  { label: '−2 × 5',          a: -2,     b: 5,      result: -10,        hex: '0xFFFFFFF6' },
  { label: '0xFFFF × 0xFFFF', a: 0xFFFF, b: 0xFFFF, result: 0xFFFE0001, hex: '0xFFFE0001' },
]

// ── Layout constants ───────────────────────────────────────────────────────────
// Pipeline stage row  (boxes sit at y=10..92)
const BY = 10, BH = 82
const MY = BY + BH / 2   // = 51  — vertical centre for arrows & dots

// Box widths
const IW = 150   // IF/ID
const SW = 240   // each M stage (M1 / M2 / M3)
const RW = 240   // Result
const MW = 218   // MEM/WB

// Gap between every pair of boxes — this is where arrows live and dots travel
const GAP = 56

// X positions (left edge of each box)
const IX  = 0                    // IF/ID
const S1X = IX  + IW + GAP      // 206   M1
const S2X = S1X + SW + GAP      // 502   M2
const S3X = S2X + SW + GAP      // 798   M3
const RX  = S3X + SW + GAP      // 1094  Result
const MX  = RX  + RW + GAP      // 1390  MEM/WB
// rightmost edge: MX + MW = 1608  (well within 1728px SVG)

// Arrow spans — each arrow goes from right-edge-of-source to left-edge-of-target
//   Arrow 1: IX+IW → S1X   = 150 → 206   (56 px)
//   Arrow 2: S1X+SW → S2X  = 446 → 502   (56 px)
//   Arrow 3: S2X+SW → S3X  = 742 → 798   (56 px)
//   Arrow 4: S3X+SW → RX   = 1038 → 1094 (56 px)
//   Arrow 5: RX+RW  → MX   = 1334 → 1390 (56 px)

// Dot travel bounds (4px inset from each arrow endpoint, so dot clears the arrowhead)
const ARROWS = [
  { x1: IX  + IW,      x2: S1X,      isNew: false }, // IF/ID → M1
  { x1: S1X + SW,      x2: S2X,      isNew: true  }, // M1 → M2
  { x1: S2X + SW,      x2: S3X,      isNew: true  }, // M2 → M3
  { x1: S3X + SW,      x2: RX,       isNew: true  }, // M3 → Result
  { x1: RX  + RW,      x2: MX,       isNew: false }, // Result → MEM/WB
]

// ── Vertical section Y values ─────────────────────────────────────────────────
// Each constant is derived explicitly so collisions are impossible.

// Hardware chip labels (below boxes)
const HW_Y     = BY + BH + 28    // 120   text baseline

// Stall annotation (well below hw labels)
const STALL_TY = BY + BH + 58    // 150   stall text baseline  (30 px below hw_y)
const STALL_LY = BY + BH + 68    // 160   dashed stall line

// Timing table
const TBL_HDR  = STALL_LY + 38  // 198   section heading text
const TBL_RL   = TBL_HDR  + 12  // 210   rule line
const TBL_TOP  = TBL_RL   +  3  // 213   col-header boxes start
const CW = 112, CH = 44, LW = 196
// col headers:  y=213..257   (CH=44)
// data row 1:   y=257..301
// data row 2:   y=301..345
const TBL_BOT  = TBL_TOP + CH * 3   // 345

// MUL opcodes
const OPC_HDR  = TBL_BOT  + 34  // 379   section heading text
const OPC_RL   = OPC_HDR  + 12  // 391   rule line
const ORH      = 46             // opcode row height
// 4 rows: y≈393..577
const OPC_BOT  = OPC_RL + 2 + 4 * ORH   // 577

// Examples + DSP48E1 vs SW (below opcodes)
const EX_HDR   = OPC_BOT  + 34  // 611   section heading text
const EX_RL    = EX_HDR   +  8  // 619   rule line
const EX_CARD_Y = EX_RL   +  6  // 625   card top edge
const EX_CARD_H = 66
const EX_CARD_W = 268
const EX_CARD_G = 20            // gap between cards

// SVG total height
const SVG_H    = EX_CARD_Y + EX_CARD_H + 18   // 709
const SVG_TOP  = 108    // px from top of .slide (compact header ≈95 px + 13 px room)

export default function Slide11() {
  const [sel, setSel] = useState(0)
  const ex = EXAMPLES[sel]

  return (
    <Frame n={7} compactHeader
      kicker="RV32M Extension · DSP48E1 Hardware"
      title="Multiplier: 3-cycle pipeline · mul x3, x1, x2">

      {/* ── Main SVG ──────────────────────────────────────────────────────── */}
      <svg width={1728} height={SVG_H} viewBox={`0 0 1728 ${SVG_H}`}
        style={{ position: 'absolute', left: 96, top: SVG_TOP }}>
        <defs>
          <marker id="ah11g" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#6b6f78" />
          </marker>
          <marker id="ah11n" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ═══ ROW 1 · Pipeline stage boxes ════════════════════════════════ */}

        {/* Arrow lines first (drawn under boxes, so order matters) */}
        {ARROWS.map((a, i) => (
          <Arrow key={i} isNew={a.isNew}
            d={`M${a.x1},${MY} H${a.x2 - 2}`} />
        ))}

        {/* Animated dots — each travels its own arrow span (right-edge → left-edge) */}
        {ARROWS.map((a, i) => (
          <circle key={`dot-${i}`} r={5} cy={MY}
            fill={a.isNew ? 'var(--navy)' : '#6b6f78'} opacity="0.85">
            <animate attributeName="cx"
              from={a.x1 + 3}
              to={a.x2 - 14}
              dur="0.72s"
              begin={`${1.3 + i * 0.36}s`}
              repeatCount="indefinite" />
          </circle>
        ))}

        {/* ── IF/ID ── */}
        <g className="rise" style={delay(0.1)}>
          <rect x={IX} y={BY} width={IW} height={BH}
            fill="rgba(255,255,255,.55)" stroke="#8b8f98" strokeWidth={1.6} rx={2} />
          <text x={IX + IW / 2} y={BY + 35} textAnchor="middle"
            style={{ font: '600 21px var(--font)', fill: 'var(--ink-2)' }}>IF / ID</text>
          <text x={IX + IW / 2} y={BY + 57} textAnchor="middle"
            style={{ font: '400 15px var(--font)', fill: 'var(--ink-2)' }}>mul decoded</text>
        </g>

        {/* ── M1 · Operand Latch ── */}
        <g className="rise" style={delay(0.18)}>
          <Box x={S1X} y={BY} w={SW} h={BH} t="M 1" s="Operand Latch" isNew d={0.18} />
          <text x={S1X + SW / 2} y={HW_Y} textAnchor="middle"
            style={{ font: '500 13px var(--mono)', fill: 'var(--ink-3)' }}>
            DSP48E1 AREG / BREG
          </text>
        </g>

        {/* ── M2 · Core Multiply ── */}
        <g className="rise" style={delay(0.28)}>
          <Box x={S2X} y={BY} w={SW} h={BH} t="M 2" s="Core Multiply" isNew d={0.28} />
          <text x={S2X + SW / 2} y={HW_Y} textAnchor="middle"
            style={{ font: '500 13px var(--mono)', fill: 'var(--ink-3)' }}>
            25 × 18 MREG
          </text>
        </g>

        {/* ── M3 · Post-Add + PREG ── */}
        <g className="rise" style={delay(0.38)}>
          <Box x={S3X} y={BY} w={SW} h={BH} t="M 3" s="Post-Add + PREG" isNew d={0.38} />
          <text x={S3X + SW / 2} y={HW_Y} textAnchor="middle"
            style={{ font: '500 13px var(--mono)', fill: 'var(--ink-3)' }}>
            result ready
          </text>
        </g>

        {/* ── Result (dynamic) ── */}
        <g className="rise" style={delay(0.48)}>
          <rect x={RX} y={BY} width={RW} height={BH}
            fill="#e3e4f4" stroke="var(--navy)" strokeWidth={2.6} rx={2} />
          <text x={RX + RW / 2} y={BY + 35} textAnchor="middle"
            style={{ font: '700 21px var(--mono)', fill: '#101234' }}>
            x3 = {ex.result}
          </text>
          <text x={RX + RW / 2} y={BY + 57} textAnchor="middle"
            style={{ font: '500 15px var(--mono)', fill: 'var(--ink-2)' }}>
            {ex.hex}
          </text>
        </g>

        {/* ── MEM/WB ── */}
        <g className="rise" style={delay(0.58)}>
          <rect x={MX} y={BY} width={MW} height={BH}
            fill="rgba(255,255,255,.55)" stroke="#8b8f98" strokeWidth={1.6} rx={2} />
          <text x={MX + MW / 2} y={BY + 35} textAnchor="middle"
            style={{ font: '600 21px var(--font)', fill: 'var(--ink-2)' }}>MEM / WB</text>
          <text x={MX + MW / 2} y={BY + 57} textAnchor="middle"
            style={{ font: '400 15px var(--font)', fill: 'var(--ink-2)' }}>regfile WB</text>
        </g>

        {/* ═══ ROW 2 · Stall annotation ════════════════════════════════════ */}
        <g className="rise" style={delay(0.7)}>
          {/* Dashed span: from M1 left edge to Result right edge */}
          <line x1={S1X} y1={STALL_LY} x2={RX + RW} y2={STALL_LY}
            stroke="var(--warn)" strokeWidth={1.5} strokeDasharray="6 4" />
          {/* Text centred above the line — 10 px above */}
          <text x={(S1X + RX + RW) / 2} y={STALL_TY} textAnchor="middle"
            style={{ font: '600 15px var(--mono)', fill: 'var(--warn)', letterSpacing: '.04em' }}>
            stall_pipeline HIGH · m_busy HIGH (T4 – T7)
          </text>
          {/* m_done badge to the right */}
          <text x={RX + RW + 16} y={STALL_TY}
            style={{ font: '600 15px var(--mono)', fill: 'var(--ok)' }}>
            m_done ✓ T8
          </text>
        </g>

        {/* ═══ ROW 3 · Pipeline timing table ══════════════════════════════ */}
        <g className="rise" style={delay(0.8)}>
          <text x={0} y={TBL_HDR}
            style={{ font: '600 15px var(--mono)', fill: 'var(--navy)', letterSpacing: '.07em' }}>
            PIPELINE TIMING — mul x3, x1, x2 &nbsp; (x1 = {ex.a}, x2 = {ex.b})
          </text>
          <line x1={0} y1={TBL_RL} x2={LW + 7 * CW} y2={TBL_RL}
            stroke="var(--line)" strokeWidth={1.5} />

          {/* Column headers */}
          {['T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9'].map((c, i) => (
            <g key={c}>
              <rect x={LW + i * CW} y={TBL_TOP} width={CW - 2} height={CH - 2}
                fill={c === 'T8' ? '#e3e4f4' : 'rgba(255,255,255,.6)'}
                stroke={c === 'T8' ? 'var(--navy)' : '#e2e8f0'} strokeWidth={1} />
              <text x={LW + i * CW + CW / 2} y={TBL_TOP + 26} textAnchor="middle"
                style={{ font: `${c === 'T8' ? '700' : '600'} 15px var(--mono)`, fill: c === 'T8' ? 'var(--navy)' : 'var(--ink-2)' }}>
                {c}
              </text>
            </g>
          ))}

          {/* Data rows */}
          {[
            { instr: 'mul x3,x1,x2', cells: ['IF/ID', 'M1', 'M2', 'M3', '—', 'WB', '—'] },
            { instr: 'add x4,x3,x1', cells: ['—', 'HOLD', 'HOLD', 'HOLD', 'HOLD', 'EX→fwd', 'WB'] },
          ].map((r, ri) => (
            <g key={ri}>
              <text x={0} y={TBL_TOP + (ri + 1) * CH + 24}
                style={{ font: '500 14px var(--mono)', fill: 'var(--ink-2)' }}>
                {r.instr}
              </text>
              {r.cells.map((cell, ci) => {
                const isM    = cell.startsWith('M') && !cell.startsWith('ME')
                const isHold = cell === 'HOLD'
                const isFwd  = cell.includes('fwd')
                return (
                  <g key={ci}>
                    <rect x={LW + ci * CW} y={TBL_TOP + (ri + 1) * CH}
                      width={CW - 2} height={CH - 2}
                      fill={isM ? '#e3e4f4' : isHold ? 'rgba(252,211,77,.15)' : 'rgba(255,255,255,.6)'}
                      stroke={isM ? 'var(--navy)' : isFwd ? 'var(--ok)' : isHold ? '#d97706' : '#e2e8f0'}
                      strokeWidth={isM ? 2 : isFwd || isHold ? 1.5 : 1} />
                    <text x={LW + ci * CW + CW / 2} y={TBL_TOP + (ri + 1) * CH + 24}
                      textAnchor="middle"
                      style={{
                        font: `${isM ? '700' : '500'} ${cell.length > 4 ? '12' : '14'}px var(--mono)`,
                        fill: isM ? '#101234' : isFwd ? 'var(--ok)' : isHold ? '#b45309' : 'var(--ink-2)',
                      }}>
                      {cell}
                    </text>
                  </g>
                )
              })}
            </g>
          ))}
        </g>

        {/* ═══ ROW 4 · All 4 MUL opcodes ══════════════════════════════════ */}
        <g className="rise" style={delay(0.9)}>
          <text x={0} y={OPC_HDR}
            style={{ font: '600 15px var(--mono)', fill: 'var(--navy)', letterSpacing: '.07em' }}>
            ALL 4 RV32M MULTIPLY OPCODES
          </text>
          <line x1={0} y1={OPC_RL} x2={1440} y2={OPC_RL} stroke="var(--line)" strokeWidth={1.5} />
          {[
            { op: 'MUL',    desc: 'Lower 32 bits of signed × signed product' },
            { op: 'MULH',   desc: 'Upper 32 bits of signed × signed (64-bit result)' },
            { op: 'MULHU',  desc: 'Upper 32 bits of unsigned × unsigned' },
            { op: 'MULHSU', desc: 'Upper 32 bits of signed × unsigned' },
          ].map((r, i) => (
            <g key={r.op}>
              <text x={0}   y={OPC_RL + 4 + i * ORH + 28}
                style={{ font: '700 20px var(--mono)', fill: 'var(--navy)' }}>{r.op}</text>
              <text x={186} y={OPC_RL + 4 + i * ORH + 28}
                style={{ font: '400 20px var(--font)', fill: 'var(--ink-2)' }}>{r.desc}</text>
              <line x1={0} y1={OPC_RL + 4 + (i + 1) * ORH} x2={1440} y2={OPC_RL + 4 + (i + 1) * ORH}
                stroke="#e2e8f0" strokeWidth={1} />
            </g>
          ))}
        </g>

        {/* ═══ ROW 5 · Examples (3 horizontal cards) + DSP48E1 vs SW ══════ */}
        <g className="rise" style={delay(0.65)}>

          {/* ── EXAMPLES header + 3 side-by-side cards ── */}
          <text x={0} y={EX_HDR}
            style={{ font: '600 15px var(--mono)', fill: 'var(--navy)', letterSpacing: '.07em' }}>
            EXAMPLES — click to switch
          </text>
          <line x1={0} y1={EX_RL}
            x2={3 * EX_CARD_W + 2 * EX_CARD_G} y2={EX_RL}
            stroke="var(--line)" strokeWidth={1.5} />

          {EXAMPLES.map((e, i) => {
            const cx = i * (EX_CARD_W + EX_CARD_G)
            return (
              <g key={e.label} onClick={() => setSel(i)} style={{ cursor: 'pointer' }}>
                <rect x={cx} y={EX_CARD_Y} width={EX_CARD_W} height={EX_CARD_H}
                  fill={sel === i ? '#e3e4f4' : 'rgba(255,255,255,.6)'}
                  stroke={sel === i ? 'var(--navy)' : '#c4c4c0'}
                  strokeWidth={sel === i ? 2.4 : 1.2} rx={3} />
                <text x={cx + EX_CARD_W / 2} y={EX_CARD_Y + 26} textAnchor="middle"
                  style={{ font: `${sel === i ? '700' : '500'} 16px var(--mono)`, fill: sel === i ? '#101234' : 'var(--ink-2)' }}>
                  {e.label} = {e.result}
                </text>
                <text x={cx + EX_CARD_W / 2} y={EX_CARD_Y + 46} textAnchor="middle"
                  style={{ font: '500 13px var(--mono)', fill: 'var(--ink-3)' }}>
                  {e.hex}
                </text>
              </g>
            )
          })}

          {/* ── DSP48E1 vs SOFTWARE (right of cards) ── */}
          {(() => {
            const rx = 3 * EX_CARD_W + 2 * EX_CARD_G + 52
            return (
              <>
                <text x={rx} y={EX_HDR}
                  style={{ font: '600 15px var(--mono)', fill: 'var(--navy)', letterSpacing: '.07em' }}>
                  DSP48E1 vs SOFTWARE
                </text>
                <line x1={rx} y1={EX_RL} x2={1728} y2={EX_RL}
                  stroke="var(--line)" strokeWidth={1.5} />
                {[
                  'Software shift-add: 32 – 64 cycles',
                  'DSP48E1 hardware: 3 cycles fixed',
                  '10 – 20× throughput improvement',
                  '236 unit tests + 31 pipeline checks',
                ].map((l, i) => (
                  <text key={i} x={rx} y={EX_CARD_Y + 14 + i * 28}
                    style={{ font: '400 17px var(--font)', fill: 'var(--ink-2)' }}>
                    {l}
                  </text>
                ))}
              </>
            )
          })()}
        </g>
      </svg>

      {/* ── Bottom notes row ──────────────────────────────────────────────── */}
      {/* SVG bottom = SVG_TOP + SVG_H = 108 + 709 = 817 px from .slide top  */}
      {/* Footer ≈ 1030 px — leaves ~213 px for 3-column notes               */}
      <div style={{
        position: 'absolute', left: 96, right: 96,
        top: SVG_TOP + SVG_H + 16,
        display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 40,
      }}>
        <Note label="DSP48E1 pipeline" d={1.1}>
          3 fixed cycles: operand latch → 25×18 core multiply → post-adder. Fully pipelined; one new result every cycle once filled.
        </Note>
        <Note label="Hazard handling" d={1.2}>
          stall_pipeline freezes IF/ID for 4 cycles (T4–T7). Skid buffer preserves add x4 state. EX-to-EX forwarding delivers result at T8.
        </Note>
        <Note label="Verification" d={1.3}>
          236 unit test vectors across all four MUL variants. 31 pipeline integration checks. Signed overflow corner cases confirmed.
        </Note>
      </div>
    </Frame>
  )
}
