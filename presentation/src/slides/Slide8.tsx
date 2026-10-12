import { useCallback, useEffect, useState } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

const STAGES = [
  { id: 0, label: 'RMII RX', file: 'rmii_rx.sv', sub: '2-bit dibits + CRC-32', col: '#dbeafe', stroke: '#93c5fd', text: '#1e40af' },
  { id: 1, label: 'Net Parser', file: 'net_parser.sv', sub: 'IPv4 · UDP:10443', col: '#dcfce7', stroke: '#86efac', text: '#15803d' },
  { id: 2, label: 'MoldUDP64', file: 'moldudp64_decoder.sv', sub: 'Session · Seq# · Frames', col: '#fef9c3', stroke: '#fde047', text: '#854d0e' },
  { id: 3, label: 'ITCH 5.0', file: 'itch_decoder.sv', sub: "Type 'A' Add Order", col: '#ede9fe', stroke: '#c4b5fd', text: '#5b21b6' },
  { id: 4, label: '256-bit Event', file: 'Canonical Event', sub: 'OP·OID·QTY·PIDX', col: '#e3e4f4', stroke: '#2a2e86', text: '#101234' },
]

const BYTE_FIELDS = [
  { label: 'Type', bytes: '[0]', example: "'A'", col: '#1e40af', bg: '#dbeafe' },
  { label: 'Stock Loc', bytes: '[1-2]', example: '0x0001', col: '#15803d', bg: '#dcfce7' },
  { label: 'Track#', bytes: '[3-4]', example: '0x0000', col: '#6b7280', bg: '#f3f4f6' },
  { label: 'Timestamp', bytes: '[5-10]', example: '48-bit ns', col: '#7c3aed', bg: '#ede9fe' },
  { label: 'Order ID', bytes: '[11-18]', example: '0xABCD1234', col: '#ea580c', bg: '#ffedd5' },
  { label: 'Shares', bytes: '[19-22]', example: '500', col: '#dc2626', bg: '#fee2e2' },
  { label: 'Side', bytes: '[23]', example: "'B'=BID", col: '#0891b2', bg: '#cffafe' },
  { label: 'Price', bytes: '[24-27]', example: '$149.50', col: '#059669', bg: '#d1fae5' },
]

const EVT_FIELDS = [
  { bits: '[255:252]', label: 'VER=1', col: '#7c3aed', w: 68 },
  { bits: '[251:248]', label: 'OP=ADD', col: '#2a2e86', w: 78 },
  { bits: '[247]', label: 'BID', col: '#15803d', w: 46 },
  { bits: '[246:240]', label: 'rsvd', col: '#94a3b8', w: 58 },
  { bits: '[239:176]', label: 'OID=0xABCD1234EFAB...', col: '#ea580c', w: 240 },
  { bits: '[175:112]', label: 'NEW_OID=0 (ADD)', col: '#6b7280', w: 165 },
  { bits: '[95:64]', label: 'QTY=500', col: '#dc2626', w: 110 },
  { bits: '[44:32]', label: 'PIDX=142', col: '#0891b2', w: 105 },
  { bits: '[31:0]', label: 'TIMESTAMP_ns', col: '#6b7280', w: 140 },
]

const BOX_W = 230
const BOX_H = 108
const GAP = 84
const START_X = 30
const STAGE_Y = 50

const stageX = (i: number) => START_X + i * (BOX_W + GAP)
const stageCX = (i: number) => stageX(i) + BOX_W / 2

