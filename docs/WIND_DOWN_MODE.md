# Wind-Down Mode — blocking distracting apps in the evening

> **Status: built, and enabled for DEVELOPMENT builds.** The implementation is in
> `App/iOS/WindDownShieldService.swift` + the "Block distracting apps" card in
> `WindDownView`. The `com.apple.developer.family-controls` entitlement is in
> `project.yml` — it **auto-provisions for development** (your own device, dev
> signing) with no approval, so you can test the shield now. **Only a
> TestFlight/App Store build** needs Apple's gated Family Controls request (below).

## Why this and not screen-time tracking

iOS does **not** let a normal third-party app *measure* Screen Time. Confirmed by a
shipping developer's account (Medium, @nikkieke001, *"What no one tells you about
building with Apple's Screen Time API"*):

- Usage data lives only inside a sandboxed `DeviceActivityReport` extension —
  *"if you attempt to extract the usage data to your main app, it returns absolutely
  nothing."* The extension sandbox is read-only; writes *"fail silently."*
- The **Family Controls entitlement is gated** — the Account holder requests it;
  review *"any time from a few days to over three weeks and in bad cases a few
  months."*
- Apps are identified by **opaque tokens** the OS *"sometimes silently changes."*

So we don't measure — **we enforce.** The Screen Time API is built for restriction,
and that fits wind-down better than tracking ever would: instead of charting your
evening scrolling, we **block the apps that keep you up.**

## How our implementation works

- **Manual shield (no monitor extension needed).** The user picks apps/categories
  via `FamilyActivityPicker` (stored as a `FamilyActivitySelection`). When they tap
  **Start wind-down**, `WindDownShieldService.shield()` applies the shield; **Stop**
  clears it. Applied app-side while authorized — no `DeviceActivityMonitor` extension.
- **Two modes:**
  - **Block these** (blocklist) — shields the chosen apps:
    `store.shield.applications = tokens`.
  - **Bare Necessities** (allowlist) — shields **everything except** the chosen apps:
    `store.shield.applicationCategories = .all(except: tokens)`. The stronger mode —
    you don't have to enumerate every distraction.

### Bare Necessities gotchas (important)

- **You can't hardcode "Phone / Messages / Clock / FaceTime / SleepBank" by name.**
  iOS only exposes apps as **opaque `ApplicationToken`s** obtained by the user
  picking them in `FamilyActivityPicker` — there's no by-bundle-ID lookup. Those
  system apps *do* appear in the picker and are selectable as exceptions, so the
  user chooses their necessities once (persisted).
- **Always include SleepBank in the allowlist** — otherwise the app that turns
  wind-down *off* would itself be shielded. (Emergency calling stays available
  regardless, and alarms fire even if Clock is shielded.)
- The strict block-all is best paired with the **Phase-B schedule** (auto-lift in
  the morning) so you never depend on reopening a shielded app.
- Authorization via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
  Without the entitlement this fails gracefully → `isAuthorized = false` → the card
  shows a setup hint and shielding is a no-op. **The rest of the app is unaffected.**

## Two tiers — development works now, distribution needs the form

The entitlement key is the same; the *signing tier* differs:

- **Development (now):** the entitlement is in `project.yml`, so a dev-signed build
  on your own device **provisions it automatically** — no form, no approval. Run it,
  grant Screen Time permission when prompted, pick apps, and the shield works.
  - *Caveat:* if automatic provisioning ever errors on Family Controls, enable the
    capability once on the `com.doctordurant.sleepbank` App ID at developer.apple.com
    (no review) — but dev signing usually registers it for you.
- **Distribution (later, before TestFlight/App Store):** request **Family Controls
  (Distribution)** for the App ID at developer.apple.com and submit the **Family
  Controls request form**. Review can take days to months. The same entitlement key
  then ships in the distribution build.

## Future (Phase B): fully-automatic nightly shielding

The manual shield covers "block while I wind down." To shield **automatically every
evening** (even if the app isn't open), add a **`DeviceActivityMonitor` extension**
target with a `DeviceActivitySchedule` for the evening window: `intervalDidStart`
applies the shield, `intervalDidEnd` clears it. That's a separate target (its own
provisioning + the same entitlement) and is deferred until the entitlement lands and
the manual flow is validated on-device. A `DeviceActivityMonitor` threshold event
(*"30 min of social this evening"*) could also fire a nudge — you get the *event*,
never the raw minutes.
