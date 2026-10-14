import type { ReactNode } from 'react'
import { Frame } from '../components/Frame'
import { delay } from '../components/util'

// ── reuse the same mini-components as Slide 2 ──────────────────────────────
interface BoxProps { x: number; y: number; w: number; h: number; t: string; s?: string; isNew?: boolean; d?: number }
function Box({ x, y, w, h, t, s, isNew, d = 0 }: BoxProps) {
  const stroke = isNew ? 'var(--navy)' : '#8b8f98'
  const cy = y + h / 2
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h}
        fill={isNew ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
        stroke={stroke} strokeWidth={isNew ? 2.6 : 1.6} />
      <text x={x + w / 2} y={s ? cy - 4 : cy + 8} textAnchor="middle"
        style={{ font: '600 25px var(--font)', fill: isNew ? '#101234' : 'var(--ink-2)' }}>{t}</text>
      {s && <text x={x + w / 2} y={cy + 26} textAnchor="middle"
        style={{ font: '400 20px var(--font)', fill: 'var(--ink-2)' }}>{s}</text>}
    </g>
  )
}

function Group({ x, y, w, h, label, isNew, d = 0 }: { x: number; y: number; w: number; h: number; label: string; isNew?: boolean; d?: number }) {
  const c = isNew ? 'var(--navy)' : '#8b8f98'
  return (
    <g className="rise" style={delay(d)}>
      <rect x={x} y={y} width={w} height={h} fill="none" stroke={c} strokeWidth={1.5} strokeDasharray="9 7" />
      {label && <text x={x + 14} y={y - 12} style={{ font: '600 20px var(--mono)', fill: c, letterSpacing: '.08em' }}>{label}</text>}
    </g>
  )
}

function Arrow({ d, isNew }: { d: string; isNew?: boolean }) {
  const c = isNew ? 'var(--navy)' : '#6b6f78'
  return <path d={d} fill="none" stroke={c} strokeWidth={2.4} markerEnd={`url(#aho8${isNew ? 'n' : 'g'})`} />
}

function Note({ label, children, d }: { label: string; children: ReactNode; d: number }) {
  return (
    <div className="rise" style={delay(d)}>
      <div className="label">{label}</div>
      <p style={{ font: '400 25px/1.3 var(--font)', marginTop: 4 }}>{children}</p>
    </div>
  )
}

// Byte field data
const BYTE_FIELDS = [
  { label: "Type 'A'", bytes: '[0]',     w: 80 },
  { label: 'Locate',   bytes: '[1-2]',   w: 96 },
  { label: 'Track#',   bytes: '[3-4]',   w: 96 },
  { label: 'Timestamp (48-bit ns)', bytes: '[5-10]', w: 220 },
  { label: 'Order ID (OID)',         bytes: '[11-18]', w: 200 },
  { label: 'Shares',  bytes: '[19-22]',  w: 120 },
  { label: 'Side',    bytes: '[23]',     w: 80 },
  { label: 'Price',   bytes: '[24-27]',  w: 120 },
]

const EVT_FIELDS = [
  { label: 'VER', bits: '[255:252]', w: 70 },
  { label: 'OP=ADD', bits: '[251:248]', w: 88 },
  { label: 'SIDE', bits: '[247]', w: 60 },
  { label: '—', bits: '[246:240]', w: 70 },
  { label: 'OID  (64 b)', bits: '[239:176]', w: 200 },
  { label: 'NEW_OID (64 b)', bits: '[175:112]', w: 200 },
  { label: '—', bits: '[111:96]', w: 70 },
  { label: 'QTY (32 b)', bits: '[95:64]', w: 160 },
  { label: '—', bits: '[63:45]', w: 70 },
  { label: 'PIDX', bits: '[44:32]', w: 100 },
  { label: 'TIMESTAMP', bits: '[31:0]', w: 140 },
]

