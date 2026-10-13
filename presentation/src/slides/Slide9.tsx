import { useEffect, useState } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

const BLOCKS = [
  { label: 'Event In', file: '(256-bit canonical event)', col: '#6b7280', bg: 'rgba(255,255,255,0.7)', special: false },
  { label: 'Hash Table', file: 'lob_hash_table.sv', sub: '1024 sets × 8 ways + 8 stash', sub2: 'O(1) OID → Slot# · single cycle', col: '#2a2e86', bg: '#e3e4f4', special: true },
  { label: 'Slot Table', file: 'lob_slot_table.sv', sub: '2048 entries × {valid, side, pidx, qty}', sub2: 'Dual-Port BRAM (read & write simultaneously)', col: '#2a2e86', bg: '#e3e4f4', special: true },
  { label: 'Free List', file: 'lob_free_list.sv', sub: 'LIFO stack — pre-initialized to 0..2047', sub2: 'Pop on ADD · Push on DELETE/FILL', col: '#059669', bg: '#d1fae5', special: true },
  { label: 'Price Level RAM', file: 'lob_price_ram.sv', sub: 'Bid Bank: 8192 levels × {qty, count}', sub2: 'Ask Bank: 8192 levels × {qty, count}', col: '#0891b2', bg: '#cffafe', special: true },
  { label: 'Occupancy Bitmaps', file: 'lob_occupancy.sv', sub: 'L2: 256×32b=8192 ticks · L1: 256b · L0: 8b', sub2: 'Hierarchical priority encoder → O(1) BBO', col: '#7c3aed', bg: '#ede9fe', special: true },
  { label: 'BBO Engine', file: 'lob_bbo.sv', sub: '2-stage DSP48: Price = Base + pidx × Tick', sub2: 'Fully pipelined · atomic coherence', col: '#b45309', bg: '#fef3c7', special: true },
  { label: 'MMIO Output', file: 'lob_mmio_slave.sv  0x4000_0000', sub: 'Best Bid: $149.50 qty=300', sub2: 'Best Ask: $149.60 qty=200 · Spread=0.10', col: '#15803d', bg: '#dcfce7', special: false },
]

const FLOW_CARDS = [
  {
    title: 'ADD Order Flow', color: '#2a2e86',
    lines: ['1. Hash OID → 10-bit set → 8-way parallel lookup → Slot#', '2. Pop free slot from Free List stack', '3. Write slot: {side, pidx, shares}; Price RAM +qty'],
  },
  {
    title: 'EXECUTE / CANCEL Flow', color: '#ea580c',
    lines: ['1. Hash OID → slot → read {pidx, shares}', '2. Deduct executed/cancelled shares from Price RAM', '3. If qty=0: clear price level, push slot → Free List'],
  },
  {
    title: 'BBO Search Trigger', color: '#7c3aed',
    lines: ['Triggered when a price level depletes to zero qty', '1. L0 leading-1 → segment# (1 cycle)', '2. L1 leading-1 → word# (1 cycle) → final pidx'],
  },
  {
    title: 'Fail-Stop Policy', color: '#dc2626',
    lines: ['FAIL_DUP_OID · FAIL_MISSING_OID · FAIL_QTY_UF', 'Hardware locks ST_FAIL_STOP · REG_LOB_ERROR_CODE', 'CPU reads error code and resets via REG_LOB_CTRL'],
  },
]

const BW = 310
const BH_SMALL = 54
const BH_LARGE = 90
const BLEFT = 60
const BGAP = 10

function blockH(i: number) { return i === 0 || i === 7 ? BH_SMALL : BH_LARGE }
function blockY(i: number) {
  let y = 0
  for (let j = 0; j < i; j++) y += blockH(j) + BGAP
  return y
}

