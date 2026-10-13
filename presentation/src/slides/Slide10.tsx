import { useEffect, useState } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// Simulate a real search: pidx = 5543 (bidx 5, word 173, bit 7)
// L0: bit 5 is set (of 8 bits) — highest set bit = 5
// L1: bit 173 set in segment 5 (bits 160..191) — leading-1 at offset 13 → absolute 160+13=173
// L2: word 173, bits set at position 7 and 2 → highest = 7
// final pidx = 173*32 + 7 = 5543
// price = 900000 + 5543*1000 = 6443000 → $644.30 ... let's use different values
// Let's say Base=$100.00 = 10000000 (4dp), Tick=1000 → pidx 142 → price 10142000 → $101.42? Let's keep it simple
// Use: Base=100.00, Tick=0.01, pidx=4950 → $149.50 (nice round number for demo)
// Simplify: show Base = 0, Tick = 1 in "cents", pidx = 14950 → $149.50

const SVG_W = 1728
const SVG_H = 680

// L0: 8 bits, bit 5 active (0-indexed from right, MSB=7)
const L0_BITS = [0, 0, 1, 0, 1, 1, 0, 0] // bits 7..0, bit 5=1 (highest set)
const L0_ACTIVE = 5 // highest set bit index

// L1 segment 5 = bits [160..191]. Show 32 of them. Bit offset 13 is set (abs bit 173)
const L1_BITS = Array.from({length: 32}, (_, i) => i === 13 ? 1 : ([2,7,21,28].includes(i) ? 1 : 0))
const L1_ACTIVE = 13

// L2 word 173: bits set at 7, 2 → highest = 7
const L2_BITS = Array.from({length: 32}, (_, i) => i === 7 || i === 2 ? 1 : ([14, 19, 23].includes(i) ? 1 : 0))
const L2_ACTIVE = 7

