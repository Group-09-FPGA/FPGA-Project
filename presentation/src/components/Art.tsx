import type { CSSProperties, ReactElement } from 'react'

import { delay as d } from './util'

/** Isometric IC package, drawn in line-art style. Origin is the centre of the top face. */
export function Chip({ style, label = 'LOB' }: { style?: CSSProperties; label?: string }) {
  const A = [-220, 0], B = [0, -110], C = [220, 0], D = [0, 110]
  const t = 34
  const pts = (p: number[][]) => p.map((q) => q.join(',')).join(' ')
  const pins: ReactElement[] = []
  for (let i = 0; i < 9; i++) {
    const f = (i + 0.5) / 9
    const lx = A[0] + (D[0] - A[0]) * f, ly = A[1] + (D[1] - A[1]) * f
    const rx = D[0] + (C[0] - D[0]) * f, ry = D[1] + (C[1] - D[1]) * f
    pins.push(
      <polyline key={`l${i}`} className="draw" pathLength={1} style={d(1 + i * 0.05)} points={`${lx},${ly + t} ${lx - 6},${ly + t + 22}`} />,
      <polyline key={`r${i}`} className="draw" pathLength={1} style={d(1 + i * 0.05)} points={`${rx},${ry + t} ${rx + 6},${ry + t + 22}`} />,
    )
  }
  const inner = (k: number) => pts([[A[0] * k, 0], [0, B[1] * k], [C[0] * k, 0], [0, D[1] * k]])
  return (
    <svg className="art" width="560" height="420" viewBox="-280 -150 560 420" style={style}>
      <polygon className="draw" pathLength={1} points={pts([A, B, C, D])} />
      <polygon className="draw" pathLength={1} style={d(0.3)} points={pts([A, D, [D[0], D[1] + t], [A[0], A[1] + t]])} />
      <polygon className="draw" pathLength={1} style={d(0.5)} points={pts([D, C, [C[0], C[1] + t], [D[0], D[1] + t]])} />
      <polygon className="draw" pathLength={1} style={d(0.9)} points={inner(0.62)} />
      <polygon className="hidden" points={inner(0.38)} />
      <polyline className="hidden" points={`${B[0]},${B[1]} ${B[0]},${B[1] + t} ${A[0]},${A[1] + t}`} />
      <polyline className="hidden" points={`${B[0]},${B[1] + t} ${C[0]},${C[1] + t}`} />
      {pins}
      <circle className="draw" pathLength={1} style={d(1.2)} cx={-150} cy={0} r={7} />
      <g transform="matrix(0.894,-0.447,0.894,0.447,0,0)">
        <text x={0} y={10} textAnchor="middle" style={{ fontSize: 30, fill: '#16181d', fontWeight: 600, letterSpacing: 4 }}>{label}</text>
      </g>
    </svg>
  )
}

/** Long diagonal construction line, as in the reference template. */
export function Diagonal({ x1, y1, x2, y2 }: { x1: number; y1: number; x2: number; y2: number }) {
  return (
    <svg className="art" style={{ left: 0, top: 0 }} width="1920" height="1052" viewBox="0 0 1920 1052">
      <line className="draw" pathLength={1} style={d(0.2)} x1={x1} y1={y1} x2={x2} y2={y2} />
    </svg>
  )
}

export function Gear({ cx, cy, r = 70, teeth = 14, style }: { cx: number; cy: number; r?: number; teeth?: number; style?: CSSProperties }) {
  const pts: string[] = []
  const n = teeth * 4
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2
    const rr = i % 4 < 2 ? r : r * 1.18
    pts.push(`${(Math.cos(a) * rr).toFixed(1)},${(Math.sin(a) * rr).toFixed(1)}`)
  }
  return (
    <svg className="art" width={r * 3} height={r * 3} viewBox={`${-r * 1.5} ${-r * 1.5} ${r * 3} ${r * 3}`} style={{ left: cx - r * 1.5, top: cy - r * 1.5, ...style }}>
      <g className="spin">
        <polygon className="draw" pathLength={1} points={pts.join(' ')} />
        <circle className="draw" pathLength={1} style={d(0.4)} r={r * 0.55} />
        <circle className="draw" pathLength={1} style={d(0.6)} r={r * 0.22} />
        <line className="thin" x1={-r * 1.3} y1={0} x2={r * 1.3} y2={0} />
        <line className="thin" x1={0} y1={-r * 1.3} x2={0} y2={r * 1.3} />
      </g>
    </svg>
  )
}

/** Hex nut, tiny corner ornament. */
export function Nut({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  const hex = (r: number) => Array.from({ length: 6 }, (_, i) => {
    const a = (Math.PI / 3) * i + Math.PI / 6
    return `${(Math.cos(a) * r).toFixed(1)},${(Math.sin(a) * r).toFixed(1)}`
  }).join(' ')
  return (
    <svg className="art" width={90 * s} height={90 * s} viewBox="-45 -45 90 90" style={{ left: x, top: y }}>
      <polygon className="draw" pathLength={1} points={hex(38)} />
      <polygon className="draw" pathLength={1} style={d(0.3)} points={hex(30)} />
      <circle className="draw" pathLength={1} style={d(0.5)} r={16} />
    </svg>
  )
}
