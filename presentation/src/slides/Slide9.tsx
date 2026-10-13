import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

interface BoxProps { x: number; y: number; w: number; h: number; t: string; s?: string; isNew?: boolean; d?: number }
function Box({ x, y, w, h, t, s, isNew, d = 0 }: BoxProps) {
  const stroke = isNew ? 'var(--navy)' : '#8b8f98'
  const cy = y + h / 2
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h} rx={3}
        fill={isNew ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
        stroke={stroke} strokeWidth={isNew ? 2.6 : 1.6} />
      <text x={x + w / 2} y={s ? cy - 6 : cy + 7} textAnchor="middle"
        style={{ font: '600 22px var(--font)', fill: isNew ? '#101234' : 'var(--ink-2)' }}>{t}</text>
      {s && <text x={x + w / 2} y={cy + 18} textAnchor="middle"
        style={{ font: '500 13.5px var(--mono)', fill: 'var(--ink-2)' }}>{s}</text>}
    </g>
  )
}

function Group({ x, y, w, h, label, isNew, d = 0 }: { x: number; y: number; w: number; h: number; label: string; isNew?: boolean; d?: number }) {
  const c = isNew ? 'var(--navy)' : '#8b8f98'
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h} fill="none" stroke={c} strokeWidth={1.5} strokeDasharray="9 7" />
      {label && <text x={x + 14} y={y - 12} style={{ font: '600 19px var(--mono)', fill: c, letterSpacing: '.08em' }}>{label}</text>}
    </g>
  )
}

function Arrow({ d, isNew, vert }: { d: string; isNew?: boolean; vert?: boolean }) {
  const c = isNew ? 'var(--navy)' : '#6b6f78'
  const mid = vert ? 'url(#ah9v)' : `url(#ah9${isNew ? 'n' : 'g'})`
  return <path d={d} fill="none" stroke={c} strokeWidth={2.4} markerEnd={mid} />
}

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 25px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

