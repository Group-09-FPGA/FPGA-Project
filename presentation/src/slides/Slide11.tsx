import { useState } from 'react'
import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

interface BoxProps { x:number; y:number; w:number; h:number; t:string; s?:string; isNew?:boolean; d?:number }
function Box({ x, y, w, h, t, s, isNew, d=0 }: BoxProps) {
  const cy = y + h / 2
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h}
        fill={isNew ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
        stroke={isNew ? 'var(--navy)' : '#8b8f98'} strokeWidth={isNew ? 2.6 : 1.6} />
      <text x={x+w/2} y={s ? cy-4 : cy+8} textAnchor="middle"
        style={{ font:'600 25px var(--font)', fill: isNew ? '#101234' : 'var(--ink-2)' }}>{t}</text>
      {s && <text x={x+w/2} y={cy+22} textAnchor="middle"
        style={{ font:'400 20px var(--font)', fill:'var(--ink-2)' }}>{s}</text>}
    </g>
  )
}

function Arrow({ d, isNew }: { d:string; isNew?:boolean }) {
  return <path d={d} fill="none" stroke={isNew ? 'var(--navy)' : '#6b6f78'} strokeWidth={2.4}
    markerEnd={`url(#ah11${isNew ? 'n' : 'g'})`} />
}

function Note({ label, children, d }: { label:string; children:ReactNode; d:number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font:'400 25px/1.3 var(--font)', marginTop:4 }}>{children}</p>
    </div>
  )
}

const EXAMPLES = [
  { label: '7 × 9', a: 7, b: 9, result: 63, hex: '0x0000003F' },
  { label: '−2 × 5', a: -2, b: 5, result: -10, hex: '0xFFFFFFF6' },
  { label: '0xFFFF × 0xFFFF', a: 0xFFFF, b: 0xFFFF, result: 0xFFFE0001, hex: '0xFFFE0001' },
]

const STAGES = [
  { cycle: 'M 1', title: 'Operand Latch', hw: 'DSP48E1 AREG / BREG', x: 24 },
  { cycle: 'M 2', title: 'Core Multiply', hw: '25 × 18 MREG',         x: 314 },
  { cycle: 'M 3', title: 'Post-Add + PREG', hw: 'result ready',       x: 604 },
]

