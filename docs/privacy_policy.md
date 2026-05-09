# LEO Privacy Policy

**Last updated:** 2026-10-01 (placeholder — update before publish)

## Summary

LEO is built privacy-first. In plain language:

- **We don't collect your data.** Your items, habits, and calendar data live on your device and iCloud — not our servers.
- **The AI is optional.** On-device AI uses Apple's Foundation Models and stays on your device. Cloud AI (Claude) is triggered only when you explicitly tap "Ask LEO" and requires you to add your own API key.
- **No tracking.** We don't use analytics SDKs, ad identifiers, or tracking pixels.

---

## What we collect

**Nothing we store on our servers.** All user data is stored:
- Locally on your device (SwiftData)
- In your private iCloud container (CloudKit private database)

Neither storage is accessible to us.

## iCloud sync

LEO uses Apple's CloudKit private database. Your data is encrypted and controlled by Apple under their privacy policy. We cannot access it.

## AI features

### On-device AI (Apple Foundation Models)
Uses Apple's on-device ML. Data never leaves your device.

### Cloud AI (Claude API — optional)
When you use "Ask LEO" with a Claude API key:
- A summary of relevant items (not your full history) is sent to Anthropic's API
- This is governed by Anthropic's API Privacy Policy
- You can see exactly what is sent via Settings → AI → Payload Inspector
- You can disable cloud AI entirely in Settings → AI → Allow cloud AI

## Data we do not collect

- ❌ Name, email address (unless you provide it in the feedback form)
- ❌ Device identifiers
- ❌ Crash data (MetricKit crash reports stay on-device and are only shared if you explicitly send feedback)
- ❌ Calendar content
- ❌ Location (only used locally for location-based reminders)

## Children

LEO is not directed to children under 13. We do not knowingly collect data from children.

## Contact

Questions: feedback@leo.app (placeholder — provide real address before launch)

---

*This policy is subject to final legal review before App Store submission.*
