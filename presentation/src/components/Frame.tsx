import { createContext, useContext, type ReactNode } from 'react'
import { delay } from './util'

export const TOTAL = 12

export interface SlideContextValue {
  currentSlide: number
  goTo: (n: number) => void
}

export const SlideContext = createContext<SlideContextValue | null>(null)

interface FrameProps {
  n?: number
  kicker: string
  title: string
  children: ReactNode
  compactHeader?: boolean
}

export function Frame({ n, kicker, title, children, compactHeader }: FrameProps) {
  const ctx = useContext(SlideContext)
  const current = ctx?.currentSlide ?? n ?? 1

  return (
    <section className={`slide${compactHeader ? ' compact' : ''}`}>
      <div className={`kicker rise${compactHeader ? ' compact' : ''}`}>{kicker}</div>
      <h1 className={`title rise${compactHeader ? ' compact' : ''}`} style={delay(0.08)}>{title}</h1>
      {children}
      <div className="foot">
        <span>{String(current).padStart(3, '0')} · GROUP 09 · FPGA LOB · HISTORICAL DESIGN</span>
        <span className="dots">
          {Array.from({ length: TOTAL }, (_, i) => (
            <i
              key={i}
              className={`dot${i + 1 === current ? ' on' : ''}`}
              onClick={() => ctx?.goTo(i + 1)}
              style={{ cursor: ctx ? 'pointer' : 'default' }}
              title={`Slide ${i + 1}`}
            />
          ))}
        </span>
      </div>
    </section>
  )
}
