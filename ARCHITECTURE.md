# SleepBank — Architecture

SleepBank began as a power-nap app and grew into a **daytime alertness manager**:
take short naps when a full night isn't possible and wake at the right moment (in
light sleep, before deep-sleep grogginess) via a smart, onset-relative alarm — and,
around that, help you *plan* a day that makes the most of imperfect sleep. The heart
of it is an **interactive alertness curve**: last night's sleep (scored to match
Apple's) sets the day's ceiling, and you drag **naps, walks, and workouts** onto the
curve to see — and schedule — how they lift you back toward a rested day, with an
end-of-day recap of how much of that gap you filled. iOS app + companion watchOS app,
optional paired sensors (Muse EEG, Polar H10), and HomeKit/calendar integrations.

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
  Alertness:   AlertnessRhythm (two-process curve; stacks naps + walk/workout activity)
               SleepScore (reverse-engineered to Apple watchOS 26.2) · AlertnessCharge
               DayPlan (the day's agenda) · Daylight · CircadianLighting + Solar
               Streaks · Intervals

App/
  Shared/      SharedStore (App Group) · RhythmSnapshot · PlanSummary · WindDownShield
               NoiseService · GuidedRelaxationService · MotionService
               NapHealthWriter · NapSessionRecorder · NapChart · NapFiles · …
  iOS/         SleepBankApp · ContentView (5-tab: Home/Today/Nap/History/Settings)
               SettingsView · HealthKitService · AlertnessProvider
               EnergyRingView (battery + plan/scrub preview) · AlertnessCurveView (planner)
               AlertnessRecapView (gap-recovery analysis) · AlertnessDetailView
               PlanPreview · DayPlanView · DaylightView · WindDownView
               SleepScore wiring: BedtimeHistoryStore · ManualSleepStore · SleepBasis
               LocationService (sunset via Solar) · AppearanceMode
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
  day. Last night's sleep sets the curve height; **naps** discharge pressure (a
  smooth impulse: fast subjective + slow homeostatic component, so a deep/late nap
  lingers and can steal tonight's sleep); **activities** (walk/workout) add a modest
  acute-arousal bump; morning light/movement add small capped lifts. It stacks any
  number of naps + activities (`level(at:naps:activities:)`, `planReadings`).
  `AlertnessProvider` assembles the *actual* rhythm from HealthKit + nap history;
  `RhythmSnapshot` (App Group) shares it with the widgets and the watch.
- **`SleepScore`** — reverse-engineered to Apple's **watchOS 26.2** Sleep Score
  (Duration 50 + Bedtime Consistency 30 + Interruptions 20): an absolute 7h50m
  duration curve + low-Deep/REM penalty, efficiency-based interruptions, and a
  consistency factor that grades schedule *regularity*. `BedtimeHistoryStore`
  backfills the last 14 HealthKit nights so consistency works on day one;
  `ManualSleepStore` + `SleepBasis` cover Oura/manual/no-watch users. The score sets
  the curve's start-of-day pressure (validated 5h50m → Apple 71 / ours 72).
- **The interactive planner (`AlertnessCurveView`)** — the product's centrepiece.
  Drag **naps / walks / workouts** onto the curve (a list of plan items, any number
  of each); each shows a duration band and a draggable marker, snaps clear of the
  others, and stacks into one combined "your plan" curve. Late/intense additions turn
  orange (a deep late nap or bright-evening outdoor bout would cost tonight's sleep —
  the bright-light caution is gated on real local sunset via `LocationService`/`Solar`).
  The **+** schedules each to Today's Plan + a reminder; the home **battery
  (`EnergyRingView`/`PlanPreview`)** previews the plan's peak and "charges" as you
  drag. With no plan, the curve becomes a **scrubber** — drag the dot to read the
  Alert Score at any time of day.
- **The recap (`AlertnessRecapView`, Today tab)** — draws the gap a short night opens
  between your curve and a rested one, fills green what your logged + scheduled
  naps/light/movement recovered, and quantifies it ("recovered X% of what your short
  night cost"). Forward-looking by day, retrospective by evening.
- **`AlertnessCharge`** — the energy-ring "nap charge" that fills on waking and
  fades over the benefit window.
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
HomeKit, Family Controls, calendar, and **Core Location** (coarse, for local sunset)
need a real device; simulators compile and exercise the UI, and `SleepBankCore` is
fully unit-tested without hardware.

> **Charts gotcha:** multiple `AreaMark` groups in one `Chart` must each carry a
> distinct `series:` value, or Swift Charts welds them into one self-intersecting
> polygon (stray "shards"). The curve and recap fills tag every area as its own series.

> **Always `xcodegen generate` after adding files** — XcodeGen builds a static file
> list at generation time, so new files are excluded from the build until you
> regenerate.

## Provenance

The sensor/watch/EEG infrastructure was harvested and adapted from a separate app
(SexKit) — kept as a distinct repo/app, not a dependency. Swift 5 language mode for
now; a deliberate Swift 6 concurrency migration is a future step.
