import { Frame } from '../components/Frame'
import { Gear } from '../components/Art'
import { delay } from '../components/util'

const steps = [
  { t: 'Golden model + event contract', p: 'Python book, canonical events, test vectors' },
  { t: 'Hash, slot table, free list', p: 'Modules + testbench, checked against the model' },
  { t: 'Price RAM + occupancy + BBO', p: 'Module + testbench, best bid / ask match' },
  { t: 'MMIO + CPU integration', p: 'Integrated simulation: C program reads BBO' },
]

const checks = [
  { h: 'Module level', l: ['Each module vs golden model vectors', 'Random event streams, bit-exact BBO'] },
  { h: 'Edge cases', l: ['Duplicate / missing order ID, quantity underflow', 'Hash set full, empty book, signed / unsigned, divide by zero'] },
  { h: 'Processor level', l: ['C programs on the CPU, compared against reference logs', 'RV32M already passes 236 unit + 31 pipeline checks'] },
]

export default function Slide4() {
  return (
    <Frame n={4} kicker="How we build it and prove it" title="Design + verification plan">
      <Gear cx={1790} cy={100} r={44} />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 80, marginTop: 36 }}>
        <div>
          <div className="label rise" style={delay(0.15)}>Implementation plan</div>
          <div style={{ marginTop: 10 }}>
            {steps.map((s, i) => (
              <div key={s.t} className="step rise" style={delay(0.25 + i * 0.12)}>
                <div className="n">{i + 1}</div>
                <div><h4>{s.t}</h4><p>{s.p}</p></div>
              </div>
            ))}
          </div>
        </div>
        <div>
          <div className="label rise" style={delay(0.15)}>Verification plan</div>
          <div style={{ marginTop: 10 }}>
            {checks.map((c, i) => (
              <div key={c.h} className="vgroup rise" style={delay(0.25 + i * 0.14)}>
                <h4 style={{ font: '600 34px var(--font)' }}>{c.h}</h4>
                <ul>{c.l.map((x) => <li key={x}>{x}</li>)}</ul>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Frame>
  )
}
