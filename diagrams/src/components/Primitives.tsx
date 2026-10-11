import type { CSSProperties } from 'react'

/* ─── Global SVG Definitions (Arrowheads, Halos) ─────────────────────────── */
export function DiagramDefs() {
  return (
    <defs>
      <marker id="arr-ink" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto">
        <path d="M0,1 L8,4.5 L0,8 z" fill="#16181d" />
      </marker>
      <marker id="arr-navy" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto">
        <path d="M0,1 L8,4.5 L0,8 z" fill="#2a2e86" />
      </marker>
      <marker id="arr-warn" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto">
        <path d="M0,1 L8,4.5 L0,8 z" fill="#b4451f" />
      </marker>
      <marker id="arr-ok" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto">
        <path d="M0,1 L8,4.5 L0,8 z" fill="#1f7a4d" />
      </marker>
    </defs>
  )
}

/* ─── Hardware Module Box ────────────────────────────────────────────────── */
export interface ModuleBoxProps {
  x: number
  y: number
  w: number
  h: number
  title: string
  subtitle?: string
  detail?: string
  isNew?: boolean
  tag?: string
  style?: CSSProperties
}

export function ModuleBox({ x, y, w, h, title, subtitle, detail, isNew, tag, style }: ModuleBoxProps) {
  const stroke = isNew ? 'var(--navy)' : '#4a4e57'
  const strokeWidth = isNew ? 2.4 : 1.5
  const fill = isNew ? '#e4e6f8' : 'rgba(255, 255, 255, 0.88)'
  const textColor = isNew ? '#101234' : 'var(--ink)'
  const cy = y + h / 2

  const hasSub = Boolean(subtitle)
  const hasDetail = Boolean(detail)

  let titleY = cy + 6
  if (hasSub && hasDetail) {
    titleY = cy - 14
  } else if (hasSub) {
    titleY = cy - 6
  }

  return (
    <g style={style}>
      <rect
        x={x}
        y={y}
        width={w}
        height={h}
        rx={4}
        fill={fill}
        stroke={stroke}
        strokeWidth={strokeWidth}
      />
      {tag && (
        <g>
          <rect
            x={x + w - tag.length * 8 - 14}
            y={y + 4}
            width={tag.length * 8 + 10}
            height={16}
            rx={2}
            fill={isNew ? 'var(--navy)' : '#8b8f98'}
          />
          <text
            x={x + w - (tag.length * 8 + 10) / 2 - 9}
            y={y + 16}
            textAnchor="middle"
            style={{ font: '700 10px var(--mono)', fill: '#ffffff', letterSpacing: '.06em' }}
          >
            {tag}
          </text>
        </g>
      )}
      <text
        x={x + w / 2}
        y={titleY}
        textAnchor="middle"
        style={{
          font: isNew ? '600 19px var(--font)' : '600 18px var(--font)',
          fill: textColor,
          letterSpacing: '-.01em',
        }}
      >
        {title}
      </text>
      {subtitle && (
        <text
          x={x + w / 2}
          y={titleY + 22}
          textAnchor="middle"
          style={{ font: '500 13px var(--mono)', fill: 'var(--ink-2)' }}
        >
          {subtitle}
        </text>
      )}
      {detail && (
        <text
          x={x + w / 2}
          y={titleY + 40}
          textAnchor="middle"
          style={{ font: '400 12px var(--mono)', fill: '#6e727e' }}
        >
          {detail}
        </text>
      )}
    </g>
  )
}

/* ─── Pipeline Register Divider (IF/ID, ID/EX, EX/WB) ───────────────────── */
export function PipelineReg({
  x,
  y,
  w = 28,
  h,
  label,
  sub,
}: {
  x: number
  y: number
  w?: number
  h: number
  label: string
  sub?: string
}) {
  return (
    <g>
      {/* Background shadow bar */}
      <rect x={x} y={y} width={w} height={h} rx={3} fill="#16181d" stroke="#2a2e86" strokeWidth={1.5} />
      {/* Vertical text label */}
      <text
        x={x + w / 2}
        y={y + h / 2}
        textAnchor="middle"
        dominantBaseline="middle"
        transform={`rotate(-90, ${x + w / 2}, ${y + h / 2})`}
        style={{ font: '700 15px var(--mono)', fill: '#ffffff', letterSpacing: '.14em' }}
      >
        {label}
      </text>
      {sub && (
        <text
          x={x + w / 2}
          y={y - 8}
          textAnchor="middle"
          style={{ font: '600 11px var(--mono)', fill: 'var(--navy)' }}
        >
          {sub}
        </text>
      )}
    </g>
  )
}

