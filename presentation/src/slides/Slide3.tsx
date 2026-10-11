import { useEffect, useState } from 'react'
import { Frame } from '../components/Frame'
import { BUBBLES, CAPTIONS, CYCLES, ROWS } from '../data/trace'
import type { Kind } from '../data/trace'

const LEGEND: { k: Kind | 'FWD'; label: string }[] = [
  { k: 'IF', label: 'fetch' },
  { k: 'ID', label: 'decode' },
  { k: 'EX', label: 'execute' },
  { k: 'M', label: 'RV32M busy' },
  { k: 'WB', label: 'writeback' },
  { k: 'HOLD', label: 'held' },
]

const legendStyle = (k: string) => {
  switch (k) {
    case 'IF': return { background: '#fff' }
    case 'ID': return { background: '#e5e6f5' }
    case 'EX': return { background: 'var(--navy)' }
    case 'M': return { background: 'repeating-linear-gradient(135deg,#2a2e86 0 4px,#5a5fb8 4px 8px)' }
    case 'WB': return { background: 'var(--ink)' }
    default: return { background: 'transparent', borderStyle: 'dashed' }
  }
}

export default function Slide3({ active }: { active: boolean }) {
  const [cur, setCur] = useState(0)
  const [playing, setPlaying] = useState(true)

  useEffect(() => {
    if (!active) { setCur(0); setPlaying(true); return }
    if (!playing) return
    const id = setInterval(() => {
      setCur((c) => {
        if (c >= CYCLES - 1) { setPlaying(false); return c }
        return c + 1
      })
    }, 520)
    return () => clearInterval(id)
  }, [active, playing])

  const cols = Array.from({ length: CYCLES }, (_, i) => i)

  return (
    <Frame n={3} kicker="RTL simulation trace · 25 cycles" title="Timing diagram: MUL and DIV in the pipeline">
      <div className="grid-wrap rise" style={{ position: 'relative', width: 1700, marginTop: 14 }}>
        <div className="tgrid">
          <div className="hd" />
          {cols.map((c) => <div key={c} className={`hd${c === cur ? ' cur' : ''}`}>{c}</div>)}
          {ROWS.map((r) => (
            <Row key={r.pc} row={r} cur={cur} />
          ))}
          <div className="ins" style={{ color: 'var(--warn)' }}><small /> EX bubble</div>
          {cols.map((c) => (
            <div key={c} className={`cell${c > cur ? ' off' : ''}`}>
              {BUBBLES.includes(c) && <span style={{ borderColor: 'var(--warn)', color: 'var(--warn)', background: 'transparent' }}>×</span>}
            </div>
          ))}
        </div>
        <div className="colhi" style={{ left: 400 + cur * 52 }} />
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 24, marginTop: 22 }}>
        <button className="btn" onClick={() => { if (cur >= CYCLES - 1) setCur(0); setPlaying((p) => !p) }}>{playing ? 'PAUSE' : 'PLAY'}</button>
        <button className="btn" onClick={() => { setPlaying(false); setCur((c) => Math.max(0, c - 1)) }}>← STEP</button>
        <button className="btn" onClick={() => { setPlaying(false); setCur((c) => Math.min(CYCLES - 1, c + 1)) }}>STEP →</button>
        <div className="mono" style={{ fontSize: 26, color: 'var(--navy)', fontWeight: 600 }}>T{cur}</div>
        <div style={{ font: '400 28px var(--font)' }}>{CAPTIONS[cur]}</div>
      </div>

      <div className="legend" style={{ marginTop: 20 }}>
        {LEGEND.map((l) => <span key={l.k}><i style={legendStyle(l.k)} />{l.label}</span>)}
        <span><i style={{ boxShadow: '0 0 0 3px var(--ok)' }} />forwarded operand</span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48, marginTop: 26 }}>
        <Point label="Multi-cycle">MUL stalls EX for 3 cycles. DIV stalls for 33.</Point>
        <Point label="Stall behaviour">Front end is held. Skid buffer keeps the fetched word.</Point>
        <Point label="Forwarding">add uses x3 and mul x6 uses x5 straight from WB, no extra stall.</Point>
      </div>
    </Frame>
  )
}

function Point({ label, children }: { label: string; children: string }) {
  return (
    <div>
      <div className="label">{label}</div>
      <p style={{ font: '400 25px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

function Row({ row, cur }: { row: (typeof ROWS)[number]; cur: number }) {
  return (
    <>
      <div className="ins"><small>{row.pc}</small>{row.asm}</div>
      {Array.from({ length: CYCLES }, (_, c) => {
        const k = row.cells[c]
        if (!k) return <div key={c} className="cell" />
        const label = k === 'HOLD' ? '–' : k === 'M' ? 'M' : k
        return (
          <div key={c} className={`cell ${k}${row.fwd?.includes(c) ? ' fwd' : ''}${c > cur ? ' off' : ''}`}>
            <span>{label}</span>
          </div>
        )
      })}
    </>
  )
}
