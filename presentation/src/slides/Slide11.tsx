import { useState } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

const EXAMPLES = [
  { a: 7, b: 9, op: 'mul', desc: 'Trace example (mul x3,x1,x2)', result: 63, mulh: 0, signed: true },
  { a: -2, b: 5, op: 'mul', desc: 'Signed multiplication', result: -10, mulh: -1, signed: true },
  { a: 0xFFFF, b: 0xFFFF, op: 'mulhu', desc: 'Unsigned upper half (MULHU)', result: 0xFFFE0001, mulh: 0xFFFE, signed: false },
]

function hex32(n: number) {
  return '0x' + (n >>> 0).toString(16).toUpperCase().padStart(8, '0')
}

const STAGE_COLORS = ['#1e40af', '#7c3aed', '#15803d']
const STAGE_BG = ['#dbeafe', '#ede9fe', '#dcfce7']
const STAGES_DESC = [
  { cycle: 'M1', title: 'Operand Latch', hw: 'DSP48E1 Pre-Adder + AREG/BREG', detail: 'Register A & B operands into DSP input registers. Pipeline stage 1 begins.' },
  { cycle: 'M2', title: 'Core Multiply', hw: 'DSP48E1 25×18 Multiply Core + MREG', detail: '25-bit × 18-bit hardware multiplier computes 48-bit partial product in this cycle.' },
  { cycle: 'M3', title: 'Result Accumulate', hw: 'DSP48E1 Post-Adder + PREG', detail: 'Post-accumulator assembles final 64-bit product. Lower/upper 32-bit extracted.' },
]

const BOX_W = 260
const BOX_H = 150
const BOX_GAP = 70
const BOX_Y = 50
const BOX_START_X = 20
const stageCX = (i: number) => BOX_START_X + i * (BOX_W + BOX_GAP) + BOX_W / 2