/* ─── MUX (Trapezoid) ─────────────────────────────────────────────────────── */
export function Mux2to1({
  x,
  y,
  w = 26,
  h = 56,
  label = 'MUX',
  selLabel,
}: {
  x: number
  y: number
  w?: number
  h?: number
  label?: string
  selLabel?: string
}) {
  const points = `${x},${y} ${x + w},${y + 12} ${x + w},${y + h - 12} ${x},${y + h}`
  return (
    <g>
      <polygon points={points} fill="#ffffff" stroke="#16181d" strokeWidth={1.6} />
      <text
        x={x + w / 2}
        y={y + h / 2 + 4}
        textAnchor="middle"
        style={{ font: '600 10px var(--mono)', fill: '#4a4e57' }}
      >
        {label}
      </text>
      {selLabel && (
        <text
          x={x + w / 2}
          y={y - 6}
          textAnchor="middle"
          className="halo-text"
          style={{ font: '500 11px var(--mono)', fill: 'var(--navy)' }}
        >
          {selLabel}
        </text>
      )}
    </g>
  )
}

/* ─── Group Container with Dashed Boundary ───────────────────────────────── */
export function SubsystemGroup({
  x,
  y,
  w,
  h,
  label,
  sub,
  isNew,
}: {
  x: number
  y: number
  w: number
  h: number
  label: string
  sub?: string
  isNew?: boolean
}) {
  const c = isNew ? 'var(--navy)' : '#8b8f98'
  return (
    <g>
      <rect
        x={x}
        y={y}
        width={w}
        height={h}
        rx={6}
        fill={isNew ? 'rgba(42, 46, 134, 0.02)' : 'none'}
        stroke={c}
        strokeWidth={1.5}
        strokeDasharray="9 7"
      />
      <rect x={x + 16} y={y - 12} width={label.length * 9.5 + 24} height={20} fill="var(--paper)" />
      <text
        x={x + 24}
        y={y + 3}
        style={{ font: '600 14px var(--mono)', fill: c, letterSpacing: '.08em', textTransform: 'uppercase' }}
      >
        {label}
      </text>
      {sub && (
        <text
          x={x + w - 16}
          y={y + 20}
          textAnchor="end"
          style={{ font: '500 12px var(--mono)', fill: 'var(--ink-3)' }}
        >
          {sub}
        </text>
      )}
    </g>
  )
}

/* ─── Signal Wire with Clean Path & Halo Label ──────────────────────────── */
export function SignalWire({
  d,
  color = 'ink',
  width = 2,
  label,
  lx,
  ly,
  widthTag,
  dashed,
  flowAnim,
}: {
  d: string
  color?: 'ink' | 'navy' | 'warn' | 'ok' | 'grey'
  width?: number
  label?: string
  lx?: number
  ly?: number
  widthTag?: string
  dashed?: boolean
  flowAnim?: boolean
}) {
  const strokeColor =
    color === 'navy'
      ? 'var(--navy)'
      : color === 'warn'
        ? 'var(--warn)'
        : color === 'ok'
          ? 'var(--ok)'
          : color === 'grey'
            ? '#8b8f98'
            : '#16181d'

  const markerId =
    color === 'navy'
      ? 'url(#arr-navy)'
      : color === 'warn'
        ? 'url(#arr-warn)'
        : color === 'ok'
          ? 'url(#arr-ok)'
          : 'url(#arr-ink)'

  return (
    <g>
      <path
        d={d}
        fill="none"
        stroke={strokeColor}
        strokeWidth={width}
        strokeDasharray={dashed ? '6 4' : undefined}
        markerEnd={markerId}
        className={flowAnim ? 'flowline' : undefined}
      />
      {label && lx !== undefined && ly !== undefined && (
        <text
          x={lx}
          y={ly}
          textAnchor="middle"
          className="halo-text"
          style={{
            font: '600 12px var(--mono)',
            fill: strokeColor,
            letterSpacing: '.02em',
          }}
        >
          {label}
          {widthTag && <tspan style={{ font: '400 10px var(--mono)', fill: '#6e727e' }}> {widthTag}</tspan>}
        </text>
      )}
    </g>
  )
}

/* ─── Bus Backbone (Heavy bar) ───────────────────────────────────────────── */
export function HeavyBus({
  x1,
  y1,
  x2,
  y2,
  label,
  width = 6,
}: {
  x1: number
  y1: number
  x2: number
  y2: number
  label?: string
  width?: number
}) {
  return (
    <g>
      <line x1={x1} y1={y1} x2={x2} y2={y2} stroke="var(--ink)" strokeWidth={width} strokeLinecap="round" />
      {label && (
        <text
          x={x1 + 16}
          y={y1 - 10}
          className="halo-text"
          style={{ font: '700 14px var(--mono)', fill: 'var(--ink)', letterSpacing: '.08em' }}
        >
          {label}
        </text>
      )}
    </g>
  )
}
