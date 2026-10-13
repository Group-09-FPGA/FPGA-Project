import { useCallback, useEffect, useState } from 'react'
import { Play, Pause, RotateCcw, ChevronLeft, ChevronRight } from 'lucide-react'
import { Frame } from '../components/Frame'
import { CAPTIONS, COLS, CYCLES, FORWARDING_ARROWS, ROWS, SIGNALS } from '../data/trace'
import type { Kind } from '../data/trace'

const COL_W = 46
const LABEL_W = 348 // 48px PC + 300px Asm
const ROW_H = 34
const SIG_H = 29

export default function Slide3({ active }: { active: boolean }) {
  const [cur, setCur] = useState(0)
  const [playing, setPlaying] = useState(true)

  const togglePlay = useCallback(() => {
    setCur((c) => {
      if (c >= CYCLES - 1) return 0
      return c
    })
    setPlaying((p) => !p)
  }, [])

  const stepBack = useCallback(() => {
    setPlaying(false)
    setCur((c) => Math.max(0, c - 1))
  }, [])

  const stepForward = useCallback(() => {
    setPlaying(false)
    setCur((c) => Math.min(CYCLES - 1, c + 1))
  }, [])

  const resetTrace = useCallback(() => {
    setPlaying(false)
    setCur(0)
  }, [])

  // Keyboard shortcut: P toggles play/pause on this slide
  useEffect(() => {
    if (!active) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'p' || e.key === 'P') {
        e.preventDefault()
        togglePlay()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [active, togglePlay])

  // Animation ticker
  useEffect(() => {
    if (!active || !playing) return
    const id = setInterval(() => {
      setCur((c) => {
        if (c >= CYCLES - 1) {
          setPlaying(false)
          return c
        }
        return c + 1
      })
    }, 550)
    return () => clearInterval(id)
  }, [active, playing])

  const curCol = COLS[cur]
  const curBadge = curCol.isFold ? 'T25–T52' : curCol.label
  const isEnded = cur >= CYCLES - 1

  return (
    <Frame
      n={6}
      compactHeader
      kicker="Figure 3 · Cycle-Accurate RTL Simulation Trace (100 MHz)"
      title="Figure 3 · Pipeline Timing: EX-to-EX Forwarding, Hazards & RV32M Multi-Cycle Ops"
    >
      <div className="td-container rise">
        {/* Subtitle row with quick play/pause badge */}
        <div className="td-header-row">
          <div className="td-subtitle">
            Exact cycle-by-cycle trace from cpu_core + sys_bus_interconnect + imem/dmem slaves | 1 Cycle = 1 Clock Period (10 ns @ 100 MHz) | Stages: IF/ID (Fetch+Decode), EX (Execute/M-Unit), MEM/WB (Bus/Writeback) | tcq propagation delay shown on stages &amp; signals
          </div>
          <button
            className={`td-top-playpause${playing ? ' active' : ''}`}
            onClick={togglePlay}
            title={playing ? 'Pause animation (P)' : 'Play animation (P)'}
            aria-label={playing ? 'Pause animation' : 'Play animation'}
          >
            <span className={`td-status-dot ${playing ? 'live' : 'paused'}`} />
            {isEnded ? (
              <>
                <RotateCcw size={13} />
                <span>REPLAY</span>
              </>
            ) : playing ? (
              <>
                <Pause size={13} fill="currentColor" />
                <span>PAUSE</span>
              </>
            ) : (
              <>
                <Play size={13} fill="currentColor" />
                <span>PLAY</span>
              </>
            )}
          </button>
        </div>
        <div className="td-subtitle-rule" />

        {/* Timing Diagram Main Body */}
        <div className="td-grid-wrap">
          {/* Active Cycle Column Highlight */}
          <div className="td-colhi" style={{ left: LABEL_W + cur * COL_W }} />

          {/* Table Header Row */}
          <div className="td-table-header">
            <div className="td-th-pc">PC</div>
            <div className="td-th-ins">Instruction &amp; Operations</div>
            {COLS.map((c, i) => (
              <div
                key={c.id}
                className={`td-th-col${c.isFold ? ' td-th-fold' : ''}${i === cur ? ' cur' : ''}`}
              >
                {c.isFold ? (
                  <svg width="26" height="20" viewBox="0 0 24 18" style={{ display: 'inline-block', verticalAlign: 'middle' }}>
                    <path d="M 4 2 L 10 16 L 14 2 L 20 16" fill="none" stroke="var(--ink-3)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                ) : (
                  c.label
                )}
              </div>
            ))}
          </div>

          {/* Instruction Rows */}
          <div className="td-rows-wrap">
            {ROWS.map((row, rIdx) => (
              <div key={row.pc} className="td-row">
                <div className="td-pc">{row.pc}</div>
                <div className="td-asm">{row.asm}</div>
                {COLS.map((col, cIdx) => {
                  const k = row.cells[cIdx]
                  const isOff = cIdx > cur
                  const isFold = col.isFold

                  return (
                    <div
                      key={col.id}
                      className={`td-cell-col${isFold ? ' td-fold-col' : ''}`}
                    >
                      {/* Dashed line through fold for multi-cycle ops */}
                      {isFold && (rIdx === 10 || rIdx === 11) && !k && (
                        <div className="td-fold-dashed" />
                      )}

                      {k && (
                        <span
                          className={`td-badge ${badgeClass(k)}${isOff ? ' off' : ''}`}
                        >
                          {badgeText(k)}
                        </span>
                      )}
                    </div>
                  )
                })}
              </div>
            ))}

            {/* Rotated text for divider stall fold column */}
            <div className="td-fold-text-vertical">
              T25 - T52: Radix-2 Divider (33 cyc stall)
            </div>

            {/* SVG overlay for Forwarding Arrows */}
            <svg
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                height: '100%',
                pointerEvents: 'none',
                zIndex: 3,
              }}
            >
              <defs>
                <marker
                  id="arrow-green"
                  viewBox="0 0 8 8"
                  refX="6"
                  refY="4"
                  markerWidth="6"
                  markerHeight="6"
                  orient="auto-start-reverse"
                >
                  <polygon points="0 1, 7 4, 0 7" fill="#15803d" />
                </marker>
              </defs>
              {FORWARDING_ARROWS.map((arrow, i) => {
                const x1 = LABEL_W + arrow.fromCol * COL_W + COL_W / 2 + 21
                const y1 = arrow.fromRow * ROW_H + ROW_H / 2
                const x2 = LABEL_W + arrow.toCol * COL_W + COL_W / 2 - 21
                const y2 = arrow.toRow * ROW_H + ROW_H / 2
                const cornerX = x2 - 5
                const isOff = arrow.toCol > cur

                return (
                  <path
                    key={i}
                    d={`M ${x1} ${y1} H ${cornerX} V ${y2} H ${x2}`}
                    fill="none"
                    stroke="#15803d"
                    strokeWidth="2.5"
                    strokeLinejoin="round"
                    markerEnd="url(#arrow-green)"
                    style={{ opacity: isOff ? 0.15 : 1, transition: 'opacity 0.25s' }}
                  />
                )
              })}
            </svg>
          </div>

          {/* Hardware Control Signals Banner */}
          <div className="td-signals-banner">
            Hardware Control Signals &amp; Bus Protocol (RTL cycle-accurate waveforms from sim)
          </div>

          {/* SVG Waveforms */}
          <svg
            className="td-waveforms-svg"
            width="1728"
            height={SIGNALS.length * SIG_H + 4}
            viewBox={`0 0 1728 ${SIGNALS.length * SIG_H + 4}`}
          >
            {/* Background Column Grid Lines */}
            {COLS.map((col, idx) => {
              const x = LABEL_W + idx * COL_W
              return (
                <line
                  key={col.id}
                  x1={x}
                  y1={0}
                  x2={x}
                  y2={SIGNALS.length * SIG_H + 4}
                  stroke={col.isFold ? '#cbd5e1' : '#f1f5f9'}
                  strokeDasharray={col.isFold ? '3 3' : undefined}
                  strokeWidth="1"
                />
              )
            })}

            {/* Vertical border line between left labels and waveform tracks */}
            <line
              x1={LABEL_W}
              y1={0}
              x2={LABEL_W}
              y2={SIGNALS.length * SIG_H + 4}
              stroke="#e2e8f0"
              strokeWidth="1.5"
            />

            {/* Fold column background shading */}
            <rect
              x={LABEL_W + 25 * COL_W}
              y={0}
              width={COL_W}
              height={SIGNALS.length * SIG_H + 4}
              fill="#fafafa"
            />

            {/* Signal Tracks */}
            {SIGNALS.map((sig, sIdx) => {
              const yBase = sIdx * SIG_H
              const yHigh = yBase + 4
              const yLow = yBase + 25

              return (
                <g key={sig.name}>
                  {/* Subtle track baseline */}
                  <line
                    x1={0}
                    y1={yBase + SIG_H}
                    x2={1728}
                    y2={yBase + SIG_H}
                    stroke="#f1f5f9"
                    strokeWidth="1"
                  />

                  {/* Left Label: Name + Description (positioned comfortably before waveforms begin at x=348) */}
                  <text
                    x={10}
                    y={yBase + 19}
                    fontFamily="var(--mono)"
                    fontSize="14"
                    fontWeight="700"
                    fill="var(--navy)"
                  >
                    {sig.name}
                  </text>
                  <text
                    x={120}
                    y={yBase + 19}
                    fontFamily="var(--font)"
                    fontSize="12"
                    fill="var(--ink-2)"
                  >
                    {sig.label}
                  </text>

                  {/* Waveform Path */}
                  {sig.name === 'clk' ? (
                    // Clock square wave with 50% duty cycle
                    COLS.map((col, cIdx) => {
                      const x0 = LABEL_W + cIdx * COL_W
                      const xMid = x0 + COL_W / 2
                      const x1 = x0 + COL_W
                      const isOff = cIdx > cur

                      if (col.isFold) {
                        return (
                          <line
                            key={cIdx}
                            x1={x0}
                            y1={yLow}
                            x2={x1}
                            y2={yLow}
                            stroke={sig.color}
                            strokeWidth="1.8"
                            strokeDasharray="4 4"
                            opacity={isOff ? 0.15 : 1}
                          />
                        )
                      }

                      return (
                        <path
                          key={cIdx}
                          d={`M ${x0} ${yLow} V ${yHigh} H ${xMid} V ${yLow} H ${x1}`}
                          fill="none"
                          stroke={sig.color}
                          strokeWidth="1.8"
                          opacity={isOff ? 0.15 : 1}
                        />
                      )
                    })
                  ) : (
                    // Digital Signal Waveform
                    COLS.map((col, cIdx) => {
                      const prevVal = cIdx === 0 ? 0 : sig.values[cIdx - 1]
                      const curVal = sig.values[cIdx]
                      const x0 = LABEL_W + cIdx * COL_W
                      const x1 = x0 + COL_W
                      const isOff = cIdx > cur
                      const badge = sig.badges?.[cIdx]

                      if (col.isFold) {
                        // In fold column
                        const y = curVal ? yHigh : yLow
                        return (
                          <line
                            key={cIdx}
                            x1={x0}
                            y1={y}
                            x2={x1}
                            y2={y}
                            stroke={sig.color}
                            strokeWidth="2"
                            strokeDasharray={curVal ? '4 4' : undefined}
                            opacity={isOff ? 0.15 : 1}
                          />
                        )
                      }

                      const yPrev = prevVal ? yHigh : yLow
                      const yCur = curVal ? yHigh : yLow
                      // All displayed control signals change half a cycle into the column.
                      const xStep = x0 + COL_W / 2

                      return (
                        <g key={cIdx} opacity={isOff ? 0.15 : 1}>
                          <path
                            d={
                              prevVal !== curVal
                                ? `M ${x0} ${yPrev} H ${xStep} V ${yCur} H ${x1}`
                                : `M ${x0} ${yCur} H ${x1}`
                            }
                            fill="none"
                            stroke={sig.color}
                            strokeWidth="2"
                          />

                          {/* "EX-EX" badge inside forwarding pulse */}
                          {badge && curVal === 1 && (
                            <text
                              x={x0 + COL_W / 2 + 1}
                              y={yHigh + 13}
                              fontFamily="var(--mono)"
                              fontSize="9.5"
                              fontWeight="800"
                              fill="#15803d"
                              textAnchor="middle"
                            >
                              {badge}
                            </text>
                          )}
                        </g>
                      )
                    })
                  )}
                </g>
              )
            })}
          </svg>
        </div>



        {/* Playback Controls & Dynamic Cycle Caption */}
        <div className="td-controls">
          {/* Main Pause / Play Button */}
          <button
            className={`td-btn-playpause${!playing ? ' paused' : ''}`}
            onClick={togglePlay}
            title={playing ? 'Pause animation (P)' : 'Play animation (P)'}
            aria-label={playing ? 'Pause animation' : 'Play animation'}
          >
            {isEnded ? (
              <>
                <RotateCcw size={18} />
                <span>REPLAY</span>
              </>
            ) : playing ? (
              <>
                <Pause size={18} fill="currentColor" />
                <span>PAUSE</span>
              </>
            ) : (
              <>
                <Play size={18} fill="currentColor" />
                <span>PLAY</span>
              </>
            )}
          </button>

          {/* Step Back Button */}
          <button
            className="td-step-btn"
            onClick={stepBack}
            title="Step backward one cycle (Left arrow)"
            aria-label="Step backward"
          >
            <ChevronLeft size={17} />
            <span>STEP</span>
          </button>

          {/* Step Forward Button */}
          <button
            className="td-step-btn"
            onClick={stepForward}
            title="Step forward one cycle (Right arrow)"
            aria-label="Step forward"
          >
            <span>STEP</span>
            <ChevronRight size={17} />
          </button>

          {/* Reset button (visible when moved) */}
          {cur > 0 && (
            <button
              className="td-step-btn"
              onClick={resetTrace}
              title="Reset to cycle T0"
              aria-label="Reset to T0"
              style={{ padding: '8px 12px' }}
            >
              <RotateCcw size={15} />
            </button>
          )}

          {/* Active Cycle Badge */}
          <div className="td-cycle-badge mono">{curBadge}</div>

          {/* Active Dynamic Caption */}
          <div className="td-caption">{CAPTIONS[cur]}</div>

          {/* Keyboard Hint */}
          <div className="td-key-hint">P: Play/Pause</div>
        </div>
      </div>
    </Frame>
  )
}

function badgeClass(k: Kind): string {
  switch (k) {
    case 'IF/ID': return 'IF_ID'
    case 'EX': return 'EX'
    case 'M': return 'M'
    case 'D': return 'D'
    case 'MEM/WB': return 'MEM_WB'
    case 'STALL': return 'STALL'
    case 'HOLD': return 'HOLD'
    case 'FLUSH': return 'FLUSH'
    default: return ''
  }
}

function badgeText(k: Kind): string {
  switch (k) {
    case 'HOLD': return '–'
    default: return k
  }
}
