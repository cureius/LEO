import { GlobalWorkerOptions } from 'pdfjs-dist'
// Vite needs the worker as a real asset URL, not pdfjs-dist's own internal
// resolution (which assumes a Node or classic-script host) — this is the one
// place that config happens, imported once before any getDocument() call.
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'

GlobalWorkerOptions.workerSrc = pdfWorkerUrl

export * from 'pdfjs-dist'
