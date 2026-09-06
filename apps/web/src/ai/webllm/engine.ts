import { CreateMLCEngine, type MLCEngine } from '@mlc-ai/web-llm'

/**
 * Hermes-3-Llama-3.1-8B, 4-bit quantized (~4.9GB download / VRAM) — WebLLM's
 * `tools` support (see webllmClient.ts) only works with a small, named list
 * of models (`functionCallingModelIds`), all 8B-class; there's no smaller
 * function-calling-capable option to fall back to. This replaced an earlier
 * 3B conversation-only model — noticeably bigger download and slower
 * inference for everyone, in exchange for on-device mode actually being able
 * to read/propose changes like Claude mode does. requires ~5GB of GPU memory
 * available to WebGPU; devices without that will fail to load (surfaced as
 * an error on the chat message, not a crash).
 */
export const WEBLLM_MODEL_ID = 'Hermes-3-Llama-3.1-8B-q4f16_1-MLC'

export type EngineLoadProgress = { progress: number; text: string }

// The model downloads as several dozen separate shard files (weights split
// into chunks, tokenizer, wasm lib) — a single flaky request among that many
// (confirmed live: "Cache.add() encountered a network error" partway through
// a real load) previously killed the entire multi-GB download with no
// recovery but the user manually retrying. Retried attempts are usually much
// faster than the first: everything CreateMLCEngine already fetched
// successfully is sitting in the browser's Cache Storage, so only the shard
// that failed (and anything after it) actually re-downloads.
const MAX_LOAD_ATTEMPTS = 3
const RETRY_DELAY_MS = 1500

let enginePromise: Promise<MLCEngine> | null = null

async function loadEngineWithRetry(onProgress?: (report: EngineLoadProgress) => void): Promise<MLCEngine> {
  let lastErr: unknown
  for (let attempt = 1; attempt <= MAX_LOAD_ATTEMPTS; attempt++) {
    try {
      return await CreateMLCEngine(WEBLLM_MODEL_ID, {
        initProgressCallback: (report) => onProgress?.({ progress: report.progress, text: report.text }),
      })
    } catch (err) {
      lastErr = err
      if (attempt < MAX_LOAD_ATTEMPTS) {
        console.warn(`[webllm] load attempt ${attempt} failed, retrying:`, err)
        await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS))
      }
    }
  }
  throw lastErr
}

/** Lazily creates and caches the engine — reload() is expensive (downloads +
 *  compiles shaders), so every caller within a session shares one instance
 *  rather than re-triggering it. onProgress is only actually driven during
 *  the FIRST call's load; later callers that arrive after load has finished
 *  get their promise resolved immediately without ever invoking it. */
export function getEngine(onProgress?: (report: EngineLoadProgress) => void): Promise<MLCEngine> {
  if (!enginePromise) {
    enginePromise = loadEngineWithRetry(onProgress).catch((err) => {
      // A failed load must not permanently poison future attempts (e.g. the
      // user retries after enabling WebGPU or freeing memory) — without
      // resetting this, every subsequent getEngine() call would just
      // re-reject with the same cached failure forever.
      enginePromise = null
      throw err
    })
  }
  return enginePromise
}

export function isEngineLoaded(): boolean {
  return enginePromise !== null
}
