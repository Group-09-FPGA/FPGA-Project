import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// L0: 8 bits — bit 5 is highest set (MSB=7, shown left→right as bit7..bit0)
const L0 = [0, 0, 1, 0, 1, 1, 0, 0] // bit 5 is at display position 2 (7,6,5,4,3,2,1,0)

// L1 segment 5 (bits 160..191), 32-bit slice: bit offset 13 is set = abs bit 173
const L1 = Array.from({ length: 32 }, (_, i) => [2, 7, 13, 21, 28].includes(i) ? 1 : 0)

// L2 word 173: bit 7 is highest set
const L2 = Array.from({ length: 32 }, (_, i) => [2, 7, 14, 19, 23].includes(i) ? 1 : 0)

const CELL = 20
const PITCH = 24

export default function Slide10() {
  return (
    <Frame n={5} kicker="O(1) Priority Encoding · BBO Hierarchy" title="Hardware priority tree: best bid in 1–2 cycles">
      <svg width={1728} height={700} viewBox="0 -10 1728 700" overflow="visible"
        style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="ah10" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ── L0 row ────────────────────────────────────────────────── */}
        <g className="rise" style={delay(0.1)}>
          <text x={0} y={32} style={{ font: '700 18px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            L0 · 8-BIT MASTER MASK
          </text>
          <text x={260} y={32} style={{ font: '500 14px var(--font)', fill: 'var(--ink-3)' }}>
            — bit N = 1 if L1 segment N has active orders
          </text>
          {L0.map((b, i) => {
            const bitNum = 7 - i // left = bit7, right = bit0
            const isActive = bitNum === 5 // highest set bit → leading-1 result
            return (
              <g key={i}>
                <rect x={i * PITCH} y={48} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1.2} rx={2} />
                <text x={i * PITCH + CELL / 2} y={64} textAnchor="middle"
                  style={{ font: `${isActive ? '800' : '600'} 13.5px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                <text x={i * PITCH + CELL / 2} y={84} textAnchor="middle"
                  style={{ font: '500 11px var(--mono)', fill: 'var(--ink-3)' }}>
                  {bitNum}
                </text>
              </g>
            )
          })}
          <text x={8 * PITCH + 20} y={64} style={{ font: '600 18px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → seg = 5
          </text>
        </g>

        {/* Arrow L0 → L1: from active cell bit 5 (x=58) down into L1 active cell bit 173 (x=322) */}
        <g className="rise" style={delay(0.2)}>
          <path d="M58,88 V118 H322 V154" fill="none" stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" />
          <text x={190} y={112} textAnchor="middle" style={{ font: '600 12.5px var(--mono)', fill: 'var(--navy)' }}>select segment 5</text>
        </g>

        {/* ── L1 row (segment 5) ────────────────────────────────────── */}
        <g className="rise" style={delay(0.3)}>
          <text x={0} y={146} style={{ font: '700 18px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            L1 · 256-BIT SUMMARY
          </text>
          <text x={380} y={146} style={{ font: '500 14px var(--font)', fill: 'var(--ink-3)' }}>
            [ segment 5 shown · words 160..191 ]
          </text>
          {L1.map((b, i) => {
            const bitNum = 160 + i
            const isActive = i === 13
            return (
              <g key={i}>
                <rect x={i * PITCH} y={158} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1} rx={2} />
                <text x={i * PITCH + CELL / 2} y={174} textAnchor="middle"
                  style={{ font: `${b ? '700' : '400'} 12px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                {i % 4 === 0 && (
                  <text x={i * PITCH + CELL / 2} y={192} textAnchor="middle"
                    style={{ font: '500 10.5px var(--mono)', fill: 'var(--ink-3)' }}>{bitNum}</text>
                )}
              </g>
            )
          })}
          <text x={32 * PITCH + 20} y={174} style={{ font: '600 18px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → bit 173
          </text>
        </g>

        {/* Arrow L1 → L2: from active cell bit 173 (x=322) down into L2 active cell bit 7 (x=178) */}
        <g className="rise" style={delay(0.4)}>
          <path d="M322,196 V224 H178 V254" fill="none" stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" />
          <text x={250} y={218} textAnchor="middle" style={{ font: '600 12.5px var(--mono)', fill: 'var(--navy)' }}>select word 173</text>
        </g>

        {/* ── L2 row (word 173) ─────────────────────────────────────── */}
        <g className="rise" style={delay(0.5)}>
          <text x={0} y={246} style={{ font: '700 18px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            L2 · 32-BIT LEAF
          </text>
          <text x={230} y={246} style={{ font: '500 14px var(--font)', fill: 'var(--ink-3)' }}>
            [ word 173 shown · ticks 5536..5567 ]
          </text>
          {L2.map((b, i) => {
            const bitNum = 5536 + i
            const isActive = i === 7
            return (
              <g key={i}>
                <rect x={i * PITCH} y={258} width={CELL} height={CELL}
                  fill={isActive ? '#e3e4f4' : (b ? 'rgba(255,255,255,.8)' : 'rgba(255,255,255,.3)')}
                  stroke={isActive ? 'var(--navy)' : (b ? 'var(--ink-2)' : '#c4c4c0')}
                  strokeWidth={isActive ? 2.6 : 1} rx={2} />
                <text x={i * PITCH + CELL / 2} y={274} textAnchor="middle"
                  style={{ font: `${b ? '700' : '400'} 12px var(--mono)`, fill: isActive ? '#101234' : (b ? 'var(--ink)' : 'var(--ink-3)') }}>
                  {b}
                </text>
                {i % 4 === 0 && (
                  <text x={i * PITCH + CELL / 2} y={292} textAnchor="middle"
                    style={{ font: '500 10.5px var(--mono)', fill: 'var(--ink-3)' }}>{bitNum}</text>
                )}
              </g>
            )
          })}
          <text x={32 * PITCH + 20} y={274} style={{ font: '600 18px var(--mono)', fill: 'var(--navy)' }}>
            → leading-1 → bit 7
          </text>
        </g>

        {/* Arrow L2 → result: from active cell bit 7 (x=178) into Result box center (x=368) */}
        <g className="rise" style={delay(0.6)}>
          <path d="M178,296 V324 H368 V348" fill="none" stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah10)" />
          <text x={273} y={318} textAnchor="middle" style={{ font: '600 12.5px var(--mono)', fill: 'var(--navy)' }}>select tick 7 (pidx 5543)</text>
        </g>

        {/* ── Final result box ─────────────────────────────────────── */}
        <g className="rise" style={delay(0.7)}>
          <rect x={0} y={352} width={736} height={104} rx={4}
            fill="#e3e4f4" stroke="var(--navy)" strokeWidth={2.6} />
          <text x={368} y={392} textAnchor="middle"
            style={{ font: '700 26px var(--mono)', fill: '#101234' }}>
            pidx = 173 × 32 + 7 = 5543
          </text>
          <text x={368} y={426} textAnchor="middle"
            style={{ font: '400 22px var(--font)', fill: 'var(--ink-2)' }}>
            price = base + 5543 × tick = $149.50 · qty = 300
          </text>
        </g>

        {/* Animated search token traces EXACTLY along the arrow shafts and through active cells */}
        <circle r={6.5} fill="var(--navy)">
          <animateMotion dur="3.4s" begin="0.8s" repeatCount="indefinite"
            path="M58,88 V118 H322 V156 V196 V224 H178 V256 V296 V324 H368 V352" />
        </circle>

        {/* ── RIGHT: complexity comparison (cleanly placed at x=1060) ─── */}
        <g className="rise" style={delay(0.8)}>
          <text x={1060} y={32} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            COMPLEXITY COMPARISON
          </text>
          <line x1={1060} y1={42} x2={1720} y2={42} stroke="var(--line)" strokeWidth={1.5} />

          {/* Software */}
          <text x={1060} y={76} style={{ font: '600 22px var(--font)', fill: 'var(--ink)' }}>Naïve software scan</text>
          {['for (p = 8191; p >= 0; p--) {', '  if (level[p].qty > 0) return p', '}  // worst: 8,192 iterations'].map((l, i) => (
            <text key={i} x={1076} y={106 + i * 28} style={{ font: '500 18px var(--mono)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
          <text x={1060} y={204} style={{ font: '700 24px var(--font)', fill: 'var(--warn)' }}>
            Latency: O(N) — up to 8,192 cycles
          </text>

          <line x1={1060} y1={224} x2={1720} y2={224} stroke="#e2e8f0" strokeWidth={1} />

          {/* Hardware */}
          <text x={1060} y={258} style={{ font: '600 22px var(--font)', fill: 'var(--ink)' }}>Hardware priority tree</text>
          {[
            'L0  priority_encode (8 b)   → seg   // 1 cycle',
            'L1  priority_encode (32 b)  → word  // 1 cycle',
            'L2  priority_encode (32 b)  → bit   // 1 cycle',
            'pidx = word × 32 + bit              // combinational',
            'price = base + pidx × tick          // DSP48 · 2 cycles',
          ].map((l, i) => (
            <text key={i} x={1076} y={288 + i * 28} style={{ font: '500 18px var(--mono)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
          <text x={1060} y={442} style={{ font: '700 24px var(--font)', fill: 'var(--ok)' }}>
            Latency: O(1) — 2–3 cycles = 20–30 ns
          </text>
          <text x={1060} y={482} style={{ font: '700 28px var(--font)', fill: 'var(--navy)' }}>
            273× faster than a software scan
          </text>

          {/* Resource note */}
          <line x1={1060} y1={504} x2={1720} y2={504} stroke="#e2e8f0" strokeWidth={1} />
          <text x={1060} y={536} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            HARDWARE COST
          </text>
          {[
            'L2 leaves : 256 × 32-bit BRAM words  =  8,192 occupancy bits',
            'L1 summary: 256-bit register          =  8 × 32-bit FFs',
            'L0 master : 8-bit register            =  single LUT slice',
            'Best Ask  : trailing-one encoder      =  symmetric, same cost',
          ].map((l, i) => (
            <text key={i} x={1076} y={566 + i * 28} style={{ font: '400 18px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
        </g>
      </svg>
    </Frame>
  )
}
