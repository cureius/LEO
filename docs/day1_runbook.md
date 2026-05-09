# LEO v1.0 — Day-1 Launch Runbook

**Period:** First 72h post-approval (estimated Oct 2026)
**Owner:** @raj
**Hot-fix branch:** `hotfix/v1.0.1` (create from the release tag before launch)

---

## Monitoring cadence

| Time | Action |
|------|--------|
| Hour 0–2 | Monitor App Store Connect for crashes every 30 min |
| Hour 2–24 | Check every 2h; respond to reviews/feedback |
| Day 2–7 | 2h daily triage window |

---

## If X → Then Y

### Crash on first launch
- **Signal:** MetricKit crash payload, 1★ reviews mentioning crash on open, TestFlight crash logs
- **Response:**
  1. Reproduce locally immediately
  2. If reproducible: cherry-pick fix to `hotfix/v1.0.1`, submit expedited review
  3. Expedited review request template: `docs/templates/expedited_review_request.md`

### Critical alerts permission UI broken
- **Signal:** Users report no alarm sound with silent mode on
- **Response:**
  1. The alarm caveats are already in onboarding — verify onboarding copy is live
  2. If the UX is confusing, push copy change (no expedited needed if behavior is per-spec)
  3. If behavior is wrong: flag and fix

### CloudKit sync conflict
- **Signal:** Users report duplicated items, items disappearing, sync errors in Settings
- **Response:**
  1. Pause CloudKit sync via a remote config flag (not built in v1 — add to hotfix if needed)
  2. Surface a "Sync paused — tap to view" banner in Settings

### Paywall not loading products
- **Signal:** PaywallView shows empty products list; users can't subscribe
- **Response:**
  1. Verify App Store Connect products are in "Ready for Sale" state
  2. Check StoreKit logs: `product.products(for:)` should not be empty
  3. If StoreKit down: surface "Try again later" — don't hide the feature

### AI not responding
- **Signal:** "Ask LEO" spinner never completes; network errors
- **Response:**
  1. Check Anthropic status page
  2. If API down: show offline banner, route to on-device Haiku only
  3. If API key used up: prompt user to add their own key in Settings

---

## Expedited review checklist

Before submitting for expedited:
- [ ] Bug is reproducible on a fresh device install
- [ ] Fix is minimal and scoped (no new features)
- [ ] Build number incremented
- [ ] TestFlight tested on at least 2 devices
- [ ] Review notes updated with fix description and reproduction steps

---

## Hot-fix branch setup

```bash
git tag v1.0.0
git checkout -b hotfix/v1.0.1
```

After fix:
```bash
git tag v1.0.1
# Increment CURRENT_PROJECT_VERSION in project.yml
# Run Archive + Upload from Xcode
```
