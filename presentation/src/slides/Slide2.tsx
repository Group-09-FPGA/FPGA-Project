import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { Gear } from '../components/Art'
import { delay } from '../components/util'

interface BoxProps { x: number; y: number; w: number; h: number; t: string; s?: string; isNew?: boolean; d?: number }

function Box({ x, y, w, h, t, s, isNew, d = 0 }: BoxProps) {
  const stroke = isNew ? 'var(--navy)' : '#8b8f98'
  const cy = y + h / 2
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h} fill={isNew ? '#e3e4f4' : 'rgba(255,255,255,.55)'} stroke={stroke} strokeWidth={isNew ? 2.6 : 1.6} />
      <text x={x + w / 2} y={s ? cy - 4 : cy + 8} textAnchor="middle" style={{ font: '600 25px var(--font)', fill: isNew ? '#101234' : 'var(--ink-2)' }}>{t}</text>
      {s && <text x={x + w / 2} y={cy + 26} textAnchor="middle" style={{ font: '400 20px var(--font)', fill: 'var(--ink-2)' }}>{s}</text>}
    </g>
  )
}

function Group({ x, y, w, h, label, isNew, d = 0 }: { x: number; y: number; w: number; h: number; label: string; isNew?: boolean; d?: number }) {
  const c = isNew ? 'var(--navy)' : '#8b8f98'
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h} fill="none" stroke={c} strokeWidth={1.5} strokeDasharray="9 7" />
      <text x={x + 14} y={y - 12} style={{ font: '600 20px var(--mono)', fill: c, letterSpacing: '.08em' }}>{label}</text>
    </g>
  )
}

function Arrow({ d, isNew, anim }: { d: string; isNew?: boolean; anim?: boolean }) {
  const c = isNew ? 'var(--navy)' : '#6b6f78'
  return <path d={d} fill="none" stroke={c} strokeWidth={2.4} markerEnd={`url(#ah${isNew ? 'n' : 'o'})`} className={anim ? 'flowline' : undefined} />
}

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 25px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

export default function Slide2() {
  const gaps = [210, 480, 1160, 1440]
  return (
    <Frame n={2} kicker="Existing CPU in grey · new hardware in blue" title="System architecture">
      <Gear cx={1760} cy={110} r={46} />
      <svg width="1728" height="660" viewBox="0 -20 1728 660" overflow="visible" style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="aho" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#6b6f78" /></marker>
          <marker id="ahn" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" /></marker>
        </defs>

        {/* existing: CPU */}
        <Group x={0} y={30} w={1000} h={220} label="RV32IM CORE · 3 STAGES" d={0.1} />
        <Box x={24} y={56} w={210} h={80} t="IF / ID" s="fetch + decode" d={0.15} />
        <Box x={395} y={56} w={210} h={80} t="EX" s="ALU, branch, fwd" d={0.2} />
        <Box x={766} y={56} w={210} h={80} t="MEM / WB" s="bus access" d={0.25} />
        <Box x={395} y={152} w={210} h={72} t="RV32M unit" s="MUL 3 · DIV 33" d={0.3} />
        <Arrow d="M234,96 H393" />
        <Arrow d="M605,96 H764" />
        <path d="M500,136 V150" stroke="#6b6f78" strokeWidth={2.4} fill="none" />

        {/* existing: memories */}
        <Group x={1056} y={30} w={672} h={130} label="MEMORY + I/O" d={0.3} />
        <Box x={1076} y={56} w={196} h={80} t="IMEM" s="4 KB" d={0.35} />
        <Box x={1292} y={56} w={196} h={80} t="DMEM" s="4 KB" d={0.4} />
        <Box x={1508} y={56} w={196} h={80} t="7-seg + LED" d={0.45} />

        {/* bus */}
        <g className="rise" style={delay(0.5)}>
          <line x1={0} y1={330} x2={1728} y2={330} stroke="var(--ink)" strokeWidth={6} />
          <text x={0} y={310} style={{ font: '600 20px var(--mono)', fill: 'var(--ink-2)', letterSpacing: '.08em' }}>SYSTEM BUS</text>
          {[500, 1174, 1390, 1606].map((x) => <line key={x} x1={x} y1={x === 500 ? 250 : 160} x2={x} y2={330} stroke="#6b6f78" strokeWidth={2.4} />)}
        </g>

        {/* new hardware */}
        <text x={0} y={402} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>NEW · HARDWARE LIMIT ORDER BOOK</text>
        <Box x={0} y={440} w={210} h={130} t="Event source" s="replay, ITCH later" isNew d={0.6} />
        <Box x={270} y={440} w={210} h={130} t="Async FIFO" s="50 → 100 MHz" isNew d={0.7} />
        <Group x={540} y={425} w={620} h={190} label="" isNew d={0.8} />
        <text x={554} y={417} style={{ font: '600 20px var(--mono)', fill: 'var(--navy)' }} />
        <Box x={562} y={445} w={266} h={68} t="Hash + stash" isNew d={0.85} />
        <Box x={872} y={445} w={266} h={68} t="Slot table" isNew d={0.9} />
        <Box x={562} y={529} w={266} h={68} t="Free list" isNew d={0.95} />
        <Box x={872} y={529} w={266} h={68} t="Price RAM" isNew d={1.0} />
        <Box x={1220} y={440} w={220} h={130} t="BBO search" s="hierarchical" isNew d={1.05} />
        <Box x={1500} y={440} w={228} h={130} t="MMIO regs" s="0x4000_0000" isNew d={1.1} />

        <Arrow isNew d="M212,505 H268" />
        <Arrow isNew d="M482,505 H538" />
        <Arrow isNew d="M1162,505 H1218" />
        <Arrow isNew d="M1442,505 H1498" />
        <Arrow isNew d="M1680,440 V334" />

        {/* data tokens */}
        {gaps.map((x, i) => (
          <circle key={x} r={7} cx={x} cy={505} fill="var(--navy)" opacity={0}>
            <animate attributeName="cx" from={x} to={x + 56} dur="1.4s" begin={`${1.6 + i * 0.35}s`} repeatCount="indefinite" />
            <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.15;0.85;1" dur="1.4s" begin={`${1.6 + i * 0.35}s`} repeatCount="indefinite" />
          </circle>
        ))}
        <circle r={7} fill="var(--ink)" opacity={0}>
          <animateMotion dur="3.2s" begin="2s" repeatCount="indefinite" path="M1680,440 V330 H500 V250" />
          <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.08;0.92;1" dur="3.2s" begin="2s" repeatCount="indefinite" />
        </circle>

        <text x={1700} y={410} textAnchor="end" style={{ font: '500 20px var(--mono)', fill: 'var(--ink-2)' }}>BBO read ↑</text>
      </svg>

      <div style={{ position: 'absolute', left: 96, right: 96, top: 880, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48 }}>
        <Note label="Where it fits" d={1.2}>One new MMIO slave on the existing bus. Pipeline unchanged.</Note>
        <Note label="Data flow" d={1.3}>Event → FIFO → book → BBO search → registers.</Note>
        <Note label="Control flow" d={1.4}>CPU configures and reads. It is never in the per-event path.</Note>
      </div>
    </Frame>
  )
}
