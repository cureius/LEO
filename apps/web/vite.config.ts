/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'
import { devClaudeProxyPlugin } from './devProxyPlugin.js'
import { devGoogleOAuthProxyPlugin } from './devGoogleOAuthProxyPlugin.js'
import { devJiraProxyPlugin } from './devJiraProxyPlugin.js'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss(), devClaudeProxyPlugin(), devGoogleOAuthProxyPlugin(), devJiraProxyPlugin()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
})
