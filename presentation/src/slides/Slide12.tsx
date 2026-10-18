import { useCallback, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { Pause, Play, RotateCcw } from 'lucide-react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// div x9, x4, x1 — x4=63, x1=7 → quotient=9, remainder=0
const DIVIDEND = 63, DIVISOR = 7, QUOT_EXP = 9, REM_EXP = 0
const TOTAL_ITERS = 33

function computeSteps() {
  const steps: { partial: number; qBit: number; quot: number }[] = []
  let partial = 0, quot = 0
  for (let i = 31; i >= 0; i--) {
    const bit = (DIVIDEND >>> i) & 1
    partial = (partial << 1) | bit
    const qBit = partial >= DIVISOR ? 1 : 0
    if (qBit) partial -= DIVISOR
    quot = (quot << 1) | qBit
    steps.push({ partial, qBit, quot: quot >>> 0 })
  }
  return steps
}
const STEPS = computeSteps()

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 20px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

export default function Slide12() {
  const [iter, setIter] = useState(0)
  const [playing, setPlaying] = useState(true)

  const reset = useCallback(() => { setPlaying(false); setIter(0) }, [])
  const toggle = useCallback(() => {
    if (iter >= TOTAL_ITERS - 1) { setIter(0); setPlaying(true) }
    else setPlaying(p => !p)
  }, [iter])

  useEffect(() => {
    if (!playing) return
    const id = setInterval(() => setIter(i => {
      if (i >= TOTAL_ITERS - 1) { setPlaying(false); return i }
      return i + 1
    }), 210)
    return () => clearInterval(id)
  }, [playing])

  const step = STEPS[Math.min(iter, STEPS.length - 1)]
  const pct = iter / (TOTAL_ITERS - 1)
  const isDone = iter >= TOTAL_ITERS - 1

  return (
    <Frame n={8} kicker="RV32M Extension · Radix-2 Serial Divider" title="Divider: div x9, x4, x1 — 33 iteration cycles">
      <svg width={1728} height={660} viewBox="0 -10 1728 660" overflow="visible"
        style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="ah12" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ── Algorithm (left column) ───────────────────────────────── */}
        <g className="rise" style={delay(0.1)}>
          <text x={0} y={20} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            RADIX-2 NON-RESTORING ALGORITHM
          </text>
          <rect x={0} y={30} width={580} height={230} fill="rgba(255,255,255,.55)" stroke="var(--ink-2)" strokeWidth={1.5} />
          {[
            `dividend = x4 = ${DIVIDEND} = 0b00111111`,
            `divisor  = x1 = ${DIVISOR}  = 0b00000111`,
            ``,
            `for i = 31 downto 0:`,
            `  pr = (pr << 1) | dividend[i]`,
            `  if pr >= divisor:`,
            `    quotient[i] = 1`,
            `    pr = pr − divisor`,
            `  else: quotient[i] = 0`,
            ``,
            `result: quotient = ${QUOT_EXP} = 0b00001001  rem = ${REM_EXP}`,
          ].map((l, i) => (
            <text key={i} x={18} y={58 + i * 19}
              style={{ font: '500 16px var(--mono)', fill: l.startsWith('dividend') || l.startsWith('divisor') || l.startsWith('result') ? 'var(--navy)' : 'var(--ink-2)' }}>
              {l}
            </text>
          ))}
        </g>

        {/* ── RISC-V edge cases ─────────────────────────────────────── */}
        <g className="rise" style={delay(0.2)}>
          <text x={0} y={286} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            RISC-V SPEC EDGE CASES (§M-EXT)
          </text>
          <line x1={0} y1={296} x2={580} y2={296} stroke="var(--line)" strokeWidth={1.5} />
          {[
            { op: 'x / 0',      res: 'quotient = −1  rem = x' },
            { op: '−2³¹ / −1', res: 'quotient = −2³¹  rem = 0' },
            { op: 'DIVU',       res: 'unsigned — no sign extension' },
            { op: 'REM / REMU', res: 'return remainder register' },
          ].map((r, i) => (
            <g key={r.op}>
              <line x1={0} y1={336 + i * 44} x2={580} y2={336 + i * 44} stroke="#e2e8f0" strokeWidth={1} />
              <text x={0} y={326 + i * 44} style={{ font: '700 20px var(--mono)', fill: 'var(--ink)' }}>{r.op}</text>
              <text x={230} y={326 + i * 44} style={{ font: '400 20px var(--font)', fill: 'var(--ink-2)' }}>{r.res}</text>
            </g>
          ))}
        </g>

        {/* ── Hardware architecture ─────────────────────────────────── */}
        <g className="rise" style={delay(0.3)}>
          <text x={0} y={512} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            HARDWARE ARCHITECTURE
          </text>
          <line x1={0} y1={522} x2={580} y2={522} stroke="var(--line)" strokeWidth={1.5} />
          {[
            '32-bit shift register — partial remainder',
            '33-bit quotient accumulator (LSB → MSB)',
            'State counter [0..32] drives FSM',
            'Signed fixup: 2\'s complement pre-negation',
            'Skid buffer holds next decoded instruction',
          ].map((l, i) => (
            <text key={i} x={0} y={544 + i * 20}
              style={{ font: '400 16px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
        </g>

        {/* ── RIGHT: Live iteration visualizer ──────────────────────── */}
        <g className="rise" style={delay(0.4)}>
          <text x={650} y={20} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            LIVE ITERATION TRACE
          </text>

          {/* Progress bar */}
          <rect x={650} y={30} width={1070} height={22} fill="rgba(255,255,255,.55)" stroke="var(--ink-2)" strokeWidth={1.2} />
          <rect x={650} y={30} width={pct * 1070} height={22}
            fill={isDone ? 'var(--ok)' : 'var(--navy)'}
            style={{ transition: 'width 0.15s ease' }} />

          {/* Big counter */}
          <text x={1180} y={96} textAnchor="middle"
            style={{ font: '800 56px var(--mono)', fill: isDone ? 'var(--ok)' : 'var(--navy)' }}>
            {isDone ? 'DONE' : `Iter ${iter}`}
          </text>

          {/* Stat cells */}
          {[
            { label: 'Bit index', val: iter < 32 ? String(31 - iter) : '—' },
            { label: 'Partial rem', val: String(step.partial) },
            { label: 'q-bit', val: String(step.qBit) },
            { label: 'Quotient', val: isDone ? `${QUOT_EXP}` : String(step.quot) },
            { label: 'Remainder', val: isDone ? `${REM_EXP}` : '...' },
          ].map((d, i) => (
            <g key={d.label}>
              <rect x={650 + i * 215} y={108} width={208} height={80}
                fill="rgba(255,255,255,.7)" stroke="var(--ink-2)" strokeWidth={1.2} />
              <text x={650 + i * 215 + 104} y={140} textAnchor="middle"
                style={{ font: '600 14px var(--mono)', fill: 'var(--ink-3)', textTransform: 'uppercase', letterSpacing: '.06em' }}>
                {d.label}
              </text>
              <text x={650 + i * 215 + 104} y={170} textAnchor="middle"
                style={{ font: '800 28px var(--mono)', fill: 'var(--navy)' }}>{d.val}</text>
            </g>
          ))}

          {/* Quotient bit register — 32 cells */}
          <text x={650} y={218} style={{ font: '600 16px var(--mono)', fill: 'var(--ink-3)', letterSpacing: '.06em' }}>
            QUOTIENT REGISTER (bit 31..0)
          </text>
          {Array.from({ length: 32 }, (_, i) => {
            const bitPos = 31 - i
            const valid = iter > 0 && (31 - bitPos) < iter
            const bitVal = valid ? (QUOT_EXP >>> bitPos) & 1 : -1
            const isLatest = valid && (31 - bitPos) === iter - 1
            return (
              <g key={i}>
                <rect x={650 + i * 33} y={228} width={32} height={32}
                  fill={isLatest ? '#e3e4f4' : (valid ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isLatest ? 'var(--navy)' : (valid ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isLatest ? 2.4 : 1} />
                <text x={650 + i * 33 + 16} y={250} textAnchor="middle"
                  style={{ font: `${bitVal >= 0 ? '700' : '400'} 15px var(--mono)`,
                    fill: bitVal >= 0 ? 'var(--ink)' : 'var(--ink-3)' }}>
                  {bitVal >= 0 ? bitVal : '·'}
                </text>
              </g>
            )
          })}
        </g>

        {/* ── Stall pipeline timeline ───────────────────────────────── */}
        <g className="rise" style={delay(0.55)}>
          <text x={650} y={298} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            PIPELINE STALL TIMELINE  ({TOTAL_ITERS} cycles, m_busy HIGH)
          </text>
          <line x1={650} y1={308} x2={1720} y2={308} stroke="var(--line)" strokeWidth={1.5} />

          {/* IF/ID div cell */}
          <rect x={650} y={316} width={72} height={40} fill="rgba(255,255,255,.55)" stroke="#8b8f98" strokeWidth={1.4} />
          <text x={686} y={342} textAnchor="middle" style={{ font: '700 15px var(--mono)', fill: 'var(--ink-2)' }}>IF/ID</text>

          {/* D-stage cells */}
          {Array.from({ length: TOTAL_ITERS }, (_, i) => {
            const x = 726 + i * 29
            const done = i < iter
            return (
              <rect key={i} x={x} y={316} width={28} height={40}
                fill={done ? (i === iter - 1 ? '#e3e4f4' : 'rgba(42,46,134,.15)') : 'rgba(255,255,255,.3)'}
                stroke={done ? (i === iter - 1 ? 'var(--navy)' : 'rgba(42,46,134,.3)') : '#e2e8f0'}
                strokeWidth={i === iter - 1 ? 2 : 0.8} />
            )
          })}

          {/* MEM/WB */}
          <rect x={726 + TOTAL_ITERS * 29} y={316} width={72} height={40}
            fill={isDone ? '#e3e4f4' : 'rgba(255,255,255,.3)'}
            stroke={isDone ? 'var(--navy)' : '#e2e8f0'} strokeWidth={isDone ? 2 : 1} />
          <text x={726 + TOTAL_ITERS * 29 + 36} y={342} textAnchor="middle"
            style={{ font: '700 14px var(--mono)', fill: isDone ? 'var(--navy)' : 'var(--ink-3)' }}>WB</text>

          {/* Stall annotation */}
          <line x1={726} y1={368} x2={726 + TOTAL_ITERS * 29} y2={368} stroke="var(--warn)" strokeWidth={1.4}
            markerStart="url(#ah12)" markerEnd="url(#ah12)" />
          <text x={726 + TOTAL_ITERS * 14.5} y={386} textAnchor="middle"
            style={{ font: '600 17px var(--mono)', fill: 'var(--warn)' }}>
            {TOTAL_ITERS} stall cycles · frontend frozen
          </text>
        </g>

        {/* Why 33 cycles explanation */}
        <g className="rise" style={delay(0.65)}>
          <text x={650} y={424} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            WHY 33 CYCLES?
          </text>
          <line x1={650} y1={434} x2={1720} y2={434} stroke="var(--line)" strokeWidth={1.5} />
          {[
            '32-bit dividend → 32 bit-iterations',
            '+ 1 cycle for partial-remainder initialisation',
            '= 33 total cycles with stall_pipeline HIGH',
            'Skid buffer preserves decoded addi x10 — no instruction lost',
          ].map((l, i) => (
            <text key={i} x={650} y={462 + i * 34}
              style={{ font: '400 22px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
          <text x={650} y={606} style={{ font: '700 26px var(--font)', fill: 'var(--navy)' }}>
            63 ÷ 7 = 9  rem 0 · verified against RISC-V ISA spec
          </text>
        </g>
      </svg>

      {/* ── Control buttons — top-right above the progress bar ────────── */}
      <div style={{ position: 'absolute', right: 96, top: 160, display: 'flex', gap: 10, alignItems: 'center' }}>
        <button onClick={reset}
          style={{ display:'flex', alignItems:'center', gap:5, font:'600 14px var(--mono)', color:'var(--ink-2)',
            background:'white', border:'1.5px solid #c4c4c0', borderRadius:3, padding:'5px 12px', cursor:'pointer' }}>
          <RotateCcw size={13} /> Reset
        </button>
        <button onClick={() => setIter(i => Math.min(i + 1, TOTAL_ITERS - 1))} disabled={playing || isDone}
          style={{ font:'600 14px var(--mono)', color:'var(--navy)', background:'white',
            border:'1.5px solid var(--navy)', borderRadius:3, padding:'5px 14px', cursor:'pointer' }}>
          Step
        </button>
        <button onClick={toggle}
          style={{ display:'flex', alignItems:'center', gap:6, font:'700 14px var(--mono)',
            background: playing ? 'var(--navy)' : 'white', color: playing ? 'white' : 'var(--navy)',
            border:'2px solid var(--navy)', borderRadius:3, padding:'6px 18px', cursor:'pointer' }}>
          {isDone ? <><RotateCcw size={13}/> REPLAY</> : playing ? <><Pause size={13} fill="currentColor"/> PAUSE</> : <><Play size={13} fill="currentColor"/> PLAY</>}
        </button>
      </div>

      <div style={{ position:'absolute', left:96, right:96, top:874, display:'grid', gridTemplateColumns:'repeat(3,1fr)', gap:36 }}>
        <Note label="Algorithm" d={1.0}>Radix-2 non-restoring: shift partial remainder, test against divisor, accumulate quotient bit. 32 iterations per 32-bit dividend.</Note>
        <Note label="Hardware" d={1.1}>32-bit shift register for partial remainder. State counter 0–32 drives FSM. Signed fixup via 2's-complement pre-negation.</Note>
        <Note label="Pipeline cost" d={1.2}>33-cycle stall (m_busy HIGH). Skid buffer holds decoded next instruction — no fetch lost. All four DIV/REM opcodes share this unit.</Note>
      </div>
    </Frame>
  )
}
