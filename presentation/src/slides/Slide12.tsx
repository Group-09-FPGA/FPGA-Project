import { useCallback, useEffect, useState } from 'react'
import { Pause, Play, RotateCcw } from 'lucide-react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// div x9, x4, x1 where x4=63 (dividend), x1=7 (divisor)
// Quotient = 9 = 0b00001001, Remainder = 0
const DIVIDEND = 63
const DIVISOR  = 7
const QUOT_EXP = 9
const REM_EXP  = 0

// Pre-compute 33 iteration steps (bit 31 down to 0, then final)
function computeIterations() {
  const steps: { iter: number; partial: number; qBit: number; quot: number }[] = []
  let partial = 0
  let quot = 0
  // Radix-2 non-restoring: bits 31 down to 0
  for (let i = 31; i >= 0; i--) {
    const bit = (DIVIDEND >>> i) & 1
    partial = ((partial << 1) | bit)
    let qBit = 0
    if (partial >= DIVISOR) { qBit = 1; partial -= DIVISOR }
    quot = (quot << 1) | qBit
    steps.push({ iter: 31 - i, partial, qBit, quot: quot >>> 0 })
  }
  return steps
}
const STEPS = computeIterations()

const TOTAL_ITERS = 33  // 32 bit-iters + 1 init

function bin8(n: number) { return (n >>> 0).toString(2).padStart(8, '0') }
function hex32(n: number) { return '0x' + (n >>> 0).toString(16).toUpperCase().padStart(8, '0') }

// Stall timeline: 33 D-stage cells
const STALL_CELLS = TOTAL_ITERS

