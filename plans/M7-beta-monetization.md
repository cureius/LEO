# M7 — Beta & Monetization

**Goal of this milestone:** TestFlight beta with paying trialists. StoreKit 2 paywall live. Crash + non-fatal monitoring in place.

**Target ship:** 2026-09-17 (2 weeks).

**Read before starting:** [`PRD.md`](../PRD.md) §7.8.

**Prerequisites:** M6 complete.

---

## Task summary

- [ ] M7-T01 — StoreKit 2 products + paywall UI
- [ ] M7-T02 — Pro gating wiring
- [ ] M7-T03 — Trial + family sharing
- [ ] M7-T04 — TestFlight beta launch (≤ 500 testers)
- [ ] M7-T05 — In-app feedback channel
- [ ] M7-T06 — Crash + non-fatal monitoring polish

---

### M7-T01 — StoreKit 2 products + paywall UI
- **Status:** TODO
- **Depends on:** M6 complete
- **Estimated effort:** L

**Goal**
A real paywall, products configured, purchase + restore flows.

**What to build (acceptance criteria)**
- Products in App Store Connect (placeholder IDs `leo.pro.monthly`, `leo.pro.yearly`).
- `Features/Paywall/Views/PaywallView.swift`:
  - Hero with positioning line.
  - Feature list (alarms, AI unlimited, habits, weekly review, widgets+, Watch).
  - Two SKUs: monthly $9.99, yearly $79.99 (badge: "Save 33%").
  - "Start 7-day free trial" CTA → StoreKit purchase.
  - Restore link.
  - Privacy + Terms links (URLs to be hosted; placeholder for now, real in M8).
- `Monetization/StoreClient.swift` actor wrapping StoreKit 2:
  - `func products() async throws -> [Product]`
  - `func purchase(_ product: Product) async throws -> PurchaseResult`
  - `func restore() async throws`
  - `var entitlement: AsyncStream<Entitlement>` — stream of current entitlement state.
- Persist entitlement in Keychain (cached) plus authoritative check via `Transaction.currentEntitlements` on launch.

**How to build it**
1. StoreKit Configuration File for local testing (`LEO.storekit`).
2. Test all flows in StoreKit Configuration mode before submitting to App Store Connect.
3. Don't roll your own receipt validation — `Transaction.verificationResult` is the canonical path.

**Verification**
- [ ] Local StoreKit: monthly/yearly purchase succeed; cancel works; restore works.
- [ ] Entitlement state survives relaunch and observes deep changes.

---

### M7-T02 — Pro gating wiring
- **Status:** TODO
- **Depends on:** M7-T01
- **Estimated effort:** M

**Goal**
Free tier users hit clear, friendly walls at the right moments.

**What to build (acceptance criteria)**
- Free tier features (per PRD §7.8): unlimited capture, today/week, basic recurring (no LEO extensions), system reminders, EventKit sync, 5 AI prompts/week.
- Pro features: real alarms, habits, weekly review, advanced recurring (LEO extensions), widgets (lock-screen widgets stay free; Habit ring is Pro), Live Activities, Watch app, unlimited AI.
- Gates implemented as a `ProGate` modifier with consistent UI ("This requires LEO Pro" with a "Try free for 7 days" button).
- Track gate hits via local analytics (no third-party) for funnel analysis.

**How to build it**
1. `@Environment(\.entitlement)` exposed across the app.
2. Centralize gate decisions in `ProGate.requires(_ feature: ProFeature, in entitlement: Entitlement) -> Bool`.
3. Don't gate behind dialogs the user can tap-around. The wall is the wall.

**Verification**
- [ ] Free user attempting a Pro feature sees the gate.
- [ ] Pro user has full access; downgrading (e.g., trial expiry) re-applies gates immediately.

---

### M7-T03 — Trial + family sharing
- **Status:** TODO
- **Depends on:** M7-T02
- **Estimated effort:** S

**Goal**
7-day free trial; iCloud Family Sharing enabled.