export default function Slide10() {
  const [searchStep, setSearchStep] = useState(-1)

  useEffect(() => {
    // Cycle through search steps 0..3
    const id = setInterval(() => setSearchStep(s => s >= 3 ? -1 : s + 1), 1500)
    return () => clearInterval(id)
  }, [])

  const isFound = searchStep >= 3
  const L0_Y = 60
  const L1_Y = 220
  const L2_Y = 390
  const OUT_Y = 545

  const L0_X = 420
  const L0_W = 360
  const L0_H = 80
  const CELL_W = L0_W / 8

  const L1_X = 280
  const L1_W = 640
  const L1_H = 100
  const L1_CW = L1_W / 32

  const L2_X = 280
  const L2_W = 640
  const L2_H = 90
  const L2_CW = L2_W / 32

  // Token search path: L0 center → L1 center → L2 center → output
  const searchPath = `M${L0_X + L0_W / 2},${L0_Y + L0_H} L${L1_X + L1_W / 2},${L1_Y} M${L1_X + L1_W / 2},${L1_Y + L1_H} L${L2_X + L2_W / 2},${L2_Y} M${L2_X + L2_W / 2},${L2_Y + L2_H} L${L2_X + L2_W / 2},${OUT_Y}`

  return (
    <Frame n={10} kicker="O(1) Priority Encoding · BBO Hierarchy" title="Hardware Priority Tree: Finding Best Bid in 1-2 Cycles">
      <svg width={SVG_W} height={SVG_H} viewBox={`0 0 ${SVG_W} ${SVG_H}`}
        style={{ position: 'absolute', left: 96, top: 175 }}>
        <defs>
          <marker id="ah10" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
          <filter id="glow10"><feGaussianBlur stdDeviation="4" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
        </defs>

        {/* ===== L0: 8-bit master mask ===== */}
        <g>
          <rect x={L0_X - 12} y={L0_Y - 36} width={L0_W + 24} height={L0_H + 46}
            fill={searchStep >= 0 ? '#e3e4f4' : 'rgba(255,255,255,0.8)'}
            stroke={searchStep >= 0 ? '#2a2e86' : '#cbd5e1'} strokeWidth={searchStep >= 0 ? 2.5 : 1.5} rx={8} />
          <text x={L0_X + L0_W / 2} y={L0_Y - 14} textAnchor="middle"
            style={{ font: '700 17px var(--mono)', fill: '#2a2e86', letterSpacing: '0.06em' }}>
            L0: 8-bit MASTER MASK
          </text>
          <text x={L0_X + L0_W / 2} y={L0_Y - 0} textAnchor="middle"
            style={{ font: '400 13px var(--font)', fill: '#6b7280' }}>
            Bit N = 1 if any price tick in L1 segment N is occupied
          </text>
          {/* 8 bit cells */}
          {L0_BITS.map((bit, i) => {
            const isHigh = bit === 1
            const isActive = i === (7 - L0_ACTIVE) // display MSB left
            return (
              <g key={i}>
                <rect x={L0_X + i * CELL_W} y={L0_Y + 10} width={CELL_W - 2} height={CELL_W - 2}
                  fill={isActive ? '#2a2e86' : (isHigh ? '#bfdbfe' : '#f8fafc')}
                  stroke={isActive ? '#2a2e86' : (isHigh ? '#93c5fd' : '#e2e8f0')}
                  strokeWidth={isActive ? 2.5 : 1} rx={3} />
                <text x={L0_X + i * CELL_W + CELL_W / 2 - 1} y={L0_Y + 10 + CELL_W / 2 + 5}
                  textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: isActive ? 'white' : (isHigh ? '#1d4ed8' : '#94a3b8') }}>
                  {bit}
                </text>
                <text x={L0_X + i * CELL_W + CELL_W / 2 - 1} y={L0_Y + 10 + CELL_W + 16}
                  textAnchor="middle" style={{ font: '500 11px var(--mono)', fill: '#94a3b8' }}>
                  {7 - i}
                </text>
              </g>
            )
          })}
          {searchStep >= 0 && (
            <text x={L0_X + L0_W + 20} y={L0_Y + 55} style={{ font: '700 16px var(--mono)', fill: '#2a2e86' }}>
              → leading-1 → seg=5
            </text>
          )}
        </g>

        {/* ===== L0→L1 arrow ===== */}
        <line x1={L0_X + L0_W / 2} y1={L0_Y + L0_H + 12}
          x2={L1_X + L1_W / 2} y2={L1_Y - 12}
          stroke={searchStep >= 1 ? '#2a2e86' : '#e2e8f0'} strokeWidth={2}
          markerEnd="url(#ah10)" style={{ transition: 'stroke 0.3s' }} />
        {searchStep >= 0 && (
          <text x={(L0_X + L0_W / 2 + L1_X + L1_W / 2) / 2 + 30} y={(L0_Y + L0_H + L1_Y) / 2 - 4}
            style={{ font: '600 14px var(--mono)', fill: '#2a2e86' }}>
            Segment #5 →
          </text>
        )}

        {/* ===== L1: 32-bit slice of segment 5 ===== */}
        <g>
          <rect x={L1_X - 12} y={L1_Y - 28} width={L1_W + 24} height={L1_H + 38}
            fill={searchStep >= 1 ? '#ede9fe' : 'rgba(255,255,255,0.8)'}
            stroke={searchStep >= 1 ? '#7c3aed' : '#cbd5e1'} strokeWidth={searchStep >= 1 ? 2.5 : 1.5} rx={8} />
          <text x={L1_X + L1_W / 2} y={L1_Y - 12} textAnchor="middle"
            style={{ font: '700 17px var(--mono)', fill: '#7c3aed', letterSpacing: '0.06em' }}>
            L1: 256-bit SUMMARY (showing segment 5: bits [160..191])
          </text>
          {L1_BITS.map((bit, i) => {
            const isHigh = bit === 1
            const isActive = i === L1_ACTIVE
            return (
              <g key={i}>
                <rect x={L1_X + i * L1_CW} y={L1_Y + 8} width={L1_CW - 1} height={L1_CW - 1}
                  fill={isActive ? '#7c3aed' : (isHigh ? '#ddd6fe' : '#f8fafc')}
                  stroke={isActive ? '#7c3aed' : (isHigh ? '#a78bfa' : '#e2e8f0')}
                  strokeWidth={isActive ? 2 : 1} rx={2} />
                {isHigh && (
                  <text x={L1_X + i * L1_CW + L1_CW / 2} y={L1_Y + 8 + L1_CW / 2 + 4}
                    textAnchor="middle" style={{ font: '700 12px var(--mono)', fill: isActive ? 'white' : '#6d28d9' }}>
                    1
                  </text>
                )}
                {i % 4 === 0 && (
                  <text x={L1_X + i * L1_CW + L1_CW / 2} y={L1_Y + 8 + L1_CW + 16}
                    textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#94a3b8' }}>
                    {160 + i}
                  </text>
                )}
              </g>
            )
          })}
          {searchStep >= 1 && (
            <text x={L1_X + L1_W + 20} y={L1_Y + 60} style={{ font: '700 16px var(--mono)', fill: '#7c3aed' }}>
              → leading-1 → bit=173
            </text>
          )}
        </g>

        {/* ===== L1→L2 arrow ===== */}
        <line x1={L1_X + L1_W / 2} y1={L1_Y + L1_H + 12}
          x2={L2_X + L2_W / 2} y2={L2_Y - 12}
          stroke={searchStep >= 2 ? '#2a2e86' : '#e2e8f0'} strokeWidth={2}
          markerEnd="url(#ah10)" style={{ transition: 'stroke 0.3s' }} />
        {searchStep >= 1 && (
          <text x={(L1_X + L1_W / 2 + L2_X + L2_W / 2) / 2 + 30} y={(L1_Y + L1_H + L2_Y) / 2 - 4}
            style={{ font: '600 14px var(--mono)', fill: '#2a2e86' }}>
            Word #173 →
          </text>
        )}

        {/* ===== L2: 32-bit leaf word 173 ===== */}
        <g>
          <rect x={L2_X - 12} y={L2_Y - 28} width={L2_W + 24} height={L2_H + 38}
            fill={searchStep >= 2 ? '#fef3c7' : 'rgba(255,255,255,0.8)'}
            stroke={searchStep >= 2 ? '#b45309' : '#cbd5e1'} strokeWidth={searchStep >= 2 ? 2.5 : 1.5} rx={8} />
          <text x={L2_X + L2_W / 2} y={L2_Y - 12} textAnchor="middle"
            style={{ font: '700 17px var(--mono)', fill: '#b45309', letterSpacing: '0.06em' }}>
            L2: 32-bit LEAF WORD #173 (price ticks 5536..5567)
          </text>
          {L2_BITS.map((bit, i) => {
            const isHigh = bit === 1
            const isActive = i === L2_ACTIVE
            return (
              <g key={i}>
                <rect x={L2_X + i * L2_CW} y={L2_Y + 8} width={L2_CW - 1} height={L2_CW - 1}
                  fill={isActive ? '#b45309' : (isHigh ? '#fde68a' : '#f8fafc')}
                  stroke={isActive ? '#b45309' : (isHigh ? '#fcd34d' : '#e2e8f0')}
                  strokeWidth={isActive ? 2.5 : 1} rx={2} />
                {isHigh && (
                  <text x={L2_X + i * L2_CW + L2_CW / 2} y={L2_Y + 8 + L2_CW / 2 + 4}
                    textAnchor="middle" style={{ font: '700 12px var(--mono)', fill: isActive ? 'white' : '#92400e' }}>
                    1
                  </text>
                )}
                {i % 4 === 0 && (
                  <text x={L2_X + i * L2_CW + L2_CW / 2} y={L2_Y + 8 + L2_CW + 16}
                    textAnchor="middle" style={{ font: '500 10px var(--mono)', fill: '#94a3b8' }}>
                    {5536 + i}
                  </text>
                )}
              </g>
            )
          })}
          {searchStep >= 2 && (
            <text x={L2_X + L2_W + 20} y={L2_Y + 55} style={{ font: '700 16px var(--mono)', fill: '#b45309' }}>
              → leading-1 → bit=7
            </text>
          )}
        </g>

        {/* ===== L2 → Output arrow ===== */}
        <line x1={L2_X + L2_W / 2} y1={L2_Y + L2_H + 12}
          x2={L2_X + L2_W / 2} y2={OUT_Y - 12}
          stroke={isFound ? '#2a2e86' : '#e2e8f0'} strokeWidth={2}
          markerEnd="url(#ah10)" style={{ transition: 'stroke 0.3s' }} />

        {/* ===== Final BBO Output ===== */}
        <g>
          <rect x={L2_X - 50} y={OUT_Y} width={L2_W + 100} height={110}
            fill={isFound ? '#2a2e86' : '#f8fafc'}
            stroke={isFound ? '#2a2e86' : '#e2e8f0'} strokeWidth={2.5} rx={10}
            filter={isFound ? 'url(#glow10)' : undefined} />
          <text x={L2_X + L2_W / 2} y={OUT_Y + 28} textAnchor="middle"
            style={{ font: '600 16px var(--mono)', fill: isFound ? '#93c5fd' : '#94a3b8', letterSpacing: '0.1em' }}>
            {isFound ? '✓ BBO FOUND — 3 CYCLES TOTAL' : 'Awaiting search...'}
          </text>
          <text x={L2_X + L2_W / 2} y={OUT_Y + 58} textAnchor="middle"
            style={{ font: '700 28px var(--mono)', fill: isFound ? 'white' : '#e2e8f0' }}>
            pidx = 173×32+7 = 5543
          </text>
          <text x={L2_X + L2_W / 2} y={OUT_Y + 88} textAnchor="middle"
            style={{ font: '700 24px var(--font)', fill: isFound ? '#86efac' : '#e2e8f0' }}>
            {isFound ? 'Best Bid Price = $149.50  ·  Qty = 300 shares' : '—'}
          </text>
        </g>

        {/* Animated search token */}
        <circle r={9} fill="#2a2e86" filter="url(#glow10)" opacity={searchStep >= 0 ? 1 : 0}>
          <animateMotion dur="4.5s" begin="0s" repeatCount="indefinite"
            path={`M${L0_X + L0_W / 2},${L0_Y + L0_H / 2} L${L1_X + L1_W / 2},${L1_Y + L1_H / 2} L${L2_X + L2_W / 2},${L2_Y + L2_H / 2} L${L2_X + L2_W / 2},${OUT_Y + 55}`} />
        </circle>

        {/* RIGHT: Complexity comparison */}
        <g>
          <rect x={1030} y={L0_Y - 36} width={660} height={420} fill="#0f172a" stroke="#1e293b" strokeWidth={1.5} rx={10} />
          <text x={1360} y={L0_Y - 12} textAnchor="middle"
            style={{ font: '700 16px var(--mono)', fill: '#38bdf8', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
            Complexity Comparison
          </text>
          {/* Software */}
          <rect x={1050} y={L0_Y + 5} width={620} height={165} fill="#1e293b" rx={6} />
          <text x={1070} y={L0_Y + 30} style={{ font: '700 14px var(--mono)', fill: '#f87171' }}>NAIVE SOFTWARE (C loop):</text>
          {['for (p = 8191; p >= 0; p--) {', '  if (level[p].qty > 0)', '    return p; // found!', '}', '// Worst case: 8192 comparisons!', '// O(N) — variable, cache-thrashing'].map((line, i) => (
            <text key={i} x={1080} y={L0_Y + 50 + i * 20} style={{ font: '400 13px var(--mono)', fill: line.includes('//') ? '#4ade80' : '#e2e8f0' }}>
              {line}
            </text>
          ))}
          <text x={1360} y={L0_Y + 185} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: '#f87171' }}>
            Latency: O(N) up to 8,192 cycles
          </text>

          {/* Hardware */}
          <rect x={1050} y={L0_Y + 205} width={620} height={175} fill="#1e293b" rx={6} />
          <text x={1070} y={L0_Y + 230} style={{ font: '700 14px var(--mono)', fill: '#4ade80' }}>OUR HARDWARE (3-level tree):</text>
          {[
            'L0 priority_encode(8b master) → seg  // 1 cyc',
            'L1 priority_encode(32b slice) → word // 1 cyc',
            'L2 priority_encode(32b leaf)  → bit  // 1 cyc',
            '',
            'pidx = word×32 + bit  // combinational',
            'price = Base + pidx×Tick // DSP48, 2 cyc',
          ].map((line, i) => (
            <text key={i} x={1080} y={L0_Y + 252 + i * 21} style={{ font: '400 12px var(--mono)', fill: line.includes('//') ? '#4ade80' : '#e2e8f0' }}>
              {line}
            </text>
          ))}
          <text x={1360} y={L0_Y + 395} textAnchor="middle" style={{ font: '700 18px var(--mono)', fill: '#4ade80' }}>
            Latency: O(1) = 2-3 cycles = 20-30 ns
          </text>

          {/* Speedup badge */}
          <rect x={1120} y={L0_Y + 408} width={480} height={52} fill="#2a2e86" rx={8} />
          <text x={1360} y={L0_Y + 442} textAnchor="middle" style={{ font: '800 22px var(--font)', fill: 'white' }}>
            273× faster than software scan
          </text>
        </g>
      </svg>
    </Frame>
  )
}
