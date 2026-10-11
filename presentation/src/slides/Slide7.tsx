import { Frame } from '../components/Frame'
import { Chip } from '../components/Art'
import { delay } from '../components/util'

const flow = [
  { h: 'Input', t: 'Recorded order events replayed into the book' },
  { h: 'Processing', t: 'Hardware LOB update, BBO search, CPU reads BBO over MMIO' },
  { h: 'Output', t: 'Best bid / ask on the 7-segment display, status on LEDs' },
]

const challenges = [
  'Quantity overflow and underflow: fail-stop, never a corrupt book',
  'Hash collisions: bounded sets plus stash, capacity proven',
  'BBO consistency while the book is updating',
  'FPGA timing: CPU has only run at 1 Hz on the board so far',
]

export default function Slide7() {
  return (
    <Frame n={7} kicker="Visible on the FPGA" title="Demo plan + challenges">
      <Chip style={{ left: 1330, top: 120 }} label="FPGA" />
      <div style={{ display: 'grid', gridTemplateColumns: '1000px 1fr', gap: 70, marginTop: 40 }}>
        <div>
          <div className="label rise" style={delay(0.15)}>Demo plan</div>
          {flow.map((f, i) => (
            <div key={f.h} className="step rise" style={{ gridTemplateColumns: '210px 1fr', ...delay(0.25 + i * 0.14) }}>
              <div className="mono" style={{ font: '600 26px var(--mono)', color: 'var(--navy)', letterSpacing: '.05em' }}>{f.h.toUpperCase()}</div>
              <h4 style={{ font: '400 32px/1.3 var(--font)' }}>{f.t}</h4>
            </div>
          ))}
        </div>
        <div />
      </div>
      <div style={{ marginTop: 44, width: 1500 }}>
        <div className="label rise" style={delay(0.7)}>Challenges</div>
        <ul className="bullets" style={{ marginTop: 14 }}>
          {challenges.map((c, i) => <li key={c} className="rise" style={delay(0.8 + i * 0.1)}>{c}</li>)}
        </ul>
      </div>
    </Frame>
  )
}
