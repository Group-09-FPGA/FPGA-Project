import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import JourneyPage from './JourneyPage.tsx'

const isSlides = new URLSearchParams(window.location.search).has('slides')
document.documentElement.setAttribute('data-mode', isSlides ? 'slides' : 'journey')

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {isSlides ? <App /> : <JourneyPage />}
  </StrictMode>,
)