export default function Slide11() {
  const [sel, setSel] = useState(0)
  const ex = EXAMPLES[sel]

  const BW = 260, BH = 100, BY = 56

  return (
    <Frame n={7} kicker="RV32M Extension · DSP48E1 Hardware" title="Multiplier: 3-cycle pipeline · mul x3, x1, x2">
      <svg width={1728} height={660} viewBox="0 -20 1728 660" overflow="visible"
        style={{ position:'absolute', left:96, top:205 }}>
        <defs>
          <marker id="ah11g" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#6b6f78" />
          </marker>
          <marker id="ah11n" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ── CPU pipeline context ──────────────────────────────────── */}
        <g className="rise" style={delay(0.1)}>
          <rect x={0} y={BY} width={180} height={BH} fill="rgba(255,255,255,.55)" stroke="#8b8f98" strokeWidth={1.6} />
          <text x={90} y={BY+46} textAnchor="middle" style={{ font:'600 24px var(--font)', fill:'var(--ink-2)' }}>IF / ID</text>
          <text x={90} y={BY+70} textAnchor="middle" style={{ font:'400 19px var(--font)', fill:'var(--ink-2)' }}>mul decoded</text>
          <Arrow d="M182,106 H22" />
        </g>

        {/* ── 3 DSP pipeline stages ─────────────────────────────────── */}
        {STAGES.map((s, i) => (
          <g key={s.cycle}>
            <Box x={s.x + 200} y={BY} w={BW} h={BH} t={s.cycle} s={s.title} isNew d={0.15 + i * 0.1} />
            <g className="rise" style={delay(0.25 + i * 0.1)}>
              <text x={s.x + 200 + BW / 2} y={BY + BH + 22} textAnchor="middle"
                style={{ font:'500 17px var(--mono)', fill:'var(--ink-3)' }}>{s.hw}</text>
            </g>
            {i < 2 && <Arrow isNew d={`M${s.x + 200 + BW},${BY + BH / 2} H${STAGES[i+1].x + 200 - 2}`} />}
          </g>
        ))}

        {/* Result output */}
        <g className="rise" style={delay(0.55)}>
          <Arrow isNew d="M1064,106 H1128" />
          <rect x={1132} y={BY} width={260} height={BH} fill="#e3e4f4" stroke="var(--navy)" strokeWidth={2.6} />
          <text x={1262} y={BY + 46} textAnchor="middle"
            style={{ font:'700 26px var(--mono)', fill:'#101234' }}>
            x3 = {ex.result > 0 ? ex.result : ex.result}
          </text>
          <text x={1262} y={BY + 72} textAnchor="middle"
            style={{ font:'500 18px var(--mono)', fill:'var(--ink-2)' }}>{ex.hex}</text>
        </g>

        {/* MEM/WB */}
        <g className="rise" style={delay(0.65)}>
          <Arrow d="M1394,106 H1460" />
          <rect x={1464} y={BY} width={200} height={BH} fill="rgba(255,255,255,.55)" stroke="#8b8f98" strokeWidth={1.6} />
          <text x={1564} y={BY + 46} textAnchor="middle" style={{ font:'600 24px var(--font)', fill:'var(--ink-2)' }}>MEM / WB</text>
          <text x={1564} y={BY + 70} textAnchor="middle" style={{ font:'400 18px var(--font)', fill:'var(--ink-2)' }}>regfile WB</text>
        </g>

        {/* Animated tokens through pipeline */}
        {[180, 460, 750].map((x, i) => (
          <circle key={x} r={7} cy={BY + BH / 2} fill="var(--navy)">
            <animate attributeName="cx" from={x + 220} to={x + 280} dur="1.2s" begin={`${1.4 + i * 0.4}s`} repeatCount="indefinite" />
          </circle>
        ))}

        {/* ── stall_pipeline annotation ────────────────────────────── */}
        <g className="rise" style={delay(0.7)}>
          <line x1={224} y1={200} x2={1130} y2={200} stroke="var(--warn)" strokeWidth={1.5} strokeDasharray="6 4" />
          <text x={670} y={194} textAnchor="middle" style={{ font:'600 19px var(--mono)', fill:'var(--warn)', letterSpacing:'.05em' }}>
            stall_pipeline HIGH · m_busy HIGH (cycles T4–T7)
          </text>
          <text x={1200} y={194} style={{ font:'600 19px var(--mono)', fill:'var(--ok)' }}>m_done ✓ T8</text>
        </g>

        {/* ── Pipeline timing table ─────────────────────────────────── */}
        <g className="rise" style={delay(0.8)}>
          <text x={0} y={254} style={{ font:'600 19px var(--mono)', fill:'var(--navy)', letterSpacing:'.08em' }}>
            PIPELINE TIMING — mul x3, x1, x2 (x1={ex.a}, x2={ex.b})
          </text>
          <line x1={0} y1={264} x2={1200} y2={264} stroke="var(--line)" strokeWidth={1.5} />
          {(() => {
            const cols = ['T3','T4','T5','T6','T7','T8','T9']
            const rows = [
              { instr:'mul x3,x1,x2', cells:['IF/ID','M1','M2','M3','—','WB','—'] },
              { instr:'add x4,x3,x1', cells:['—','HOLD','HOLD','HOLD','HOLD','EX→fwd','WB'] },
            ]
            const CW = 116, CH = 48, LW = 200
            return (
              <>
                {cols.map((c, i) => (
                  <g key={c}>
                    <rect x={LW + i * CW} y={268} width={CW - 2} height={CH - 6}
                      fill={c === 'T8' ? '#e3e4f4' : 'rgba(255,255,255,.6)'}
                      stroke={c === 'T8' ? 'var(--navy)' : '#e2e8f0'} strokeWidth={1} />
                    <text x={LW + i * CW + CW/2 - 1} y={299} textAnchor="middle"
                      style={{ font:`${c === 'T8' ? '700' : '600'} 18px var(--mono)`, fill: c === 'T8' ? 'var(--navy)' : 'var(--ink-2)' }}>
                      {c}
                    </text>
                  </g>
                ))}
                {rows.map((r, ri) => (
                  <g key={ri}>
                    <text x={0} y={336 + ri * CH} style={{ font:'500 18px var(--mono)', fill:'var(--ink-2)' }}>{r.instr}</text>
                    {r.cells.map((cell, ci) => {
                      const isM = cell.startsWith('M')
                      const isHold = cell === 'HOLD'
                      const isFwd = cell.includes('fwd')
                      return (
                        <g key={ci}>
                          <rect x={LW + ci * CW} y={316 + ri * CH} width={CW - 2} height={CH - 6}
                            fill={isM ? '#e3e4f4' : (isHold ? 'rgba(255,255,255,.4)' : 'rgba(255,255,255,.6)')}
                            stroke={isM ? 'var(--navy)' : (isFwd ? 'var(--ok)' : '#e2e8f0')}
                            strokeWidth={isM ? 2 : (isFwd ? 1.8 : 1)} />
                          <text x={LW + ci * CW + CW/2 - 1} y={340 + ri * CH} textAnchor="middle"
                            style={{ font:`${isM ? '700' : '500'} ${cell.length > 4 ? '14' : '17'}px var(--mono)`,
                              fill: isM ? '#101234' : (isFwd ? 'var(--ok)' : (isHold ? 'var(--ink-3)' : 'var(--ink-2)')) }}>
                            {cell}
                          </text>
                        </g>
                      )
                    })}
                  </g>
                ))}
              </>
            )
          })()}
        </g>

        {/* ── MUL opcodes ───────────────────────────────────────────── */}
        <g className="rise" style={delay(0.9)}>
          <text x={0} y={446} style={{ font:'600 19px var(--mono)', fill:'var(--navy)', letterSpacing:'.08em' }}>
            ALL 4 RV32M MULTIPLY OPCODES
          </text>
          <line x1={0} y1={456} x2={1200} y2={456} stroke="var(--line)" strokeWidth={1.5} />
          {[
            { op:'MUL',    desc:'Lower 32 bits of signed × signed product' },
            { op:'MULH',   desc:'Upper 32 bits of signed × signed (64-bit result)' },
            { op:'MULHU',  desc:'Upper 32 bits of unsigned × unsigned' },
            { op:'MULHSU', desc:'Upper 32 bits of signed × unsigned' },
          ].map((r, i) => (
            <g key={r.op}>
              <line x1={0} y1={498 + i * 52} x2={1200} y2={498 + i * 52} stroke="#e2e8f0" strokeWidth={1} />
              <text x={0} y={484 + i * 52} style={{ font:'700 24px var(--mono)', fill:'var(--navy)' }}>{r.op}</text>
              <text x={200} y={484 + i * 52} style={{ font:'400 24px var(--font)', fill:'var(--ink-2)' }}>{r.desc}</text>
            </g>
          ))}
        </g>

        {/* ── Right panel: example selector + DSP note ──────────────── */}
        <g className="rise" style={delay(0.6)}>
          <text x={1400} y={22} style={{ font:'600 20px var(--mono)', fill:'var(--navy)', letterSpacing:'.08em' }}>
            EXAMPLES
          </text>
          <line x1={1400} y1={32} x2={1720} y2={32} stroke="var(--line)" strokeWidth={1.5} />
          {EXAMPLES.map((e, i) => (
            <g key={e.label}>
              <rect x={1400} y={44 + i * 78} width={320} height={62}
                fill={sel === i ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
                stroke={sel === i ? 'var(--navy)' : '#c4c4c0'}
                strokeWidth={sel === i ? 2.4 : 1.2} rx={2} />
              <text x={1560} y={76 + i * 78} textAnchor="middle"
                style={{ font:`${sel === i ? '700' : '500'} 20px var(--mono)`, fill: sel === i ? '#101234' : 'var(--ink-2)' }}>
                {e.label} = {e.result}
              </text>
              <text x={1560} y={98 + i * 78} textAnchor="middle"
                style={{ font:'500 16px var(--mono)', fill:'var(--ink-3)' }}>{e.hex}</text>
            </g>
          ))}

          <line x1={1400} y1={286} x2={1720} y2={286} stroke="var(--line)" strokeWidth={1.5} />
          <text x={1400} y={322} style={{ font:'600 20px var(--mono)', fill:'var(--navy)', letterSpacing:'.08em' }}>
            DSP48E1 vs SOFTWARE
          </text>
          {[
            'Software shift-add: 32–64 cycles',
            'DSP48E1 hardware: 3 cycles fixed',
            '10–20× throughput improvement',
            '236 unit tests + 31 pipeline checks',
          ].map((l, i) => (
            <text key={i} x={1400} y={356 + i * 36}
              style={{ font:'400 21px var(--font)', fill:'var(--ink-2)' }}>{l}</text>
          ))}
        </g>
      </svg>

      {/* Example selector buttons (HTML overlay) */}
      <div style={{ position:'absolute', left:1496+96, top:290, display:'flex', flexDirection:'column', gap:0 }}>
        {EXAMPLES.map((_, i) => (
          <button key={i} onClick={() => setSel(i)} style={{ width:0, height:78, opacity:0, cursor:'pointer' }} />
        ))}
      </div>
      {/* Clickable overlay on the SVG example boxes */}
      <div style={{ position:'absolute', left:1496+96, top:249, display:'flex', flexDirection:'column', gap:16 }}>
        {EXAMPLES.map((_, i) => (
          <button key={i} onClick={() => setSel(i)}
            style={{ width:320, height:62, opacity:0, cursor:'pointer', position:'absolute', top:i*78 }} />
        ))}
      </div>

      <div style={{ position:'absolute', left:96, right:96, top:890, display:'grid', gridTemplateColumns:'repeat(3,1fr)', gap:48 }}>
        <Note label="DSP48E1 pipeline" d={1.1}>3 fixed cycles: operand latch → 25×18 core multiply → post-adder. Fully pipelined; one result per cycle once filled.</Note>
        <Note label="Hazard handling" d={1.2}>stall_pipeline freezes IF/ID for 4 cycles (T4–T7). Skid buffer preserves add x4 state. EX-to-EX forwarding at T8.</Note>
        <Note label="Verification" d={1.3}>236 unit test vectors across all four MUL variants. 31 pipeline integration checks. Signed overflow corner cases confirmed.</Note>
      </div>
    </Frame>
  )
}