export default function Slide9() {
  // vertical chain positions: widened to 330px with ample margins
  const BW = 330, BH = 86, BX = 30
  const BY = [20, 118, 216, 314, 412, 510, 608]
  const mmioCenterY = BY[6] + BH / 2
  const cpuReadCenterX = BX + BW + 46 + 105
  const tokenPath = `M${BX + BW / 2},${BY[0]} V${mmioCenterY} H${cpuReadCenterX}`
  const LABELS = [
    { t: 'Hash table',     s: '1024 × 8-way · 8 CAM stash',       isNew: true },
    { t: 'Slot table',     s: '2048 entries · {side, pidx, qty}', isNew: true },
    { t: 'Free list',      s: 'LIFO stack · 0..2047 indices',     isNew: true },
    { t: 'Price RAM',      s: 'Bid + Ask banks · 8192 levels',    isNew: true },
    { t: 'Occupancy',      s: 'L0/L1/L2 hierarchical bitmaps',    isNew: true },
    { t: 'BBO engine',     s: 'DSP48 · base + pidx × tick',       isNew: true },
    { t: 'MMIO regs',      s: '0x4000_0000 · coherent snapshot',  isNew: true },
  ]

  return (
    <Frame n={4} kicker="Hardware LOB Accelerator · RTL Internals" title="LOB engine: Hash → Slot → Price RAM → BBO">
      <svg width={1728} height={830} viewBox="0 -10 1728 830" overflow="visible"
        style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="ah9g" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#6b6f78" />
          </marker>
          <marker id="ah9n" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* Event-in arrow at the top */}
        <g className="rise" style={delay(0.1)}>
          <line x1={BX + BW / 2} y1={-6} x2={BX + BW / 2} y2={18} stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah9n)" />
          <text x={BX + BW / 2 + 14} y={10} style={{ font: '500 16px var(--mono)', fill: 'var(--ink-2)' }}>256-bit event in</text>
        </g>

        {/* Vertical chain */}
        {LABELS.map((l, i) => (
          <Box key={l.t} x={BX} y={BY[i]} w={BW} h={BH} t={l.t} s={l.s} isNew={l.isNew} d={0.15 + i * 0.1} />
        ))}

        {/* Connecting arrows */}
        {LABELS.slice(0, -1).map((_, i) => (
          <Arrow key={i} isNew d={`M${BX + BW / 2},${BY[i] + BH} V${BY[i + 1] - 2}`} />
        ))}

        {/* MMIO output arrow + CPU bus target badge (clean, completely isolated from right column) */}
        <g className="rise" style={delay(1.1)}>
          <line x1={BX + BW} y1={BY[6] + BH / 2} x2={BX + BW + 42} y2={BY[6] + BH / 2} stroke="var(--navy)" strokeWidth={2.4} markerEnd="url(#ah9n)" />
          <rect x={BX + BW + 46} y={BY[6] + 10} width={210} height={66} rx={4}
            fill="#e3e4f4" stroke="var(--navy)" strokeWidth={1.8} />
          <text x={BX + BW + 46 + 105} y={BY[6] + 37} textAnchor="middle"
            style={{ font: '700 13px var(--mono)', fill: '#101234' }}>CPU reads BBO via MMIO</text>
          <text x={BX + BW + 46 + 105} y={BY[6] + 59} textAnchor="middle"
            style={{ font: '500 11.5px var(--mono)', fill: 'var(--ink-2)' }}>0x4000_0000 · Bus Arbiter</text>
        </g>

        {/* Animated token flowing down the chain */}
        <circle r={6} fill="var(--navy)" opacity={0}>
          <animateMotion dur="3.5s" begin="1.5s" repeatCount="indefinite"
            path={tokenPath} />
          <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.08;0.92;1" dur="3.5s" begin="1.5s" repeatCount="indefinite" />
        </circle>
        <circle r={6} fill="var(--navy)" opacity={0}>
          <animateMotion dur="3.5s" begin="3s" repeatCount="indefinite"
            path={tokenPath} />
          <animate attributeName="opacity" values="0;0.45;0.45;0" keyTimes="0;0.08;0.92;1" dur="3.5s" begin="3s" repeatCount="indefinite" />
        </circle>

        {/* ── RIGHT: FSM states and latency table (comfortably placed at x=640) ──── */}
        <g className="rise" style={delay(0.6)}>
          {/* ADD flow */}
          <text x={640} y={40} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            ADD ORDER FLOW
          </text>
          {[
            'C1: hash OID → set index → 8-way lookup → slot#',
            'C2: pop slot# from free-list LIFO stack',
            'C3: write slot BRAM {side, pidx, qty}',
            'C4-C5: read Price RAM → add qty → writeback',
            'C6: set occupancy bit → check BBO update',
          ].map((l, i) => (
            <text key={i} x={640} y={68 + i * 32} style={{ font: '400 21px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
        </g>

        <g className="rise" style={delay(0.75)}>
          <text x={640} y={248} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            EXECUTE / CANCEL / REPLACE
          </text>
          {[
            'Hash OID → slot → read {pidx, shares}',
            'Deduct shares from Price RAM bank',
            'If qty=0 → clear occupancy bit → push slot to free list',
            'Trigger BBO re-search if depleted level was best price',
          ].map((l, i) => (
            <text key={i} x={640} y={276 + i * 32} style={{ font: '400 21px var(--font)', fill: 'var(--ink-2)' }}>{l}</text>
          ))}
        </g>

        {/* Latency table */}
        <g className="rise" style={delay(0.9)}>
          <text x={640} y={438} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            DETERMINISTIC LATENCY
          </text>
          <line x1={640} y1={448} x2={1720} y2={448} stroke="var(--line)" strokeWidth={1.5} />
          {[
            { op: 'ADD',       lat: '6 cycles',    ns: '60 ns  @ 100 MHz' },
            { op: 'EXECUTE',   lat: '8–10 cycles',  ns: '80–100 ns' },
            { op: 'CANCEL',    lat: '8–10 cycles',  ns: '80–100 ns' },
            { op: 'REPLACE',   lat: '12 cycles',    ns: '120 ns' },
          ].map((r, i) => (
            <g key={r.op}>
              <line x1={640} y1={508 + i * 50} x2={1720} y2={508 + i * 50} stroke="#e2e8f0" strokeWidth={1} />
              <text x={650} y={495 + i * 50} style={{ font: '700 22px var(--mono)', fill: 'var(--navy)' }}>{r.op}</text>
              <text x={900} y={495 + i * 50} style={{ font: '400 22px var(--font)', fill: 'var(--ink)' }}>{r.lat}</text>
              <text x={1220} y={495 + i * 50} style={{ font: '500 20px var(--mono)', fill: 'var(--ink-2)' }}>{r.ns}</text>
            </g>
          ))}
        </g>

        {/* Resource numbers */}
        <g className="rise" style={delay(1.05)}>
          <text x={640} y={670} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            ARTIX-7 RESOURCES
          </text>
          <line x1={640} y1={680} x2={1720} y2={680} stroke="var(--line)" strokeWidth={1.5} />
          {[
            { r: '37 BRAM (36Kb)', p: '27.4%' },
            { r: '18 DSP48E1', p: '7.5%' },
            { r: '20,604 LUTs', p: '32.5%' },
            { r: '35,347 Registers', p: '27.9%' },
          ].map((r, i) => (
            <g key={r.r}>
              <text x={640 + i * 270} y={714} style={{ font: '700 26px var(--mono)', fill: 'var(--ink)' }}>{r.p}</text>
              <text x={640 + i * 270} y={742} style={{ font: '400 19px var(--font)', fill: 'var(--ink-2)' }}>{r.r}</text>
            </g>
          ))}
        </g>
      </svg>
    </Frame>
  )
}
