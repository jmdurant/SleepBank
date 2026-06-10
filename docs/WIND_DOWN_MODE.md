# Wind-Down Mode — blocking distracting apps in the evening

> **Status: code shipped, inert until the entitlement is granted.** The
> implementation is in `App/iOS/WindDownShieldService.swift` + the "Block
> distracting apps" card in `WindDownView`. It compiles and ships safely today, but
> does nothing until Apple grants the **Family Controls entitlement** (below).

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
  **Start wind-down**, `WindDownShieldService.shield()` sets
  `ManagedSettingsStore.shield.applications`; **Stop** clears it. The shield is
  applied app-side while authorized — no `DeviceActivityMonitor` extension required.
- Authorization via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
  Without the entitlement this fails gracefully → `isAuthorized = false` → the card
  shows a setup hint and shielding is a no-op. **The rest of the app is unaffected.**

## To turn it on (two steps — both yours)

1. **Request the entitlement from Apple** (Account holder):
   developer.apple.com → Certificates, IDs & Profiles → Identifiers → the
   `com.doctordurant.sleepbank` App ID → enable **Family Controls (Distribution)**,
   and submit the **Family Controls request form**. Wait for approval.
2. **Add the entitlement to the build** — in `project.yml`, under the `SleepBank`
   target's `entitlements: properties:` (next to the HealthKit / App Group keys):

   ```yaml
       entitlements:
         properties:
           com.apple.developer.family-controls: true
   ```

   then `xcodegen generate`. **Don't add this before approval** — a signed build will
   fail to provision until Apple grants it (which is why it's left out for now, so
   you can keep installing other builds).

## Future (Phase B): fully-automatic nightly shielding

The manual shield covers "block while I wind down." To shield **automatically every
evening** (even if the app isn't open), add a **`DeviceActivityMonitor` extension**
target with a `DeviceActivitySchedule` for the evening window: `intervalDidStart`
applies the shield, `intervalDidEnd` clears it. That's a separate target (its own
provisioning + the same entitlement) and is deferred until the entitlement lands and
the manual flow is validated on-device. A `DeviceActivityMonitor` threshold event
(*"30 min of social this evening"*) could also fire a nudge — you get the *event*,
never the raw minutes.