export default function Slide12() {
  const [iter, setIter] = useState(0)
  const [playing, setPlaying] = useState(true)

  const advance = useCallback(() => setIter(i => Math.min(i + 1, TOTAL_ITERS - 1)), [])

  useEffect(() => {
    if (!playing) return
    const id = setInterval(() => {
      setIter(i => {
        if (i >= TOTAL_ITERS - 1) { setPlaying(false); return i }
        return i + 1
      })
    }, 220)
    return () => clearInterval(id)
  }, [playing])

  const reset = useCallback(() => { setPlaying(false); setIter(0) }, [])
  const toggle = useCallback(() => {
    if (iter >= TOTAL_ITERS - 1) { setIter(0); setPlaying(true) }
    else setPlaying(p => !p)
  }, [iter])

  const stepData = STEPS[Math.min(iter, STEPS.length - 1)] ?? STEPS[STEPS.length - 1]
  const pct = iter / (TOTAL_ITERS - 1)
  const isDone = iter >= TOTAL_ITERS - 1

  // quotient bits display (MSB .. LSB), built up as we go
  const quotBits = (stepData.quot >>> 0).toString(2).padStart(32, '0')
  const visibleBits = iter  // how many bits of quotient are valid

  return (
    <Frame n={12} kicker="RV32M Extension · Radix-2 Serial Divider" title="Divider: div x9, x4, x1 — 33 Iteration Cycles">

      {/* ============ LEFT PANEL ============ */}
      <div style={{ position: 'absolute', left: 96, top: 180, width: 930 }}>

        {/* Algorithm card */}
        <div className="rise" style={{ ...delay(0.1), background: '#0f172a', borderRadius: 8, padding: '14px 18px', marginBottom: 14, border: '1.5px solid #1e293b' }}>
          <div style={{ font: '700 13px var(--mono)', color: '#38bdf8', letterSpacing: '0.1em', marginBottom: 8 }}>
            RADIX-2 NON-RESTORING ALGORITHM
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <div>
              {[
                { c: '#fde68a', t: `dividend = x4 = ${DIVIDEND} = 0b${bin8(DIVIDEND)}` },
                { c: '#fde68a', t: `divisor  = x1 = ${DIVISOR}  = 0b${bin8(DIVISOR)}` },
                { c: '#86efac', t: '' },
                { c: '#86efac', t: 'for i = 31 downto 0:' },
                { c: '#cbd5e1', t: '  pr = (pr << 1) | dividend[i]' },
                { c: '#cbd5e1', t: '  if pr >= divisor:' },
                { c: '#4ade80', t: '    q[i] = 1; pr -= divisor' },
                { c: '#f87171', t: '  else: q[i] = 0' },
                { c: '#86efac', t: '' },
                { c: '#fde68a', t: `Expected: q=${QUOT_EXP}, rem=${REM_EXP}` },
              ].map((l, i) => (
                <div key={i} style={{ font: '500 13px var(--mono)', color: l.c, lineHeight: 1.6 }}>{l.t || '\u00a0'}</div>
              ))}
            </div>
            <div style={{ borderLeft: '2px solid #1e293b', paddingLeft: 16 }}>
              <div style={{ font: '700 14px var(--mono)', color: '#38bdf8', marginBottom: 8 }}>RISC-V Edge Cases:</div>
              {[
                { op: 'x / 0', res: 'quotient = -1 (all 1s)', sub: 'remainder = x' },
                { op: '-2³¹ / -1', res: 'quotient = -2³¹', sub: 'no overflow exception' },
                { op: 'DIVU', res: 'unsigned result', sub: 'no sign extension' },
                { op: 'REM/REMU', res: 'return remainder', sub: 'same 33-cycle unit' },
              ].map(r => (
                <div key={r.op} style={{ marginBottom: 8 }}>
                  <span style={{ font: '700 13px var(--mono)', color: '#f59e0b' }}>{r.op}: </span>
                  <span style={{ font: '600 13px var(--mono)', color: '#e2e8f0' }}>{r.res}</span>
                  <div style={{ font: '400 12px var(--mono)', color: '#64748b', paddingLeft: 12 }}>{r.sub}</div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* ===== Live Iteration Visualizer ===== */}
        <div className="rise" style={{ ...delay(0.25), background: 'white', border: '1.5px solid #e2e8f0', borderRadius: 8, padding: '14px 18px', marginBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
            <div style={{ font: '700 14px var(--mono)', color: '#2a2e86', textTransform: 'uppercase', letterSpacing: '0.1em', flex: 1 }}>
              Live Iteration Trace
            </div>
            <div style={{ font: '800 28px var(--mono)', color: isDone ? '#15803d' : '#2a2e86', minWidth: 120, textAlign: 'center',
              background: isDone ? '#dcfce7' : '#e3e4f4', borderRadius: 6, padding: '2px 12px' }}>
              {isDone ? 'DONE!' : `Iter ${iter}`}
            </div>
            <button onClick={reset} style={{ border: '1px solid #e2e8f0', background: 'white', borderRadius: 4, padding: '6px 10px', cursor: 'pointer', color: '#6b7280', display: 'flex', alignItems: 'center', gap: 4 }}>
              <RotateCcw size={14} /> Reset
            </button>
            <button onClick={() => { if (!playing && iter < TOTAL_ITERS - 1) advance() }} disabled={playing || isDone}
              style={{ border: '1.5px solid #2a2e86', background: 'white', borderRadius: 4, padding: '6px 10px', cursor: 'pointer', color: '#2a2e86', fontSize: 12, fontFamily: 'var(--mono)', fontWeight: 600 }}>
              Step
            </button>
            <button onClick={toggle}
              style={{ border: '2px solid #2a2e86', background: playing ? '#2a2e86' : 'white', color: playing ? 'white' : '#2a2e86', borderRadius: 4, padding: '6px 14px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontFamily: 'var(--mono)', fontWeight: 700, fontSize: 13 }}>
              {isDone ? <><RotateCcw size={13} /> REPLAY</> : playing ? <><Pause size={13} fill="currentColor" /> PAUSE</> : <><Play size={13} fill="currentColor" /> PLAY</>}
            </button>
          </div>

          {/* Progress bar */}
          <div style={{ height: 16, background: '#f1f5f9', borderRadius: 8, overflow: 'hidden', marginBottom: 12 }}>
            <div style={{ height: '100%', width: `${pct * 100}%`, background: isDone ? '#15803d' : '#2a2e86', borderRadius: 8, transition: 'width 0.15s ease' }} />
          </div>

          {/* Iteration data row */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr', gap: 10, marginBottom: 12 }}>
            {[
              { label: 'Bit index', val: iter < 32 ? String(31 - iter) : '—', col: '#2a2e86' },
              { label: 'Partial Rem', val: iter < 32 ? String(stepData.partial) : String(REM_EXP), col: '#7c3aed' },
              { label: 'q-bit', val: iter < 32 ? String(stepData.qBit) : '—', col: stepData.qBit ? '#15803d' : '#dc2626' },
              { label: 'Quotient (so far)', val: isDone ? String(QUOT_EXP) : String(stepData.quot >>> 0), col: isDone ? '#15803d' : '#ea580c' },
            ].map(d => (
              <div key={d.label} style={{ textAlign: 'center', padding: '8px', background: '#f8fafc', borderRadius: 6, border: '1px solid #e2e8f0' }}>
                <div style={{ font: '600 11px var(--mono)', color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 4 }}>{d.label}</div>
                <div style={{ font: '700 22px var(--mono)', color: d.col }}>{d.val}</div>
              </div>
            ))}
          </div>

          {/* Quotient bit display — 32 tiny cells showing built-up quotient */}
          <div style={{ font: '600 11px var(--mono)', color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 6 }}>
            Quotient register (bit 31 ... bit 0):
          </div>
          <div style={{ display: 'flex', gap: 2 }}>
            {Array.from({ length: 32 }, (_, i) => {
              const bitPos = 31 - i
              const bitValid = iter > 0 && (31 - bitPos) < iter
              const bitVal = bitValid ? (QUOT_EXP >>> bitPos) & 1 : 0
              const isLast = bitValid && (31 - bitPos) === iter - 1
              return (
                <div key={i} style={{
                  width: 26, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: isLast ? '#fef3c7' : (bitValid ? (bitVal ? '#dcfce7' : '#fef2f2') : '#f8fafc'),
                  border: `${isLast ? '2px' : '1px'} solid ${isLast ? '#f59e0b' : (bitValid ? (bitVal ? '#86efac' : '#fca5a5') : '#e2e8f0')}`,
                  borderRadius: 3, font: '700 14px var(--mono)',
                  color: bitValid ? (bitVal ? '#15803d' : '#dc2626') : '#cbd5e1',
                }}>
                  {bitValid ? bitVal : '·'}
                </div>
              )
            })}
          </div>
        </div>

        {/* ===== Stall timeline SVG ===== */}
        <div className="rise" style={{ ...delay(0.4) }}>
          <div style={{ font: '600 12px var(--mono)', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 8 }}>
            Pipeline Stall Timeline (33 cycles, m_busy HIGH):
          </div>
          <svg width={900} height={72} viewBox="0 0 900 72">
            <defs><marker id="ah12" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#2a2e86"/></marker></defs>
            {/* IF/ID cell */}
            <rect x={0} y={10} width={72} height={36} fill="#e8eaf6" stroke="#9fa8da" strokeWidth={1.5} rx={3} />
            <text x={36} y={33} textAnchor="middle" style={{ font: '700 12px var(--mono)', fill: '#1a237e' }}>IF/ID</text>
            <text x={36} y={47} textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#6b7280' }}>div</text>

            {/* D cells (33 stall iterations) */}
            {Array.from({ length: STALL_CELLS }, (_, i) => {
              const x = 76 + i * 23
              const done = i < iter
              const active = i === iter - 1
              return (
                <g key={i}>
                  <rect x={x} y={10} width={22} height={36}
                    fill={active ? '#0d3859' : (done ? '#1e4a78' : '#f8fafc')}
                    stroke={active ? '#062340' : (done ? '#1e4a78' : '#e2e8f0')}
                    strokeWidth={1} rx={1} />
                  {(i === 0 || i === 16 || i === 32) && (
                    <text x={x + 11} y={55} textAnchor="middle" style={{ font: '500 9px var(--mono)', fill: '#94a3b8' }}>T{i + 17}</text>
                  )}
                </g>
              )
            })}
            {/* MEM/WB cell */}
            <rect x={76 + STALL_CELLS * 23} y={10} width={72} height={36}
              fill={isDone ? '#d4eed8' : '#f8fafc'} stroke={isDone ? '#66bb6a' : '#e2e8f0'} strokeWidth={1.5} rx={3} />
            <text x={76 + STALL_CELLS * 23 + 36} y={33} textAnchor="middle"
              style={{ font: '700 12px var(--mono)', fill: isDone ? '#1b5e20' : '#94a3b8' }}>MEM/WB</text>

            {/* Stall annotation */}
            <line x1={76} y1={4} x2={76 + STALL_CELLS * 23} y2={4} stroke="#b45309" strokeWidth={1.5} markerEnd="url(#ah12)" markerStart="url(#ah12)" />
            <text x={76 + STALL_CELLS * 11.5} y={2} textAnchor="middle" style={{ font: '600 11px var(--mono)', fill: '#b45309' }}>
              stall_pipeline HIGH · m_busy HIGH · {STALL_CELLS} cycles
            </text>
          </svg>
        </div>
      </div>

      {/* ============ RIGHT PANEL ============ */}
      <div style={{ position: 'absolute', left: 1060, top: 180, right: 86, width: 740 }}>

        {/* Hardware architecture */}
        <div className="rise" style={{ ...delay(0.2), background: 'white', border: '1.5px solid #e2e8f0', borderLeft: '5px solid #2a2e86', borderRadius: 6, padding: '14px 18px', marginBottom: 14 }}>
          <div style={{ font: '700 14px var(--mono)', color: '#2a2e86', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 10 }}>
            Hardware DIV Unit Architecture
          </div>
          {[
            { icon: '⚙', label: '32-bit shift register', desc: 'Partial remainder accumulates each iteration' },
            { icon: '📦', label: '33-bit quotient accumulator', desc: 'Builds quotient LSB → MSB over 32 iterations' },
            { icon: '🔢', label: 'State counter [0..32]', desc: 'Drives FSM: init (0) → compute (1..32) → done' },
            { icon: '±', label: 'Signed fixup logic', desc: '2\'s complement pre-negation + sign-correct result' },
          ].map(r => (
            <div key={r.label} style={{ display: 'flex', gap: 12, marginBottom: 8, alignItems: 'flex-start' }}>
              <span style={{ fontSize: 18, flexShrink: 0 }}>{r.icon}</span>
              <div>
                <div style={{ font: '600 15px var(--font)', color: '#16181d' }}>{r.label}</div>
                <div style={{ font: '400 13px var(--font)', color: '#6b7280' }}>{r.desc}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Why 33 cycles */}
        <div className="rise" style={{ ...delay(0.32), background: '#fffbeb', border: '1.5px solid #fde68a', borderLeft: '5px solid #f59e0b', borderRadius: 6, padding: '14px 18px', marginBottom: 14 }}>
          <div style={{ font: '700 14px var(--mono)', color: '#b45309', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 8 }}>
            Why 33 Cycles?
          </div>
          {[
            '32-bit dividend → 32 bit-iterations',
            '+ 1 cycle for initialization / control',
            '= 33 total cycles with stall_pipeline HIGH',
            '',
            'Frontend uses Skid Buffer to hold next',
            'decoded instruction — zero instruction loss!',
          ].map((l, i) => (
            <div key={i} style={{ font: `${l === '' ? '400' : '500'} 15px var(--font)`, color: '#92400e', lineHeight: 1.6 }}>{l || '\u00a0'}</div>
          ))}
        </div>

        {/* Comparison box */}
        <div className="rise" style={{ ...delay(0.44), background: '#0f172a', border: '1.5px solid #1e293b', borderRadius: 8, padding: '14px 18px' }}>
          <div style={{ font: '700 13px var(--mono)', color: '#38bdf8', letterSpacing: '0.1em', marginBottom: 10 }}>
            TIMING COMPARISON
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div>
              <div style={{ font: '700 12px var(--mono)', color: '#f87171', marginBottom: 6 }}>Software Loop DIV</div>
              <div style={{ font: '400 13px var(--font)', color: '#94a3b8', lineHeight: 1.5 }}>
                ~32–192 instructions<br/>
                Cache misses possible<br/>
                Non-deterministic
              </div>
            </div>
            <div>
              <div style={{ font: '700 12px var(--mono)', color: '#4ade80', marginBottom: 6 }}>Hardware Radix-2 DIV</div>
              <div style={{ font: '400 13px var(--font)', color: '#94a3b8', lineHeight: 1.5 }}>
                <strong style={{ color: '#4ade80' }}>Exactly 33 cycles</strong><br/>
                Always deterministic<br/>
                All 4 DIV opcodes
              </div>
            </div>
          </div>
          <div style={{ marginTop: 12, background: '#1e293b', borderRadius: 6, padding: '10px 14px', textAlign: 'center' }}>
            <div style={{ font: '700 18px var(--mono)', color: '#fde68a' }}>
              div x9, x4, x1: 63÷7 = 9 (rem 0)
            </div>
            <div style={{ font: '500 14px var(--mono)', color: '#94a3b8', marginTop: 4 }}>
              {hex32(DIVIDEND)} ÷ {hex32(DIVISOR)} = {hex32(QUOT_EXP)}
            </div>
          </div>
        </div>
      </div>
    </Frame>
  )
}
