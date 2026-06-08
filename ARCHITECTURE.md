# SleepBank — Architecture

SleepBank is a power-nap app: take short naps when a full night isn't possible,
and wake at the right moment (in light sleep, before deep-sleep grogginess) using
a smart, onset-relative alarm. iOS app + companion watchOS app, with optional
paired sensors (Muse EEG, Polar H10).

## Layout

```
Package.swift                 Two SwiftPM libraries:
  SleepChartKit               · sleep-stage charts (pre-existing)
  SleepBankCore               · sensor-agnostic nap domain (NEW, unit-tested)

project.yml                   XcodeGen source of truth → SleepBank.xcodeproj
                              (.xcodeproj is git-ignored; run `xcodegen generate`)

App/
  Shared/    HeartRateSample
  iOS/       SleepBankApp · ContentView · HealthKitService
    Muse/    MuseService · EEGSleepProcessor · MuseMonitorView
  Watch/     SleepBankWatchApp · NapSessionView · NapController
             NapWorkoutService · MotionService · SmartAlarmService · NapStore
```

## The nap loop (where the product lives)

1. **Sense (watch).** `NapWorkoutService` runs an `HKWorkoutSession` purely to keep
   sensors alive and stream live HR; `MotionService` tracks movement + stillness.
2. **Decide (SleepBankCore).** `NapController` feeds a fused `OnsetSignal` into
   `NapEngine` every second. `HeartRateImmobilityOnsetDetector` declares onset when
   HR has dropped below a personal quiet-wake baseline **and** the wrist has been
   still — requiring both raises specificity over actigraphy alone. `NapEngine`
   then arms the wake at `onset + target`, capped by an absolute session ceiling.
3. **Wake (watch).** `SmartAlarmService` schedules a `WKExtendedRuntimeSession` at
   the target and escalates haptics → stronger haptics → audio until cleared.
4. **Record.** `NapStore` saves a `NapRecord`; `NapBank` totals the sleep given
   back — a plain, descriptive "sleep bank" (no deposit formulas).

`SleepBankCore` is pure Foundation: deterministic, device-free, and unit-tested
(`Tests/SleepBankCoreTests`). The detector and alarm timing are the parts where
correctness matters, so they live there behind protocols.

## Nap types

- **Power** — wake ~18 min after onset (30 min ceiling); avoid slow-wave grogginess.
- **Cycle** — ride one ~90 min cycle (110 min ceiling).

## Sensor-fusion ladder

Watch HR + motion is the always-available baseline. `EEGSleepProcessor` (Muse,
phone-side) adds the gold-standard signal — alpha-attenuation/theta-emergence for
onset, rising delta for "wake now", spindle band for N2 — behind a signal-quality
gate. The watch stays self-sufficient; Muse enriches when present. The
`SleepOnsetDetector` protocol is the seam where an EEG detector plugs in later.

## Build

```sh
xcodegen generate
swift test                                            # SleepBankCore + SleepChartKit
xcodebuild -project SleepBank.xcodeproj -scheme SleepBank \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Live HR/motion/EEG need real devices; simulators compile and exercise the UI.

## Provenance

The sensor/watch/EEG infrastructure was harvested and adapted from a separate
app (SexKit) — kept as a distinct repo/app, not a dependency. Swift 5 language
mode for now; a deliberate Swift 6 concurrency migration is a future step.