export default function Slide11() {
  const [sel, setSel] = useState(0)
  const ex = EXAMPLES[sel]
  const resultHex = hex32(ex.result)
  const aHex = hex32(ex.a)
  const bHex = hex32(ex.b)
  const partialProduct = BigInt(ex.a) * BigInt(ex.b)

  const tokenPath = [0, 1, 2].map(i => `${i === 0 ? 'M' : 'L'}${stageCX(i)},${BOX_Y + BOX_H / 2}`).join(' ')

  return (
    <Frame n={11} kicker="RV32M Extension · DSP48E1 Hardware" title="Multiplier: mul x3, x1, x2 — 3 Pipeline Cycles">
      {/* LEFT: 3-stage pipeline SVG */}
      <svg width={950} height={480} viewBox="0 0 950 480"
        style={{ position: 'absolute', left: 86, top: 175 }}>
        <defs>
          <marker id="ah11" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
          <filter id="glow11"><feGaussianBlur stdDeviation="4" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
        </defs>

        {/* Input arrow */}
        <line x1={0} y1={BOX_Y + BOX_H / 2} x2={BOX_START_X - 2} y2={BOX_Y + BOX_H / 2}
          stroke="#2a2e86" strokeWidth={2.5} markerEnd="url(#ah11)" />
        <text x={0} y={BOX_Y + BOX_H / 2 - 14} style={{ font: '500 14px var(--mono)', fill: '#2a2e86' }}>
          EX stage input
        </text>
        <text x={0} y={BOX_Y + BOX_H / 2 + 20} style={{ font: '700 15px var(--mono)', fill: '#ea580c' }}>
          A={aHex}
        </text>
        <text x={0} y={BOX_Y + BOX_H / 2 + 38} style={{ font: '700 15px var(--mono)', fill: '#15803d' }}>
          B={bHex}
        </text>

        {/* 3 Stage boxes */}
        {STAGES_DESC.map((s, i) => {
          const x = BOX_START_X + i * (BOX_W + BOX_GAP)
          return (
            <g key={s.cycle}>
              <rect x={x} y={BOX_Y} width={BOX_W} height={BOX_H} fill={STAGE_BG[i]} stroke={STAGE_COLORS[i]} strokeWidth={2.2} rx={8} />
              {/* Cycle badge */}
              <rect x={x + 8} y={BOX_Y + 8} width={44} height={28} rx={14} fill={STAGE_COLORS[i]} />
              <text x={x + 30} y={BOX_Y + 28} textAnchor="middle"
                style={{ font: '700 17px var(--mono)', fill: 'white' }}>{s.cycle}</text>
              <text x={x + BOX_W / 2} y={BOX_Y + 48} textAnchor="middle"
                style={{ font: '700 18px var(--font)', fill: STAGE_COLORS[i] }}>{s.title}</text>
              <text x={x + BOX_W / 2} y={BOX_Y + 68} textAnchor="middle"
                style={{ font: '600 12px var(--mono)', fill: '#6b7280' }}>{s.hw}</text>
              {/* Stage-specific values */}
              {i === 0 && (
                <>
                  <text x={x + BOX_W / 2} y={BOX_Y + 92} textAnchor="middle"
                    style={{ font: '600 14px var(--mono)', fill: '#ea580c' }}>AREG={aHex}</text>
                  <text x={x + BOX_W / 2} y={BOX_Y + 110} textAnchor="middle"
                    style={{ font: '600 14px var(--mono)', fill: '#15803d' }}>BREG={bHex}</text>
                </>
              )}
              {i === 1 && (
                <text x={x + BOX_W / 2} y={BOX_Y + 98} textAnchor="middle"
                  style={{ font: '600 13px var(--mono)', fill: '#5b21b6' }}>
                  MREG = A × B (48-bit)
                </text>
              )}
              {i === 2 && (
                <>
                  <text x={x + BOX_W / 2} y={BOX_Y + 90} textAnchor="middle"
                    style={{ font: '700 17px var(--mono)', fill: '#15803d' }}>
                    {ex.a} × {ex.b} = {ex.result}
                  </text>
                  <text x={x + BOX_W / 2} y={BOX_Y + 112} textAnchor="middle"
                    style={{ font: '600 14px var(--mono)', fill: '#6b7280' }}>
                    {resultHex}
                  </text>
                </>
              )}
              {/* Arrow to next */}
              {i < 2 && (
                <line x1={x + BOX_W} y1={BOX_Y + BOX_H / 2} x2={x + BOX_W + BOX_GAP - 2} y2={BOX_Y + BOX_H / 2}
                  stroke="#2a2e86" strokeWidth={2.5} markerEnd="url(#ah11)" />
              )}
            </g>
          )
        })}

        {/* Result output arrow */}
        <line x1={BOX_START_X + 2 * (BOX_W + BOX_GAP) + BOX_W} y1={BOX_Y + BOX_H / 2}
          x2={BOX_START_X + 2 * (BOX_W + BOX_GAP) + BOX_W + 50} y2={BOX_Y + BOX_H / 2}
          stroke="#15803d" strokeWidth={3} markerEnd="url(#ah11)" />
        <text x={BOX_START_X + 2 * (BOX_W + BOX_GAP) + BOX_W + 55} y={BOX_Y + BOX_H / 2 - 8}
          style={{ font: '700 16px var(--mono)', fill: '#15803d' }}>
          x3 = {ex.result}
        </text>
        <text x={BOX_START_X + 2 * (BOX_W + BOX_GAP) + BOX_W + 55} y={BOX_Y + BOX_H / 2 + 16}
          style={{ font: '500 13px var(--mono)', fill: '#6b7280' }}>
          RegFile WB
        </text>

        {/* Animated tokens */}
        <circle r={9} fill="#2a2e86" filter="url(#glow11)">
          <animateMotion dur="1.8s" begin="0s" repeatCount="indefinite" path={tokenPath} />
        </circle>
        <circle r={7} fill="#ea580c" opacity={0.7}>
          <animateMotion dur="1.8s" begin="0.6s" repeatCount="indefinite" path={tokenPath} />
        </circle>

        {/* ===== Pipeline timing table ===== */}
        {(() => {
          const tY = BOX_Y + BOX_H + 40
          const cycles = ['T3', 'T4', 'T5', 'T6', 'T7', 'T8']
          const events = [
            ['IF/ID', '-', '-', '-', '-', '-'],
            ['EX/mul', 'M1', 'M2', 'M3', '-', '-'],
            ['-', 'HOLD', 'HOLD', 'HOLD', 'EX→fwd', 'MEM/WB'],
          ]
          const labels = ['IF/ID (fetch)', 'EX (mul)', 'add x4 (waiting)']
          const CW = 82, CH = 36, LW = 130
          return (
            <g>
              <text x={0} y={tY - 10} style={{ font: '700 15px var(--mono)', fill: '#2a2e86', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
                Pipeline Timing — mul x3, x1, x2
              </text>
              {/* Header row */}
              {cycles.map((c, i) => (
                <g key={c}>
                  <rect x={LW + i * CW} y={tY} width={CW - 2} height={CH} fill="#f1f5f9" stroke="#e2e8f0" strokeWidth={1} rx={2} />
                  <text x={LW + i * CW + CW / 2 - 1} y={tY + 23} textAnchor="middle"
                    style={{ font: '700 15px var(--mono)', fill: '#2a2e86' }}>{c}</text>
                </g>
              ))}
              {/* Event rows */}
              {events.map((row, ri) => (
                <g key={ri}>
                  <text x={0} y={tY + (ri + 1) * CH + 22} style={{ font: '500 13px var(--mono)', fill: '#6b7280' }}>{labels[ri]}</text>
                  {row.map((cell, ci) => {
                    const isM = cell.startsWith('M')
                    const isHold = cell === 'HOLD'
                    const isFwd = cell.includes('fwd')
                    return (
                      <g key={ci}>
                        <rect x={LW + ci * CW} y={tY + (ri + 1) * CH} width={CW - 2} height={CH}
                          fill={isM ? STAGE_BG[parseInt(cell[1]) - 1] : (isHold ? '#fef3c7' : (isFwd ? '#dcfce7' : 'rgba(255,255,255,0.7)'))}
                          stroke={isM ? STAGE_COLORS[parseInt(cell[1]) - 1] : (isHold ? '#d97706' : (isFwd ? '#15803d' : '#e2e8f0'))}
                          strokeWidth={isM ? 2 : 1} rx={2} />
                        <text x={LW + ci * CW + CW / 2 - 1} y={tY + (ri + 1) * CH + 23} textAnchor="middle"
                          style={{ font: `${isM ? '700' : '500'} 13px var(--mono)`, fill: isM ? STAGE_COLORS[parseInt(cell[1]) - 1] : (isHold ? '#b45309' : (isFwd ? '#15803d' : '#6b7280')) }}>
                          {cell}
                        </text>
                      </g>
                    )
                  })}
                </g>
              ))}
              <text x={LW} y={tY + 4 * CH + 22}
                style={{ font: '600 14px var(--mono)', fill: '#b45309' }}>
                {'stall_pipeline HIGH ──────────────── (4 cycles) ──────────────── m_done ✓'}
              </text>
            </g>
          )
        })()}
      </svg>

      {/* RIGHT: Why DSP48 + opcodes + example selector */}
      <div style={{ position: 'absolute', left: 1070, top: 175, width: 750, right: 96 }}>
        {/* Example selector */}
        <div className="rise" style={{ ...delay(0.15), marginBottom: 16, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {EXAMPLES.map((e, i) => (
            <button key={i} onClick={() => setSel(i)} style={{
              font: '600 13px var(--mono)', padding: '6px 14px', borderRadius: 4, cursor: 'pointer',
              background: sel === i ? 'var(--navy)' : 'white',
              color: sel === i ? 'white' : 'var(--navy)',
              border: '1.5px solid var(--navy)', letterSpacing: '0.04em',
            }}>
              {e.op.toUpperCase()}: {e.a} × {e.b}
            </button>
          ))}
        </div>

        {/* Why DSP48 */}
        <div className="rise" style={{ ...delay(0.25), background: '#0f172a', border: '1.5px solid #1e293b', borderRadius: 8, padding: '16px 20px', marginBottom: 12 }}>
          <div style={{ font: '700 14px var(--mono)', color: '#38bdf8', letterSpacing: '0.1em', marginBottom: 10 }}>
            WHY DSP48E1 HARDWARE?
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
            <div>
              <div style={{ font: '700 13px var(--mono)', color: '#f87171', marginBottom: 6 }}>❌ Software Shift-Add</div>
              <div style={{ font: '400 13px var(--font)', color: '#94a3b8', lineHeight: 1.5 }}>
                32-iteration loop using shift + add<br />
                32–64 cycles latency<br />
                Burns entire CPU pipeline
              </div>
            </div>
            <div>
              <div style={{ font: '700 13px var(--mono)', color: '#4ade80', marginBottom: 6 }}>✓ DSP48E1 Hardware</div>
              <div style={{ font: '400 13px var(--font)', color: '#94a3b8', lineHeight: 1.5 }}>
                Dedicated silicon multiply unit<br />
                <strong style={{ color: '#4ade80' }}>Fixed 3 cycles latency</strong><br />
                Pipelined: 1 result/cycle throughput
              </div>
            </div>
          </div>
        </div>

        {/* All 4 MUL opcodes */}
        <div className="rise" style={{ ...delay(0.35), background: 'white', border: '1.5px solid #e2e8f0', borderRadius: 8, padding: '14px 18px', marginBottom: 12 }}>
          <div style={{ font: '700 13px var(--mono)', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 10 }}>
            All 4 RV32M Multiply Opcodes
          </div>
          {[
            { op: 'MUL', desc: 'Lower 32 bits of signed×signed product', ex: `${ex.a}×${ex.b} = ${ex.result}` },
            { op: 'MULH', desc: 'Upper 32 bits of signed×signed (64-bit)', ex: `${ex.a}×${ex.b} >> 32 = ${ex.mulh}` },
            { op: 'MULHU', desc: 'Upper 32 bits of unsigned×unsigned', ex: '0xFFFF×0xFFFF >> 32 = 0xFFFE' },
            { op: 'MULHSU', desc: 'Upper 32 bits of signed×unsigned', ex: 'rs1 signed × rs2 unsigned' },
          ].map(r => (
            <div key={r.op} style={{ display: 'grid', gridTemplateColumns: '100px 1fr', gap: 8, borderTop: '1px solid #f1f5f9', paddingTop: 6, marginTop: 6 }}>
              <div style={{ font: '700 17px var(--mono)', color: '#2a2e86' }}>{r.op}</div>
              <div>
                <div style={{ font: '400 14px var(--font)', color: '#334155' }}>{r.desc}</div>
                <div style={{ font: '600 13px var(--mono)', color: '#6b7280', marginTop: 2 }}>{r.ex}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Edge case card */}
        <div className="rise" style={{ ...delay(0.5), background: '#eff6ff', border: '1.5px solid #bfdbfe', borderLeft: '5px solid #2a2e86', borderRadius: 6, padding: '12px 18px' }}>
          <div style={{ font: '700 13px var(--mono)', color: '#2a2e86', marginBottom: 6 }}>✓ Verification: 236 unit test vectors + 31 pipeline checks</div>
          <div style={{ font: '400 14px var(--font)', color: '#1e40af' }}>All MUL variants verified against RISC-V ISA spec, including signed overflow corner cases and pipeline forwarding paths from M-unit writeback.</div>
        </div>
      </div>
    </Frame>
  )
}
