import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 25px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

// L0: 8 bits — bit 5 is highest set (MSB=7, shown left→right as bit7..bit0)
const L0 = [0,0,1,0,1,1,0,0]  // display order: bit7..bit0; bit5 (index from right=5, display col=2) is active
// bit 5 is at display position 2 (since we show 7,6,5,4,3,2,1,0)

// L1 segment 5 (bits 160..191), 32-bit slice: bit offset 13 is set = abs bit 173
const L1 = Array.from({length:32}, (_,i) => [2,7,13,21,28].includes(i) ? 1 : 0)

// L2 word 173: bit 7 is highest set
const L2 = Array.from({length:32}, (_,i) => [2,7,14,19,23].includes(i) ? 1 : 0)

const CELL = 28

export default function Slide10() {
  return (
    <Frame n={5} kicker="O(1) Priority Encoding · BBO Hierarchy" title="Hardware priority tree: best bid in 1–2 cycles">
      <svg width={1728} height={660} viewBox="0 -10 1728 660" overflow="visible"
        style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="ah10" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ── L0 row ────────────────────────────────────────────────── */}
        <g className="rise" style={delay(0.1)}>
          <text x={0} y={22} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            L0 · 8-BIT MASTER MASK
          </text>
          <text x={580} y={22} style={{ font: '400 18px var(--font)', fill: 'var(--ink-2)' }}>
            Bit N = 1 if any price tick in L1 segment N is occupied
          </text>
          {L0.map((b, i) => {
            const bitNum = 7 - i  // left = bit7, right = bit0
            const isActive = bitNum === 5  // highest set bit → leading-1 result
            return (
              <g key={i}>
                <rect x={i * (CELL + 4)} y={30} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1.2} />
                <text x={i * (CELL + 4) + CELL / 2} y={51} textAnchor="middle"
                  style={{ font: `${isActive ? '800' : '600'} 16px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                <text x={i * (CELL + 4) + CELL / 2} y={74} textAnchor="middle"
                  style={{ font: '500 12px var(--mono)', fill: 'var(--ink-3)' }}>
                  {bitNum}
                </text>
              </g>
            )
          })}
          <text x={8 * (CELL + 4) + 20} y={52} style={{ font: '600 22px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → seg = 5
          </text>
        </g>

        {/* Arrow L0 → L1 */}
        <line x1={300} y1={84} x2={300} y2={112} stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" className="rise" />

        {/* ── L1 row (segment 5) ────────────────────────────────────── */}
        <g className="rise" style={delay(0.3)}>
          <text x={0} y={128} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            L1 · 256-BIT SUMMARY  (segment 5 shown: bits 160..191)
          </text>
          {L1.map((b, i) => {
            const bitNum = 160 + i
            const isActive = i === 13
            return (
              <g key={i}>
                <rect x={i * (CELL + 2)} y={136} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1} />
                <text x={i * (CELL + 2) + CELL / 2} y={157} textAnchor="middle"
                  style={{ font: `${b ? '700' : '400'} 13px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                {i % 4 === 0 && (
                  <text x={i * (CELL + 2) + CELL / 2} y={178} textAnchor="middle"
                    style={{ font: '500 11px var(--mono)', fill: 'var(--ink-3)' }}>{bitNum}</text>
                )}
              </g>
            )
          })}
          <text x={32 * (CELL + 2) + 14} y={158} style={{ font: '600 22px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → bit 173
          </text>
        </g>

        {/* Arrow L1 → L2 */}
        <line x1={420} y1={184} x2={420} y2={212} stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" className="rise" />

        {/* ── L2 row (word 173) ─────────────────────────────────────── */}
        <g className="rise" style={delay(0.5)}>
          <text x={0} y={228} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            L2 · 32-BIT LEAF WORD 173  (price ticks 5536..5567)
          </text>
          {L2.map((b, i) => {
            const bitNum = 5536 + i
            const isActive = i === 7
            return (
              <g key={i}>
                <rect x={i * (CELL + 4)} y={236} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1} />
                <text x={i * (CELL + 4) + CELL / 2} y={257} textAnchor="middle"
                  style={{ font: `${b ? '700' : '400'} 13px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                {i % 4 === 0 && (
                  <text x={i * (CELL + 4) + CELL / 2} y={278} textAnchor="middle"
                    style={{ font: '500 11px var(--mono)', fill: 'var(--ink-3)' }}>{bitNum}</text>
                )}
              </g>
            )
          })}
          <text x={32 * (CELL + 4) + 14} y={258} style={{ font: '600 22px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → bit 7
          </text>
        </g>

        {/* Arrow L2 → result */}
        <line x1={300} y1={285} x2={300} y2={312} stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" className="rise" />

        {/* ── Final result box ─────────────────────────────────────── */}
        <g className="rise" style={delay(0.7)}>
          <rect x={0} y={320} width={700} height={110}
            fill="#e3e4f4" stroke="var(--navy)" strokeWidth={2.6} />
          <text x={350} y={362} textAnchor="middle"
            style={{ font: '700 28px var(--mono)', fill: '#101234' }}>
            pidx = 173 × 32 + 7 = 5543
          </text>
          <text x={350} y={398} textAnchor="middle"
            style={{ font: '400 25px var(--font)', fill: 'var(--ink-2)' }}>
            price = base + 5543 × tick = $149.50 · qty = 300
          </text>
        </g>

        {/* Animated search token */}
        <circle r={8} fill="var(--navy)">
          <animateMotion dur="4s" begin="1.5s" repeatCount="indefinite"
            path="M148,30 V136 L420,162 V236 L300,262 V320" />
        </circle>

        {/* ── RIGHT: complexity comparison ──────────────────────────── */}
        <g className="rise" style={delay(0.8)}>
          <text x={820} y={22} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            COMPLEXITY COMPARISON
          </text>
          <line x1={820} y1={32} x2={1720} y2={32} stroke="var(--line)" strokeWidth={1.5} />

          {/* Software */}
          <text x={820} y={68} style={{ font: '600 22px var(--font)', fill: 'var(--ink)' }}>Naïve software scan</text>
          {['for (p = 8191; p >= 0; p--) {', '  if (level[p].qty > 0) return p', '}  // worst: 8,192 iterations'].map((l, i) => (
            <text key={i} x={836} y={98 + i * 30} style={{ font: '500 19px var(--mono)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
          <text x={820} y={202} style={{ font: '700 26px var(--font)', fill: 'var(--warn)' }}>
            Latency: O(N) — up to 8,192 cycles
          </text>

          <line x1={820} y1={222} x2={1720} y2={222} stroke="#e2e8f0" strokeWidth={1} />

          {/* Hardware */}
          <text x={820} y={258} style={{ font: '600 22px var(--font)', fill: 'var(--ink)' }}>Hardware priority tree</text>
          {[
            'L0  priority_encode (8 b)   → seg   // 1 cycle',
            'L1  priority_encode (32 b)  → word  // 1 cycle',
            'L2  priority_encode (32 b)  → bit   // 1 cycle',
            'pidx = word × 32 + bit              // combinational',
            'price = base + pidx × tick          // DSP48 · 2 cycles',
          ].map((l, i) => (
            <text key={i} x={836} y={290 + i * 30} style={{ font: '500 19px var(--mono)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
          <text x={820} y={448} style={{ font: '700 26px var(--font)', fill: 'var(--ok)' }}>
            Latency: O(1) — 2–3 cycles = 20–30 ns
          </text>
          <text x={820} y={488} style={{ font: '700 32px var(--font)', fill: 'var(--navy)' }}>
            273× faster than a software scan
          </text>

          {/* Resource note */}
          <line x1={820} y1={510} x2={1720} y2={510} stroke="#e2e8f0" strokeWidth={1} />
          <text x={820} y={548} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            HARDWARE COST
          </text>
          {[
            'L2 leaves : 256 × 32-bit BRAM words  =  8,192 occupancy bits',
            'L1 summary: 256-bit register          =  8 × 32-bit FFs',
            'L0 master : 8-bit register            =  single LUT slice',
            'Best Ask  : trailing-one encoder      =  symmetric, same cost',
          ].map((l, i) => (
            <text key={i} x={836} y={578 + i * 30} style={{ font: '400 19px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
        </g>
      </svg>
    </Frame>
  )
}
