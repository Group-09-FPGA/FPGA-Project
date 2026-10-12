import type { ReactNode } from 'react'
import { delay } from './util'

export const TOTAL = 7

interface FrameProps {
  n: number
  kicker: string
  title: string
  children: ReactNode
  compactHeader?: boolean
}

export function Frame({ n, kicker, title, children, compactHeader }: FrameProps) {
  return (
    <section className={`slide${compactHeader ? ' compact' : ''}`}>
      <div className={`kicker rise${compactHeader ? ' compact' : ''}`}>{kicker}</div>
      <h1 className={`title rise${compactHeader ? ' compact' : ''}`} style={delay(0.08)}>{title}</h1>
      {children}
      <div className="foot">
        <span>{String(n).padStart(3, '0')} · GROUP 09 · FPGA LOB</span>
        <span className="dots">
          {Array.from({ length: TOTAL }, (_, i) => (
            <i key={i} className={`dot${i + 1 === n ? ' on' : ''}`} />
          ))}
        </span>
      </div>
    </section>
  )
}