export default function Slide8() {
  const [step, setStep] = useState(0)
  const [playing, setPlaying] = useState(true)

  useEffect(() => {
    if (!playing) return
    const id = setInterval(() => setStep(s => (s + 1) % STAGES.length), 1900)
    return () => clearInterval(id)
  }, [playing])

  const tokenPath = STAGES.map((_, i) => `${i === 0 ? 'M' : 'L'}${stageCX(i)},${STAGE_Y + BOX_H / 2}`).join(' ')

  return (
    <Frame n={8} kicker="Network Ingestion Pipeline · Input Parsing" title="ITCH 5.0 Parsing: Raw Bytes → 256-bit Hardware Event">
      <svg width={1728} height={480} viewBox="0 0 1728 480" style={{ position: 'absolute', left: 96, top: 185 }}>
        <defs>
          <marker id="ah8n" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" /></marker>
          <marker id="ah8g" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#cbd5e1" /></marker>
          <filter id="glow8"><feGaussianBlur stdDeviation="3" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        </defs>

        {/* Input arrow */}
        <line x1={0} y1={STAGE_Y + BOX_H / 2} x2={START_X - 2} y2={STAGE_Y + BOX_H / 2} stroke="#2a2e86" strokeWidth={2.5} markerEnd="url(#ah8n)" />
        <text x={2} y={STAGE_Y + BOX_H / 2 - 14} style={{ font: '500 15px var(--mono)', fill: '#2a2e86' }}>LAN8720A PHY</text>

        {/* Stage boxes */}
        {STAGES.map((s, i) => {
          const x = stageX(i)
          const isActive = step === i
          return (
            <g key={s.id}>
              <rect x={x} y={STAGE_Y} width={BOX_W} height={BOX_H}
                fill={isActive ? s.col : 'rgba(255,255,255,0.8)'}
                stroke={isActive ? s.stroke : '#e2e8f0'}
                strokeWidth={isActive ? 3 : 1.5}
                rx={8}
              />
              {/* Active pulse ring */}
              {isActive && (
                <rect x={x - 3} y={STAGE_Y - 3} width={BOX_W + 6} height={BOX_H + 6}
                  fill="none" stroke={s.stroke} strokeWidth={1.5} strokeDasharray="4 3" rx={10} opacity={0.6} />
              )}
              <text x={x + BOX_W / 2} y={STAGE_Y + 26} textAnchor="middle"
                style={{ font: '700 20px var(--font)', fill: isActive ? s.text : '#16181d' }}>
                {s.label}
              </text>
              <text x={x + BOX_W / 2} y={STAGE_Y + 48} textAnchor="middle"
                style={{ font: '600 13px var(--mono)', fill: '#6b7280' }}>
                {s.file}
              </text>
              <text x={x + BOX_W / 2} y={STAGE_Y + 68} textAnchor="middle"
                style={{ font: '400 14px var(--font)', fill: '#4a4e57' }}>
                {s.sub}
              </text>
              {/* Clock badge */}
              <rect x={x + BOX_W / 2 - 34} y={STAGE_Y + BOX_H - 22} width={68} height={18} rx={9} fill={isActive ? s.stroke : '#f1f5f9'} />
              <text x={x + BOX_W / 2} y={STAGE_Y + BOX_H - 9} textAnchor="middle"
                style={{ font: '600 11px var(--mono)', fill: isActive ? 'white' : '#64748b' }}>
                {i < 4 ? '50 MHz' : '→ 100 MHz'}
              </text>
              {/* Arrow to next */}
              {i < STAGES.length - 1 && (
                <path d={`M${x + BOX_W},${STAGE_Y + BOX_H / 2} H${x + BOX_W + GAP - 8}`}
                  stroke={step > i ? '#2a2e86' : '#cbd5e1'} strokeWidth={2.5}
                  markerEnd={step > i ? 'url(#ah8n)' : 'url(#ah8g)'}
                  fill="none" />
              )}
              {/* CDC bridge annotation */}
              {i === 3 && (
                <>
                  <rect x={x + BOX_W + 5} y={STAGE_Y + BOX_H / 2 - 28} width={GAP - 10} height={56}
                    fill="none" stroke="#f59e0b" strokeWidth={1.5} strokeDasharray="5 4" rx={5} />
                  <text x={x + BOX_W + GAP / 2} y={STAGE_Y + BOX_H / 2 - 36} textAnchor="middle"
                    style={{ font: '700 11px var(--mono)', fill: '#f59e0b' }}>ASYNC FIFO</text>
                  <text x={x + BOX_W + GAP / 2} y={STAGE_Y + BOX_H / 2 + 44} textAnchor="middle"
                    style={{ font: '600 11px var(--mono)', fill: '#f59e0b' }}>50→100 MHz CDC</text>
                </>
              )}
            </g>
          )
        })}

        {/* Animated data tokens */}
        <circle r={9} fill="#2a2e86" filter="url(#glow8)">
          <animateMotion dur="2.6s" begin="0s" repeatCount="indefinite" path={tokenPath} />
        </circle>
        <circle r={7} fill="#2a2e86" opacity={0.55}>
          <animateMotion dur="2.6s" begin="0.85s" repeatCount="indefinite" path={tokenPath} />
        </circle>
        <circle r={5} fill="#2a2e86" opacity={0.3}>
          <animateMotion dur="2.6s" begin="1.7s" repeatCount="indefinite" path={tokenPath} />
        </circle>

        {/* === Byte field breakdown (below ITCH decoder) === */}
        {(() => {
          const byY = STAGE_Y + BOX_H + 46
          const byBaseX = stageX(3) - 60
          const byTotalW = 560
          const fw = (byTotalW - (BYTE_FIELDS.length - 1) * 2) / BYTE_FIELDS.length
          return (
            <g>
              <text x={byBaseX} y={byY - 12} style={{ font: '600 12px var(--mono)', fill: '#5b21b6', textTransform: 'uppercase', letterSpacing: '0.1em' }}>
                Add Order 'A' — Byte Fields:
              </text>
              {BYTE_FIELDS.map((f, i) => (
                <g key={f.label}>
                  <rect x={byBaseX + i * (fw + 2)} y={byY} width={fw} height={54} fill={f.bg} stroke={f.col} strokeWidth={1.5} rx={3} />
                  <text x={byBaseX + i * (fw + 2) + fw / 2} y={byY + 15} textAnchor="middle"
                    style={{ font: '700 10px var(--mono)', fill: f.col }}>{f.label}</text>
                  <text x={byBaseX + i * (fw + 2) + fw / 2} y={byY + 29} textAnchor="middle"
                    style={{ font: '400 9px var(--mono)', fill: '#64748b' }}>{f.bytes}</text>
                  <text x={byBaseX + i * (fw + 2) + fw / 2} y={byY + 46} textAnchor="middle"
                    style={{ font: '600 10px var(--font)', fill: f.col }}>{f.example}</text>
                </g>
              ))}
              {/* Arrow from ITCH box to byte fields */}
              <line x1={stageX(3) + BOX_W / 2} y1={STAGE_Y + BOX_H} x2={stageX(3) + BOX_W / 2} y2={byY - 2}
                stroke="#c4b5fd" strokeWidth={1.5} strokeDasharray="4 3" markerEnd="url(#ah8g)" />
            </g>
          )
        })()}

        {/* === 256-bit event output (bottom) === */}
        {(() => {
          const evtY = STAGE_Y + BOX_H + 160
          const evtBaseX = 10
          let curX = evtBaseX
          return (
            <g>
              <text x={evtBaseX} y={evtY - 12} style={{ font: '600 12px var(--mono)', fill: '#2a2e86', textTransform: 'uppercase', letterSpacing: '0.1em' }}>
                256-bit Canonical Event (output of itch_decoder.sv):
              </text>
              {EVT_FIELDS.map((f) => {
                const el = (
                  <g key={f.bits}>
                    <rect x={curX} y={evtY} width={f.w} height={58} fill={`${f.col}22`} stroke={f.col} strokeWidth={1.5} rx={3} />
                    <text x={curX + f.w / 2} y={evtY + 17} textAnchor="middle"
                      style={{ font: '700 10px var(--mono)', fill: f.col }}>{f.bits}</text>
                    <text x={curX + f.w / 2} y={evtY + 35} textAnchor="middle"
                      style={{ font: '600 11px var(--font)', fill: f.col }}>{f.label}</text>
                  </g>
                )
                curX += f.w + 2
                return el
              })}
              {/* Remaining bits */}
              <rect x={curX} y={evtY} width={Math.max(1728 - curX - 20, 0)} height={58} fill="#f8fafc" stroke="#e2e8f0" strokeWidth={1} rx={3} />
              <text x={curX + 60} y={evtY + 32} textAnchor="middle"
                style={{ font: '400 11px var(--mono)', fill: '#94a3b8' }}>[reserved/zero]</text>
              {/* Arrow from canonical event stage to output */}
              <path d={`M${stageX(4) + BOX_W / 2},${STAGE_Y + BOX_H} V${evtY - 10}`}
                stroke="#2a2e86" strokeWidth={1.5} strokeDasharray="5 4" markerEnd="url(#ah8n)" fill="none" />
            </g>
          )
        })()}
      </svg>

      {/* Play/Pause toggle */}
      <button
        onClick={() => setPlaying(p => !p)}
        style={{
          position: 'absolute', right: 110, top: 195,
          font: '700 13px var(--mono)', background: playing ? 'var(--navy)' : 'white',
          color: playing ? 'white' : 'var(--navy)', border: '2px solid var(--navy)',
          padding: '6px 18px', borderRadius: 20, cursor: 'pointer', letterSpacing: '0.06em',
        }}
      >
        {playing ? '⏸ PAUSE' : '▶ PLAY'}
      </button>

      {/* Stage callout footer */}
      <div style={{ position: 'absolute', left: 96, bottom: 52, font: '500 20px var(--font)', color: '#4a4e57' }}>
        <span style={{ fontFamily: 'var(--mono)', fontWeight: 700, color: STAGES[step].text }}>
          [{String(step + 1)}/{STAGES.length}]
        </span>{' '}
        Active:{' '}<strong>{STAGES[step].label}</strong>{' — '}{STAGES[step].sub}
      </div>
    </Frame>
  )
}
