import { Frame } from '../components/Frame'
import { delay } from '../components/util'

interface Item { x: number; up: boolean; num: string; date: string; txt: string; ms?: boolean }

const items: Item[] = [
  { x: 40, up: true, num: '01', date: '11 Oct', txt: 'CPU + RV32M verified, architecture audit done' },
  { x: 380, up: false, num: '02', date: '18 Oct', txt: 'Golden model + event vectors in repo' },
  { x: 720, up: true, num: '03', date: '25 Oct', txt: 'Hash, slot table, free list pass their testbenches', ms: true },
  { x: 1060, up: false, num: '04', date: '1 Nov', txt: 'Minimum system: book + BBO + MMIO, CPU reads BBO in simulation', ms: true },
  { x: 1400, up: true, num: '05', date: 'Final phase', txt: 'Integration, 100 MHz timing, FPGA demo', ms: true },
]

export default function Slide5() {
  const y = 400
  return (
    <Frame n={10} kicker="Milestones" title="Timeline">
      <svg width="1728" height="640" viewBox="0 0 1728 640" style={{ position: 'absolute', left: 96, top: 210 }}>
        <line x1={0} y1={y} x2={1728} y2={y} stroke="var(--ink)" strokeWidth={2} className="draw" pathLength={1} style={delay(0.1)} />
        {items.map((it, i) => (
          <g key={it.num} className="rise" style={delay(0.35 + i * 0.2)}>
            <line x1={it.x + 20} y1={y} x2={it.x + 20} y2={it.up ? y - 70 : y + 70} stroke="var(--ink)" strokeWidth={1.5} />
            <rect x={it.x + 8} y={y - 12} width={24} height={24} transform={`rotate(45 ${it.x + 20} ${y})`} fill={it.ms ? 'var(--navy)' : 'var(--paper)'} stroke={it.ms ? 'var(--navy)' : 'var(--ink)'} strokeWidth={2} />
          </g>
        ))}
      </svg>
      {items.map((it, i) => (
        <div key={it.num} className={`tl-item rise${it.ms ? ' ms' : ''}`} style={{ left: 96 + it.x, top: it.up ? 210 + 400 - 70 - 215 : 210 + 400 + 82, ...delay(0.45 + i * 0.2), width: 330 }}>
          <div className="num">{it.num}</div>
          <div className="date">{it.date}</div>
          <div className="txt">{it.txt}</div>
        </div>
      ))}
      <div className="rise" style={{ ...delay(1.5), position: 'absolute', left: 96, right: 96, bottom: 70, font: '500 22px var(--mono)', color: 'var(--ink-2)' }}>
        Stretch (Ethernet + ITCH) starts only after milestone 04 is met.
      </div>
    </Frame>
  )
}
