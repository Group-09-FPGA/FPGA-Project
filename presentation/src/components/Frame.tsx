import type { ReactNode } from 'react'
import { delay } from './util'

export const TOTAL = 7

interface FrameProps {
  n: number
  kicker: string
  title: string
  children: ReactNode
}

export function Frame({ n, kicker, title, children }: FrameProps) {
  return (
    <section className="slide">
      <div className="kicker rise">{kicker}</div>
      <h1 className="title rise" style={delay(0.08)}>{title}</h1>
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
