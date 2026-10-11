import { useCallback, useEffect, useState } from 'react'
import Slide1_SystemOverview from './diagrams/Slide1_SystemOverview'
import Slide2_CPUPipeline from './diagrams/Slide2_CPUPipeline'
import Slide3_RV32M from './diagrams/Slide3_RV32M'
import Slide4_LOBCore from './diagrams/Slide4_LOBCore'
import Slide5_TimingDiagram from './diagrams/Slide5_TimingDiagram'
import Slide6_ModuleTable from './diagrams/Slide6_ModuleTable'

interface SlideConfig {
  id: string
  title: string
  kicker: string
  component: React.ReactElement
  isNew?: boolean
}

const SLIDES: SlideConfig[] = [
  {
    id: 'system',
    title: 'Top-Level System Architecture',
    kicker: 'FULL-PAGE HARDWARE BLOCK DIAGRAM · 3 CLOCK DOMAINS',
    component: <Slide1_SystemOverview />,
  },
  {
    id: 'pipeline',
    title: 'RV32IM CPU Pipeline & Execution Stages',
    kicker: 'IF · ID · EX · WB STAGES · HAZARD LOGIC · FORWARDING BUS',
    component: <Slide2_CPUPipeline />,
  },
  {
    id: 'rv32m',
    title: 'RV32M Multiplier & Restoring Divider',
    kicker: '★ NEW HARDWARE EXTENSION · 3-CYCLE MUL · 33-CYCLE DIV',
    component: <Slide3_RV32M />,
    isNew: true,
  },
  {
    id: 'lob',
    title: 'Pure-Hardware Limit Order Book Accelerator',
    kicker: '10-CYCLE ADD SCHEDULE · 107 BRAM MEMORY STRUCTURES · BBO ENGINE',
    component: <Slide4_LOBCore />,
    isNew: true,
  },
  {
    id: 'timing',
    title: 'Pipeline Execution Timing Diagram',
    kicker: 'REAL 25-CYCLE RTL TRACE · MULTI-CYCLE STALLS · HAZARDS & FORWARDING',
    component: <Slide5_TimingDiagram />,
  },
  {
    id: 'modules',
    title: 'Module Summary & FPGA Resource Estimates',
    kicker: 'ALL 27 PROJECT MODULES · ARTIX-7 XC7A100T UTILIZATION · VERIFICATION',
    component: <Slide6_ModuleTable />,
  },
]

export default function App() {
  const [currentIdx, setCurrentIdx] = useState(0)
  const [scale, setScale] = useState(1)

  const goTo = useCallback((idx: number) => {
    const valid = Math.min(Math.max(idx, 0), SLIDES.length - 1)
    setCurrentIdx(valid)
    window.history.replaceState(null, '', `#${SLIDES[valid].id}`)
  }, [])

  useEffect(() => {
    const handleResize = () => {
      const sx = window.innerWidth / 1920
      const sy = window.innerHeight / 1080
      setScale(Math.min(sx, sy, 1))
    }
    handleResize()
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') {
        e.preventDefault()
        goTo(currentIdx + 1)
      } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
        e.preventDefault()
        goTo(currentIdx - 1)
      } else if (e.key >= '1' && e.key <= '6') {
        goTo(parseInt(e.key, 10) - 1)
      } else if (e.key === 'f' || e.key === 'F') {
        if (document.fullscreenElement) {
          void document.exitFullscreen()
        } else {
          void document.documentElement.requestFullscreen()
        }
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [currentIdx, goTo])

  const slide = SLIDES[currentIdx]

  return (
    <>
      <div
        className="stage"
        style={{
          transform: `translate(-50%, -50%) scale(${scale})`,
        }}
      >
        <section className="slide">
          {/* Header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="kicker rise">{slide.kicker}</div>
              <h1 className="title rise">{slide.title}</h1>
            </div>

            {/* Legend swatch in header */}
            <div className="legend-pills rise" style={{ marginTop: 12 }}>
              <div className="pill">
                <span className="pill-swatch" style={{ background: 'rgba(255,255,255,0.85)', borderColor: '#4a4e57' }} />
                <span>Existing CPU / Slaves</span>
              </div>
              <div className="pill">
                <span className="pill-swatch" style={{ background: '#e4e6f8', borderColor: 'var(--navy)', borderWidth: 2.5 }} />
                <span style={{ color: 'var(--navy)', fontWeight: 700 }}>★ NEW Hardware (RV32M / LOB)</span>
              </div>
              <div className="pill">
                <span className="pill-swatch" style={{ borderStyle: 'dashed', borderColor: '#8b8f98' }} />
                <span>Planned / Display</span>
              </div>
            </div>
          </div>

          {/* Navigation Bar */}
          <nav className="nav-bar rise">
            {SLIDES.map((s, i) => (
              <button
                key={s.id}
                className={`nav-tab${i === currentIdx ? ' active' : ''}`}
                onClick={() => goTo(i)}
              >
                <span>{i + 1}. {s.title}</span>
                {s.isNew && <span className="badge-new">NEW HW</span>}
              </button>
            ))}
          </nav>

          {/* Slide Content View */}
          <div key={slide.id} className="rise">
            {slide.component}
          </div>

          {/* Slide Footer */}
          <div className="foot">
            <span>
              {String(currentIdx + 1).padStart(2, '0')} / {String(SLIDES.length).padStart(2, '0')} · GROUP 09 · EE ACADEMIC PROJECT · RV32IM + FPGA LOB
            </span>
            <span className="dots">
              {SLIDES.map((_, i) => (
                <i
                  key={i}
                  className={`dot${i === currentIdx ? ' on' : ''}`}
                  onClick={() => goTo(i)}
                />
              ))}
            </span>
          </div>
        </section>
      </div>

      <div className="hint">
        ← → / Space navigate · 1–6 Jump · F Fullscreen
      </div>
    </>
  )
}
