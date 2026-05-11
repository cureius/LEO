# M9 — App Store Launch

**Goal of this milestone:** v1.0 in the App Store, marketing site live, launch posts published. Runs after M8 (Gym Companion) so all v1.0 surfaces ship together.

**Target ship:** 2026-10-22 (2 weeks).

**Read before starting:** [`PRD.md`](../PRD.md), [`ROADMAP.md`](../ROADMAP.md) M9.

**Prerequisites:** M8 complete (Gym Companion). M7 beta stable. P0/P1 bugs resolved. Marketing copy, screenshots, and preview video updated to reflect Gym Companion.

---

## Task summary

- [ ] M9-T01 — App Store Connect submission package
- [ ] M9-T02 — Marketing site (one page)
- [ ] M9-T03 — Privacy Policy + Terms
- [ ] M9-T04 — Launch posts
- [ ] M9-T05 — Day-1 monitoring + hot-fix readiness

---

### M9-T01 — App Store Connect submission package
- **Status:** TODO
- **Depends on:** M7 complete
- **Estimated effort:** M

**Goal**
A submission Apple approves.

**What to build (acceptance criteria)**
- App Store Connect record:
  - App name: `LEO` (or final naming user confirms; check trademark).
  - Subtitle: short positioning line.
  - Promotional text: 170 chars; can be updated without resubmit.
  - Description: long-form per copy guidelines; positioning + features grouped.
  - Keywords: 100 chars max; researched against ASO tools.
  - Screenshots: 6.7", 6.1" iPhone sets — use the M6 drafts polished.
  - App preview video: 15–30s, captured on device.
  - Category: Productivity (primary), Utilities (secondary).
  - Age rating: 4+ (no objectionable content).
  - Pricing: free with subscriptions.
  - Privacy: nutrition label finalized (M7-T06 inputs).
  - App Review notes: explain real-alarm audio behavior, AI features, demo account if requested.
- Build uploaded, Phased Release enabled.

**How to build it**
1. Don't submit on a Friday. Aim for Mon–Wed so review responses arrive within working hours.
2. **STOP AND ASK** before clicking "Submit for Review" — final user sign-off.
3. Have a contingency for rejection on the alarm feature (R1 from PRD) — a fallback build with the audio layer disabled.

**Verification**
- [ ] All metadata fields complete.
- [ ] Build accepted by App Store Connect's automated processing.
- [ ] Submitted for review.

---

### M9-T02 — Marketing site (one page)
- **Status:** TODO
- **Depends on:** M9-T01
- **Estimated effort:** M

**Goal**
A simple, fast page at `leo.app` (or chosen domain) that converts visitors to App Store downloads.

**What to build (acceptance criteria)**
- Single page, < 100KB shell, no third-party JS.
- Hero: positioning line + screenshot + App Store badge.
- 3-section feature breakdown (Unified, AI planner, Habits).
- Footer: Privacy, Terms, Support email.
- No analytics or tracker pixels in v1 (privacy positioning).
- Light + dark via prefers-color-scheme.

**How to build it**
1. Static HTML + CSS. No frameworks. Host on GitHub Pages or Netlify free tier.
2. Optimize images (`@1x/@2x`, WebP).
3. Robots + sitemap.

**Verification**
- [ ] Lighthouse perf ≥ 95 on mobile.
- [ ] App Store smart banner present.
- [ ] Renders cleanly at 320px width.

---

### M9-T03 — Privacy Policy + Terms
- **Status:** TODO
- **Depends on:** —
- **Estimated effort:** S

**Goal**
Real Privacy Policy + Terms hosted at stable URLs (referenced by App Store Connect and the in-app paywall).

**What to build (acceptance criteria)**
- Privacy Policy covers: data collected (none beyond device), data shared (none), AI processing (on-device by default, optional Claude API per user trigger), children's policy, contact.
- Terms covers: subscription terms, refunds (per Apple), acceptable use, governing law (user's call).
- Both hosted on the marketing site.
- Linked from in-app: paywall, settings, onboarding.

**How to build it**
1. Use plain language. Not a contract template the user can't read.
2. Run by user before publishing — non-trivial wording differs by jurisdiction.

**Verification**
- [ ] URLs reachable, indexable, dated.
- [ ] In-app links open these URLs.

---

### M9-T04 — Launch posts
- **Status:** TODO
- **Depends on:** M9-T01, M9-T02
- **Estimated effort:** M

**Goal**
Coordinated launch across the channels that matter.

**What to build (acceptance criteria)**
- Drafts ready a week ahead:
  - Product Hunt (post night before, schedule for 12:01am PT).
  - Hacker News "Show HN" post.
  - r/iOSProgramming, r/productivity (read each sub's rules — no spam tone).
  - X/Twitter: thread with screenshots + 30s video.
  - LinkedIn: founder post.
- Press list: MacStories, 9to5Mac, The Verge, Daring Fireball, Six Colors. Personalized email each, 3 days pre-launch with embargoed preview build via TestFlight.
- Day-of: monitor each channel, respond to questions within 1h during waking hours.

**How to build it**
1. Write each post in a launch doc (separate from this repo) so the agent isn't generating marketing copy.
2. Don't astroturf or buy traffic.
3. Track conversion with App Store Connect's source-link feature instead of UTM tracking.

**Verification**
- [ ] All posts queued and reviewed by user.
- [ ] Press emails sent.
- [ ] Day-1 monitoring schedule blocked on calendar.

---

### M9-T05 — Day-1 monitoring + hot-fix readiness
- **Status:** TODO
- **Depends on:** M9-T01
- **Estimated effort:** S

**Goal**
A clear plan for the first 72 hours post-launch: what to watch, when to ship a hot-fix.

**What to build (acceptance criteria)**
- Dashboard (in App Store Connect + a small custom Settings panel): installs, crashes, top reports.
- Hot-fix branch ready off the launch tag.
- A documented "if X then Y" matrix for common day-1 fires:
  - Crash on first launch → expedite review.
  - Critical alerts permission missing → in-app explainer + non-blocking fallback.
  - CloudKit schema conflict → pause sync banner + repair flow.
- A 2-hour daily window for the first 7 days to triage feedback.

**How to build it**
1. The matrix lives at `docs/day1_runbook.md` — yes a doc; user explicitly needs it.
2. Expedited review request templates pre-drafted.

**Verification**
- [ ] Runbook reviewed by user.
- [ ] Hot-fix branch created from the launch tag.

---

## Exit criteria for M9

- [ ] All five tasks `DONE`.
- [ ] LEO live on App Store.
- [ ] Marketing site live.
- [ ] 1,000 installs in first 7 days (per PRD success metric).
- [ ] No P0 bugs unaddressed > 24h.
- [ ] User signs off — v1.0 shipped.
