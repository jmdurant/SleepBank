# SleepBank — Architecture

SleepBank began as a power-nap app and grew into a **daytime alertness manager**:
take short naps when a full night isn't possible and wake at the right moment (in
light sleep, before deep-sleep grogginess) via a smart, onset-relative alarm — and,
around that, help you *time* rest and light through the day (the alertness curve,
the day's plan, morning light, wind-down). iOS app + companion watchOS app, optional
paired sensors (Muse EEG, Polar H10), and HomeKit/calendar integrations.

## Two layers

1. **The nap loop** — sense → decide → wake → record. The original product core.
2. **The alertness / response layer** — model the day's alertness, turn it into an
   actionable plan, and act on the environment (light, screens). The "respond to
   readiness, make the day happen" idea.

Both rest on **`SleepBankCore`**, a pure-Foundation, device-free, unit-tested
library (the parts where correctness matters live here behind protocols).

## Layout

```
Package.swift                 SwiftPM libraries:
  SleepChartKit               · sleep-stage charts (pre-existing)
  SleepBankCore               · domain logic (pure, unit-tested)

project.yml                   XcodeGen source of truth → SleepBank.xcodeproj
                              (.xcodeproj git-ignored; run `xcodegen generate`)

Sources/SleepBankCore/
  Nap loop:    NapType · NapPhase · OnsetSignal · NapEngine · NapRecord · NapBank
               HeartRateImmobilityOnsetDetector · DeepeningDetector · AwakeningDetector
               SleepOnsetDetector (protocol) · NapTrace
  Alertness:   AlertnessRhythm (two-process curve) · AlertnessCharge (nap "charge")
               DayPlan (the day's agenda) · Daylight · CircadianLighting + Solar
               Streaks · Intervals

App/
  Shared/      SharedStore (App Group) · RhythmSnapshot · PlanSummary · WindDownShield
               NoiseService · GuidedRelaxationService · MotionService
               NapHealthWriter · NapSessionRecorder · NapChart · NapFiles · …
  iOS/         SleepBankApp · ContentView · SettingsView · HealthKitService
               AlertnessProvider · EnergyRingView · AlertnessCurveView · AlertnessDetailView
               DayPlanView · DaylightView · WindDownView
               PlanNotificationService · CalendarService · NapWindowsStore
               WindDownShieldService · HomeLightingService
               AlertnessIntent · SleepBankPhoneShortcuts
               Muse/ · Sensors/ · Sounds/ · Nap/ · Validation/ · Live/
  Watch/       SleepBankWatchApp (WatchRootView) · NapSessionView · NapController
               WatchConnectivityService · WatchDayPlanView · WatchDaylightView
               SmartAlarmService · NapWorkoutService · NapStore · NapIntents · …
  Widget/      AlertnessWidget · SleepBankHomeWidget · NapLiveActivityView (iOS)
  WatchWidget/ SleepBankComplication (Naps · MorningLight · Plan complications)
  DeviceMonitor/ WindDownMonitor (DeviceActivityMonitor extension)
```

## The nap loop (where the product started)

1. **Sense (watch).** `NapWorkoutService` runs an `HKWorkoutSession` to keep sensors
   alive and stream live HR; `MotionService` tracks movement + stillness.
2. **Decide (core).** `NapController` feeds a fused `OnsetSignal` into `NapEngine`
   each second. `HeartRateImmobilityOnsetDetector` declares onset on HR-drop **and**
   immobility (fused with HRV/breathing/EEG when present); `DeepeningDetector` catches
   the approach to deep sleep; `AwakeningDetector` catches a spontaneous wake.
   `NapEngine` arms the wake at `onset + target`, capped by a session ceiling.
3. **Wake (watch).** `SmartAlarmService` schedules a `WKExtendedRuntimeSession` and
   escalates haptics → audio.
4. **Record.** `NapStore` saves a `NapRecord`; `NapBank` totals the sleep given back —
   a plain **descriptive** tally (no deposit formulas; naps restore alertness, they
   don't repay debt).

## The alertness / response layer

- **`AlertnessRhythm`** — a two-process model (circadian − sleep pressure) for the
  day. Last night's sleep sets the curve height; naps discharge pressure; morning
  light (cortisol pathway) and morning movement (exercise zeitgeber) add small,
  capped lifts. `AlertnessProvider` assembles it from HealthKit + nap history;
  `RhythmSnapshot` (App Group) shares it with the widgets and the watch.
- **`AlertnessCharge`** — the energy-ring "nap charge" that fills on waking and
  fades over the benefit window (`EnergyRingView`).
- **`DayPlan`** — turns the rhythm into an agenda: morning light/movement, a nap
  *before* the predicted dip, wind-down. It avoids **calendar** conflicts
  (`CalendarService` → busy intervals) and respects user **"OK to nap" windows**
  (`NapWindowsStore` → `Intervals.subtract`). Surfaced in `DayPlanView`, the watch
  (`WatchDayPlanView` + Plan complication), a morning notification, and Siri.
- **Daylight** — Apple Watch Time-in-Daylight, sub-segmented by window
  (`Daylight`); a morning-light streak; `DaylightView`.
- **Wind-down** (`WindDownView`) — guided relaxation + sounds, a self-reported
  "screens off" streak, **app shielding** (`WindDownShieldService` /
  `WindDownShield` via FamilyControls + ManagedSettings; manual + a nightly
  `DeviceActivityMonitor` automation), and a **warm-lights-at-wind-down** HomeKit
  scene (`HomeLightingService`). `CircadianLighting`/`Solar` remain as tested
  utilities (the full all-day curve was trimmed — Adaptive Lighting owns that).

## Surfaces

Home/Lock-screen **widgets** (alertness %, naps), Apple Watch app + **complications**
(naps, morning-light streak, next plan action), **Siri/Shortcuts** ("How alert am
I?", start/stop nap), a nap **Live Activity**, **notifications** (morning plan,
evening wind-down — toggleable in Settings), and **deep links**
(`sleepbank://{plan,daylight,alertness,winddown,nap,settings}`).

## Evidence & feature docs

`RATIONALE.md` (clinical rationale + positioning) and the fact-checked evidence base:
`docs/NAP_BENEFIT_EVIDENCE.md`, `docs/DAYLIGHT_EVIDENCE.md`, `docs/EEG_EVIDENCE.md`,
`docs/AIRPODS_HR_SENSOR.md`, `docs/WIND_DOWN_MODE.md`.

## Build

```sh
xcodegen generate
swift test                                            # SleepBankCore + SleepChartKit
xcodebuild -project SleepBank.xcodeproj -scheme SleepBank \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

Targets: **SleepBank** (iOS), **SleepBankWatch** (watchOS), **SleepBankWidget**
(iOS widgets + Live Activity), **SleepBankWatchWidget** (complications),
**SleepBankDeviceMonitor** (Wind-Down auto-shield). iOS 17+. Live HR/motion/EEG,
HomeKit, Family Controls, and calendar need a real device; simulators compile and
exercise the UI, and `SleepBankCore` is fully unit-tested without hardware.

> **Always `xcodegen generate` after adding files** — XcodeGen builds a static file
> list at generation time, so new files are excluded from the build until you
> regenerate.

## Provenance

The sensor/watch/EEG infrastructure was harvested and adapted from a separate app
(SexKit) — kept as a distinct repo/app, not a dependency. Swift 5 language mode for
now; a deliberate Swift 6 concurrency migration is a future step.
