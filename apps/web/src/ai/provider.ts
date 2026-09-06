/** Which backend powers Ask LEO's replies — a persisted user choice, same
 *  pattern as router.ts's routing override. 'webllm' trades tool-calling and
 *  attachment support (see chatOrchestrator.ts) for running fully on-device
 *  and free, no API key. */
export type AIProvider = 'claude' | 'webllm'

const PROVIDER_STORAGE_KEY = 'leo_ai_provider'

export function getProvider(): AIProvider {
  const raw = localStorage.getItem(PROVIDER_STORAGE_KEY)
  return raw === 'webllm' ? 'webllm' : 'claude'
}

export function setProvider(provider: AIProvider): void {
  localStorage.setItem(PROVIDER_STORAGE_KEY, provider)
}

export function isWebGPUSupported(): boolean {
  return typeof navigator !== 'undefined' && 'gpu' in navigator
}
