import { Frame } from '../components/Frame'
import { Nut } from '../components/Art'
import { delay } from '../components/util'

const rows = [
  ['A', 'Golden model', 'Python book, event contract, test vectors. Then stretch: Ethernet + ITCH parser.'],
  ['B', 'LOB core', 'Hash + stash, slot table, free list, price RAM, with testbenches.'],
  ['C', 'BBO + MMIO + firmware', 'Occupancy hierarchy, MMIO slave, bus decode, C test programs.'],
  ['D', 'FPGA + demo', '100 MHz clocking, XDC constraints, synthesis, timing closure, demo.'],
]

export default function Slide6() {
  return (
    <Frame n={6} kicker="Non-overlapping ownership" title="Team responsibilities">
      <Nut x={1730} y={80} />
      <table className="tbl rise" style={{ marginTop: 40, ...delay(0.2) }}>
        <thead><tr><th>Member</th><th style={{ width: 560 }}>Responsibility</th><th>Deliverable</th></tr></thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={r[0]} className="rise" style={delay(0.3 + i * 0.12)}>
              <td className="m">{r[0]}</td>
              <td><b>{r[1]}</b></td>
              <td className="d">{r[2]}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Frame>
  )
}
