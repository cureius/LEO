import type { AlarmSound } from '@/domain/types'

/**
 * 2-3 simple synthesized cues via Web Audio, not a port of each native sound
 * file — deliberately small per the plan (no bundled audio assets needed
 * for v1). `haptic_only` plays nothing, matching Swift's own early-return
 * for that sound profile (there's no haptic API for a browser tab).
 */
let audioCtx: AudioContext | null = null
let activeOscillators: OscillatorNode[] = []

function getContext(): AudioContext {
  if (!audioCtx) audioCtx = new AudioContext()
  return audioCtx
}

export function playAlarmSound(sound: AlarmSound) {
  if (sound === 'haptic_only') return
  const ctx = getContext()
  const frequency = sound === 'alarm_gentle' ? 440 : sound === 'alarm_urgent' ? 880 : 660
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()
  osc.frequency.value = frequency
  osc.type = sound === 'alarm_gentle' ? 'sine' : 'square'
  gain.gain.value = 0.15
  osc.connect(gain)
  gain.connect(ctx.destination)
  osc.start()
  osc.stop(ctx.currentTime + 1.5)
  activeOscillators.push(osc)
}

export function stopAllAlarmSounds() {
  for (const osc of activeOscillators) {
    try {
      osc.stop()
    } catch {
      // already stopped — fine to ignore
    }
  }
  activeOscillators = []
}
