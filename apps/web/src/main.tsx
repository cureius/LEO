import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@/styles/globals.css'
import { applyTheme, getTheme } from '@/theme/theme'
import App from './App.tsx'

// Applied before the first render, not inside a component effect — an
// effect would paint the default (system) theme first and flip to the
// stored override a frame later, a visible flash on every load for anyone
// who picked Light/Dark against a system set the other way.
applyTheme(getTheme())

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