export default function Slide9() {
  const [activeCard, setActiveCard] = useState(0)

  useEffect(() => {
    const id = setInterval(() => setActiveCard(c => (c + 1) % FLOW_CARDS.length), 2800)
    return () => clearInterval(id)
  }, [])

  const totalH = BLOCKS.reduce((s, _, i) => s + blockH(i) + BGAP, 0)
  const tokenPath = BLOCKS.map((_, i) => `${i === 0 ? 'M' : 'L'}${BLEFT + BW / 2},${blockY(i) + blockH(i) / 2}`).join(' ')

  return (
    <Frame n={9} kicker="Hardware LOB Accelerator · RTL Internals" title="LOB Datapath: Hash → Slot → Price RAM → BBO">
      {/* LEFT: Block chain SVG */}
      <svg width={420} height={820} viewBox={`0 0 420 820`}
        style={{ position: 'absolute', left: 80, top: 175 }}>
        <defs>
          <marker id="ah9" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
          <filter id="glow9"><feGaussianBlur stdDeviation="3" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        </defs>
        {/* Vertical spine line */}
        <line x1={BLEFT + BW / 2} y1={blockH(0)} x2={BLEFT + BW / 2} y2={totalH - blockH(7)}
          stroke="#e2e8f0" strokeWidth={2} />

        {BLOCKS.map((b, i) => {
          const y = blockY(i)
          const h = blockH(i)
          return (
            <g key={b.label}>
              <rect x={BLEFT} y={y} width={BW} height={h}
                fill={b.bg} stroke={b.col} strokeWidth={b.special ? 2.2 : 1.5} rx={6} />
              <text x={BLEFT + BW / 2} y={y + (b.special ? 22 : 20)} textAnchor="middle"
                style={{ font: `700 ${b.special ? '17px' : '15px'} var(--font)`, fill: b.col }}>
                {b.label}
              </text>
              <text x={BLEFT + BW / 2} y={y + (b.special ? 40 : 36)} textAnchor="middle"
                style={{ font: '500 11px var(--mono)', fill: '#6b7280' }}>
                {b.file}
              </text>
              {b.sub && (
                <text x={BLEFT + BW / 2} y={y + 57} textAnchor="middle"
                  style={{ font: '400 11px var(--font)', fill: '#4a4e57' }}>{b.sub}</text>
              )}
              {b.sub2 && (
                <text x={BLEFT + BW / 2} y={y + 73} textAnchor="middle"
                  style={{ font: '400 11px var(--font)', fill: '#4a4e57' }}>{b.sub2}</text>
              )}
              {/* Arrow to next */}
              {i < BLOCKS.length - 1 && (
                <line x1={BLEFT + BW / 2} y1={y + h} x2={BLEFT + BW / 2} y2={y + h + BGAP - 2}
                  stroke="#2a2e86" strokeWidth={1.8} markerEnd="url(#ah9)" />
              )}
            </g>
          )
        })}

        {/* Animated tokens flowing downward */}
        <circle r={8} fill="#2a2e86" filter="url(#glow9)">
          <animateMotion dur="3s" begin="0s" repeatCount="indefinite" path={tokenPath} />
        </circle>
        <circle r={6} fill="#2a2e86" opacity={0.5}>
          <animateMotion dur="3s" begin="1s" repeatCount="indefinite" path={tokenPath} />
        </circle>
      </svg>

      {/* RIGHT: Flow operation cards */}
      <div style={{ position: 'absolute', left: 560, top: 175, width: 1060, right: 96 }}>
        <div className="label rise" style={{ ...delay(0.15), marginBottom: 16 }}>
          Hardware Execution Flows
        </div>

        {FLOW_CARDS.map((c, i) => (
          <div
            key={c.title}
            className="rise"
            style={{
              ...delay(0.2 + i * 0.1),
              background: i === activeCard ? `${c.color}08` : 'white',
              border: `1.5px solid ${i === activeCard ? c.color : '#e2e8f0'}`,
              borderLeft: `6px solid ${c.color}`,
              padding: '16px 20px',
              borderRadius: 6,
              marginBottom: 12,
              transition: 'all 0.4s ease',
              boxShadow: i === activeCard ? `0 4px 16px ${c.color}22` : '0 2px 6px rgba(0,0,0,0.04)',
            }}
          >
            <div style={{ font: '700 20px var(--font)', color: c.color, marginBottom: 8 }}>{c.title}</div>
            {c.lines.map(l => (
              <div key={l} style={{ font: '400 17px/1.4 var(--font)', color: '#334155', marginBottom: 3, paddingLeft: 12, borderLeft: '2px solid #e2e8f0' }}>
                {l}
              </div>
            ))}
          </div>
        ))}

        {/* Resource utilization table */}
        <div className="rise" style={{ ...delay(0.7), marginTop: 20, background: 'white', border: '1.5px solid #e2e8f0', borderRadius: 6, padding: '14px 20px' }}>
          <div style={{ font: '600 13px var(--mono)', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 10 }}>
            Artix-7 Resource Budget (LOB Core)
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr', gap: 8 }}>
            {[
              { r: 'BRAM (36Kb)', v: '37 / 135', pct: '27.4%', col: '#2a2e86' },
              { r: 'DSP48E1', v: '18 / 240', pct: '7.5%', col: '#0891b2' },
              { r: 'Slice LUTs', v: '20,604', pct: '32.5%', col: '#7c3aed' },
              { r: 'Registers', v: '35,347', pct: '27.9%', col: '#059669' },
            ].map(r => (
              <div key={r.r} style={{ textAlign: 'center' }}>
                <div style={{ font: '700 22px var(--mono)', color: r.col }}>{r.pct}</div>
                <div style={{ font: '600 12px var(--mono)', color: '#4a4e57' }}>{r.r}</div>
                <div style={{ font: '400 12px var(--mono)', color: '#94a3b8' }}>{r.v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Latency table */}
        <div className="rise" style={{ ...delay(0.85), marginTop: 12, background: 'white', border: '1.5px solid #e2e8f0', borderRadius: 6, padding: '14px 20px' }}>
          <div style={{ font: '600 13px var(--mono)', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 10 }}>
            Deterministic Operation Latency
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            {[
              { op: 'ADD', lat: '6 cycles', ns: '60 ns', col: '#2a2e86' },
              { op: 'EXECUTE', lat: '8-10 cycles', ns: '80-100 ns', col: '#ea580c' },
              { op: 'CANCEL', lat: '8-10 cycles', ns: '80-100 ns', col: '#7c3aed' },
              { op: 'REPLACE', lat: '12 cycles', ns: '120 ns', col: '#059669' },
            ].map(r => (
              <div key={r.op} style={{ textAlign: 'center', padding: '8px', borderLeft: `4px solid ${r.col}`, background: `${r.col}08` }}>
                <div style={{ font: '700 18px var(--mono)', color: r.col }}>{r.op}</div>
                <div style={{ font: '600 16px var(--font)', color: '#16181d' }}>{r.lat}</div>
                <div style={{ font: '400 14px var(--mono)', color: '#6b7280' }}>{r.ns}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Frame>
  )
}
