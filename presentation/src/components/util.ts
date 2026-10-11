import type { CSSProperties } from 'react'

export const delay = (s: number) => ({ ['--d' as string]: `${s}s` }) as CSSProperties
