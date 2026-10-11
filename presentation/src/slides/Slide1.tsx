import { Frame } from '../components/Frame'
import { Chip, Diagonal, Nut } from '../components/Art'
import { delay } from '../components/util'

const rows = [
  { tag: 'Commitment', color: 'var(--navy)', items: ['Python golden model + canonical event contract', 'Hardware order book: hash, slots, free list, price RAM'] },
  { tag: 'Goal', color: 'var(--ink)', items: ['BBO hierarchy + MMIO: CPU reads live best bid / ask', 'FPGA demo on Nexys A7-100T, BBO on the display'] },
  { tag: 'Stretch', color: 'var(--ink-3)', items: ['Ethernet RMII + MoldUDP64 + ITCH feed into the book'] },
]

export default function Slide1() {
  return (
    <Frame n={1} kicker="Project overview · scope" title={'RV32IM + Hardware\nLimit Order Book'}>
      <Diagonal x1={980} y1={1052} x2={1920} y2={160} />
      <Chip style={{ left: 1230, top: 300 }} />
      <Nut x={1710} y={880} />

      <div style={{ width: 1060, marginTop: 30 }}>
        <div className="rise" style={delay(0.2)}>
          <div className="label">Problem</div>
          <p className="body" style={{ marginTop: 6 }}>Software order books spend a variable, CPU-bound cost on every market message.</p>
        </div>

        <div className="rise" style={{ ...delay(0.35), marginTop: 26 }}>
          <div className="label">System</div>
          <ul className="bullets" style={{ marginTop: 8, gap: 6 }}>
            <li>RV32IM softcore on a Nexys A7-100T</li>
            <li>Pure-hardware limit order book, bounded cycles per event</li>
            <li>CPU configures it and reads best bid / ask over MMIO</li>
          </ul>
        </div>

        <div style={{ marginTop: 30 }}>
          <div className="label rise" style={{ ...delay(0.5), marginBottom: 8 }}>System scope</div>
          {rows.map((r, i) => (
            <div key={r.tag} className="scope-row rise" style={delay(0.6 + i * 0.12)}>
              <div className="tag" style={{ color: r.color }}>{r.tag}</div>
              <ul>{r.items.map((t) => <li key={t}>{t}</li>)}</ul>
            </div>
          ))}
        </div>
      </div>
    </Frame>
  )
}
