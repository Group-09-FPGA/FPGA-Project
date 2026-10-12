import { useCallback, useEffect, useState } from 'react'
import Slide1 from './slides/Slide1'
import Slide2 from './slides/Slide2'
import Slide3 from './slides/Slide3'
import Slide4 from './slides/Slide4'
import Slide5 from './slides/Slide5'
import Slide6 from './slides/Slide6'
import Slide7 from './slides/Slide7'
import Slide8 from './slides/Slide8'
import Slide9 from './slides/Slide9'
import Slide10 from './slides/Slide10'
import Slide11 from './slides/Slide11'
import Slide12 from './slides/Slide12'
import { TOTAL } from './components/Frame'
import { NOTES } from './data/notes'

const readHash = () => {
  const n = parseInt(window.location.hash.replace('#', ''), 10)
  return Number.isFinite(n) ? Math.min(Math.max(n, 1), TOTAL) : 1
}

export default function App() {
  const [n, setN] = useState(readHash)
  const [scale, setScale] = useState(1)
  const [notes, setNotes] = useState(false)

  const go = useCallback((to: number) => {
    const v = Math.min(Math.max(to, 1), TOTAL)
    setN(v)
    window.history.replaceState(null, '', `#${v}`)
  }, [])

  useEffect(() => {
    const fit = () => setScale(Math.min(window.innerWidth / 1920, window.innerHeight / 1108))
    fit()
    window.addEventListener('resize', fit)
    return () => window.removeEventListener('resize', fit)
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') { e.preventDefault(); go(n + 1) }
      else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); go(n - 1) }
      else if (e.key === 'Home') go(1)
      else if (e.key === 'End') go(TOTAL)
      else if (e.key === 'n' || e.key === 'N') setNotes(v => !v)
      else if (e.key === 'f' || e.key === 'F') {
        if (document.fullscreenElement) void document.exitFullscreen()
        else void document.documentElement.requestFullscreen()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [n, go])

  // SLIDE ORDER:
  // 1  Overview
  // 2  System Architecture (block diagram)
  // 3  ITCH Parsing deep-dive      ← NEW (between arch & timing)
  // 4  LOB Engine internals        ← NEW (between arch & timing)
  // 5  BBO Priority Tree           ← NEW (between arch & timing)
  // 6  Timing Diagram (pipeline)
  // 7  MUL Unit                    ← NEW (after timing)
  // 8  DIV Unit                    ← NEW (after timing)
  // 9  Design + Verification Plan
  // 10 Timeline
  // 11 Team / Work Distribution
  // 12 Demo Plan
  const slides = [
    <Slide1 />,
    <Slide2 />,
    <Slide8 />,   // ITCH parsing
    <Slide9 />,   // LOB datapath
    <Slide10 />,  // BBO priority tree
    <Slide3 active />,
    <Slide11 />,  // MUL unit
    <Slide12 />,  // DIV unit
    <Slide4 />,
    <Slide5 />,
    <Slide6 />,
    <Slide7 />,
  ]
  const note = NOTES[n - 1] ?? NOTES[0]

  return (
    <>
      <div className="stage" style={{ transform: `translate(-50%, -50%) scale(${scale})` }}>
        <div key={n} style={{ position: 'absolute', inset: 0 }}>{slides[n - 1]}</div>
      </div>
      <div className="hint">← → navigate · F fullscreen · N notes</div>
      {notes && (
        <div className="notes">
          <h5>Slide {n} · target {note.time}</h5>
          <ul>{note.points.map(p => <li key={p}>{p}</li>)}</ul>
          <h5>Likely questions</h5>
          <ul>{note.qa.map(p => <li key={p}>{p}</li>)}</ul>
        </div>
      )}
    </>
  )
}
