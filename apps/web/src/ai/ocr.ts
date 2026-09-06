import { createWorker, type Worker } from 'tesseract.js'

/**
 * On-device OCR for the web app's camera/photo attachment — the browser
 * equivalent of LEO/AI/Vision/VisionOCRService.swift's Apple Vision usage.
 * Browsers have no built-in OCR API, so this uses tesseract.js (WASM,
 * runs entirely in a Web Worker, no network round-trip for the actual
 * recognition).
 *
 * The worker script + WASM core are self-hosted (public/tesseract/) rather
 * than left on tesseract.js's default jsdelivr CDN — the whole point of
 * doing OCR on-device is "no round-trip," and a CDN dependency for the
 * engine itself would silently break that (or the feature entirely) on a
 * CDN outage with no visible error surface. The English language model
 * (~10MB+) is NOT bundled here — it's fetched once from tesseract.js's own
 * CDN and cached in IndexedDB (via its bundled idb-keyval dependency) on
 * first use, same tradeoff most web apps make for large model assets rather
 * than bloating every page load with a file most sessions won't need.
 */
const WORKER_PATH = '/tesseract/worker.min.js'
const CORE_PATH = '/tesseract/tesseract-core-lstm.wasm.js'

// Tesseract's LSTM engine is trained overwhelmingly on printed/typed text —
// unlike Apple's Vision framework, it does NOT reliably return empty output
// on handwriting it can't actually read; it tends to produce plausible-
// looking WRONG text instead. An emptiness-only check (matching Vision's
// behavior) would silently ship garbage OCR to Claude instead of falling
// back to sending the photo. Gating on Tesseract's own per-recognition
// confidence score (0-100) catches that case; text is only trusted above
// this threshold.
const OCR_CONFIDENCE_THRESHOLD = 60

let workerPromise: Promise<Worker> | null = null

// Lazy singleton, created once and kept alive for the browser session — NOT
// recreated per photo. tesseract.js's one-shot `Tesseract.recognize()` API
// creates and terminates a fresh worker per call, paying the ~1-2s WASM +
// language-data initialization cost every single time; reusing one worker
// avoids that for a chat session where several photos might be attached.
function getWorker(): Promise<Worker> {
  if (!workerPromise) {
    workerPromise = createWorker('eng', undefined, {
      workerPath: WORKER_PATH,
      corePath: CORE_PATH,
    })
  }
  return workerPromise
}

/**
 * Returns the extracted text, or `null` if OCR found nothing reliably
 * readable (caller should fall back to sending the raw image to Claude
 * Vision instead — mirrors VisionOCRService.recognizeText's `nil` return).
 */
export async function recognizeText(base64: string, mimeType: string): Promise<string | null> {
  const worker = await getWorker()
  const dataUrl = `data:${mimeType};base64,${base64}`
  const { data } = await worker.recognize(dataUrl)
  const text = data.text.trim()
  if (!text || data.confidence < OCR_CONFIDENCE_THRESHOLD) return null
  return text
}