export default function Slide8() {
  return (
    <Frame n={3} kicker="ITCH 5.0 Protocol · Parsing Pipeline" title="Network ingestion: raw Ethernet → 256-bit event">
      <svg width={1728} height={660} viewBox="0 -20 1728 660" overflow="visible"
        style={{ position: 'absolute', left: 96, top: 205 }}>
        <defs>
          <marker id="aho8g" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#6b6f78" />
          </marker>
          <marker id="aho8n" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#2a2e86" />
          </marker>
        </defs>

        {/* ── Stage 1: Ethernet PHY layer (existing) ──────────────── */}
        <Group x={0} y={30} w={560} h={130} label="ETHERNET PHY · 50 MHz" d={0.1} />
        <Box x={24}  y={56} w={220} h={80} t="RMII RX"    s="2-bit dibits + CRC" d={0.15} />
        <Box x={304} y={56} w={220} h={80} t="Net parser" s="Eth · IPv4 · UDP:10443" d={0.2} />

        {/* ── Stage 2: MoldUDP64 (existing infrastructure) ───────── */}
        <Box x={640} y={56} w={240} h={80} t="MoldUDP64" s="session · seq# · frames" d={0.3} />

        {/* ── Stage 3: ITCH decoder (new) ─────────────────────────── */}
        <Box x={960} y={56} w={240} h={80} t="ITCH decoder" s="Type 'A' Add Order" isNew d={0.4} />

        {/* ── Stage 4: Canonical event (new) ──────────────────────── */}
        <Box x={1290} y={56} w={300} h={80} t="256-bit event" s="OP · OID · QTY · PIDX · TS" isNew d={0.5} />
        {/* CDC note */}
        <g className="rise" style={delay(0.5)}>
          <text x={1292} y={160} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.06em' }}>
            ASYNC FIFO · 50→100 MHz CDC
          </text>
        </g>

        {/* ── Arrows ──────────────────────────────────────────────── */}
        <Arrow d="M244,96 H302" />
        <Arrow d="M524,96 H638" />
        <Arrow d="M880,96 H958" />
        <Arrow isNew d="M1200,96 H1288" />
        <Arrow isNew d="M1590,96 H1660" />

        {/* ── Animated token ──────────────────────────────────────── */}
        {[168, 432, 712, 1040, 1370].map((x, i) => (
          <circle key={x} r={7} cy={96} fill={i >= 3 ? 'var(--navy)' : 'var(--ink-2)'}>
            <animate attributeName="cx" from={x} to={x + 60} dur="1.3s" begin={`${1.4 + i * 0.26}s`} repeatCount="indefinite" />
          </circle>
        ))}

        {/* ── Byte field breakdown ─────────────────────────────────── */}
        <g className="rise" style={delay(0.65)}>
          <text x={0} y={218} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            TYPE 'A' ADD ORDER — BYTE LAYOUT
          </text>
          {(() => {
            let cx = 0
            return BYTE_FIELDS.map((f) => {
              const el = (
                <g key={f.label}>
                  <rect x={cx} y={228} width={f.w - 2} height={54}
                    fill="rgba(255,255,255,.7)" stroke="var(--ink-2)" strokeWidth={1.2} />
                  <text x={cx + (f.w - 2) / 2} y={252} textAnchor="middle"
                    style={{ font: '600 15px var(--font)', fill: 'var(--ink)' }}>{f.label}</text>
                  <text x={cx + (f.w - 2) / 2} y={272} textAnchor="middle"
                    style={{ font: '500 13px var(--mono)', fill: 'var(--ink-3)' }}>{f.bytes}</text>
                </g>
              )
              cx += f.w
              return el
            })
          })()}
          {/* unused bytes indicator */}
          <rect x={1094} y={228} width={634} height={54} fill="rgba(255,255,255,.3)" stroke="#8b8f98" strokeWidth={1} strokeDasharray="5 4" />
          <text x={1411} y={258} textAnchor="middle"
            style={{ font: '500 14px var(--mono)', fill: 'var(--ink-3)' }}>stock symbol · other fields</text>
        </g>

        {/* ── 256-bit event output strip ───────────────────────────── */}
        <g className="rise" style={delay(0.8)}>
          <text x={0} y={330} style={{ font: '600 19px var(--mono)', fill: 'var(--navy)', letterSpacing: '.08em' }}>
            256-BIT CANONICAL EVENT (output of itch_decoder.sv)
          </text>
          {(() => {
            let cx = 0
            return EVT_FIELDS.map((f, i) => {
              const isKey = i === 1 || i === 4 || i === 7 || i === 9
              const el = (
                <g key={f.bits}>
                  <rect x={cx} y={340} width={f.w - 2} height={60}
                    fill={isKey ? '#e3e4f4' : 'rgba(255,255,255,.55)'}
                    stroke={isKey ? 'var(--navy)' : '#8b8f98'}
                    strokeWidth={isKey ? 2 : 1.2} />
                  <text x={cx + (f.w - 2) / 2} y={367} textAnchor="middle"
                    style={{ font: `${isKey ? '700' : '500'} ${isKey ? '16' : '14'}px var(--font)`, fill: isKey ? '#101234' : 'var(--ink-2)' }}>
                    {f.label}
                  </text>
                  <text x={cx + (f.w - 2) / 2} y={388} textAnchor="middle"
                    style={{ font: '500 12px var(--mono)', fill: 'var(--ink-3)' }}>
                    {f.bits}
                  </text>
                </g>
              )
              cx += f.w
              return el
            })
          })()}
        </g>
      </svg>

      {/* ── Bottom notes ─────────────────────────────────────────────── */}
      <div style={{ position: 'absolute', left: 96, right: 96, top: 890, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48 }}>
        <Note label="Protocol stack" d={1.0}>
          Preamble + SFD stripped by RMII RX. Eth/IPv4/UDP validated by net_parser. MoldUDP64 extracts ITCH frame boundaries.
        </Note>
        <Note label="Division-free pidx" d={1.1}>
          {'Price index = (price − base) × 274877907 >> 38. No divider needed in the 50 MHz domain.'}
        </Note>
        <Note label="Clock crossing" d={1.2}>
          Async FIFO bridges the 50 MHz Ethernet side to the 100 MHz LOB core. No packet loss on back-pressure.
        </Note>
      </div>
    </Frame>
  )
}