**What to build (acceptance criteria)**
- Subscription products configured with introductory offer = 7-day free trial.
- Family Sharing toggled ON in App Store Connect for both products.
- Eligibility check: `Product.SubscriptionInfo.IntroductoryOffer.eligibility`.
- Show "Trial ends in N days" in Settings during trial.

**How to build it**
1. Configure in App Store Connect.
2. Local StoreKit configuration mirrors offer for testing.
3. Family-shared purchases: handle additional user identifiers in `Transaction` payload.

**Verification**
- [ ] First-time purchaser sees 7-day trial CTA.
- [ ] Family member can use Pro without re-purchasing.
- [ ] "Trial ends" copy shows correct day count.

---

### M7-T04 — TestFlight beta launch
- **Status:** TODO
- **Depends on:** M7-T01, M7-T02, M7-T03
- **Estimated effort:** M

**Goal**
Up to 500 testers using LEO daily.

**What to build (acceptance criteria)**
- App Store Connect: TestFlight enabled, public link generated.
- Test groups: "Friends & family" (50 max), "Public" (450 max).
- Build uploaded with proper version + build numbers; signed; notes per release.
- Beta signup landing page (one-pager hosted somewhere — GitHub Pages or `leo.app/beta` if domain owned).
- A short beta tester guide in-app accessible from Settings → "Beta info".

**How to build it**
1. Increment build number on every TestFlight upload. Version stays `1.0.0` until launch.
2. Don't use TestFlight notes for marketing; use them for "what to try this week".
3. **STOP AND ASK** before submitting build for TestFlight external review (Apple reviews public TestFlight builds).

**Verification**
- [ ] Beta link works and adds testers.
- [ ] Test build runnable end-to-end on a fresh device.
- [ ] First 30 daily users active by week 2 (PRD success metric tracked manually for now).

---

### M7-T05 — In-app feedback channel
- **Status:** TODO
- **Depends on:** M7-T04
- **Estimated effort:** S

**Goal**
Testers can report bugs and feature requests in two taps.

**What to build (acceptance criteria)**
- Settings → "Send feedback" opens a form: type (bug / idea / praise), description, optional email.
- Pre-fills diagnostic info: app version, build, iOS version, device model, last 50 log lines (filtered for PII).
- Sends via `MFMailComposeViewController` to `feedback@leo.app` (placeholder; user provides real address).
- Crash reports auto-attached when present (MetricKit payloads serialized).

**How to build it**
1. Use Mail compose; fall back to a `mailto:` URL if Mail isn't configured.
2. PII filter: redact emails, addresses, phone numbers in logs before attaching.
3. Don't build a custom feedback backend — Mail is sufficient at this scale.

**Verification**
- [ ] Form opens, fills correctly.
- [ ] Sent email arrives with diagnostics.
- [ ] PII redaction confirmed on a synthetic log.

---

### M7-T06 — Crash + non-fatal monitoring polish
- **Status:** TODO
- **Depends on:** M7-T04
- **Estimated effort:** S

**Goal**
We see crashes and non-fatals from beta in time to fix before launch.

**What to build (acceptance criteria)**
- MetricKit payloads (from M0-T08) get persisted across launches and shown on a debug Settings page.
- Build a daily summary: crashes, hangs, signpost exceedances. Surface in TestFlight tester guide.
- For non-fatal logs of interest (sync failures, AI errors, alarm failures), log via `os.Logger` with category. Sample one per day per category to MetricKit's customMetric where possible.

**How to build it**
1. MetricKit only fires once per day with bundled payloads. Build a parser that extracts `MXCrashDiagnostic`, `MXHangDiagnostic`, etc.
2. Persist in a local rolling table; the user can view and email.

**Verification**
- [ ] Inducing a crash on debug → next launch sees the payload.
- [ ] Hangs > 250ms surface in the daily summary.

---

## Exit criteria for M7

- [ ] All six tasks `DONE`.
- [ ] 100+ beta users; 30+ active daily by week 2.
- [ ] ≥ 5 trial-to-paid conversions.
- [ ] Top 10 reported bugs triaged; P0/P1s fixed.
- [ ] App Privacy nutrition label drafted.
- [ ] App Store metadata complete.
- [ ] User signs off in chat.
