# AirPods Pro 3 Heart Rate as a SleepBank Nap Sensor — Access-Path Notes

> **Why this matters.** Nap users already wear earbuds for our wind-down audio
> (noise + guided TTS). AirPods Pro 3 are the first AirPods with a heart-rate
> sensor, so they could be a **fourth sensor rung** (watch → H10 → Muse → AirPods)
> that needs **zero extra hardware** — the earbuds are both the audio *output* and
> the HR *input*. This note records how third-party live HR access actually works,
> from a research pass (2026-06-09), and the open questions to confirm with the
> AirPulse developer before we wire it in.

## What AirPods Pro 3 HR is

- In-ear **infrared PPG** sensors (pulse light ~250×/sec), with motion-rejection
  algorithms. Apple's AirPods Pro 3 (Sept 2025).
- **iPhone-only capable** — no Apple Watch required.
- **Does NOT broadcast a standard Bluetooth HR (GATT) profile.** So it can't be
  paired as a generic BLE HR strap (this is why Garmin/Zwift/Peloton-hardware and
  Android can't see it). Access is **Apple-mediated**, not raw BLE.

## How third-party apps get it (best current understanding)

- HR is **workout-context-gated**: it streams while an **active workout session**
  is running. Apps like Strava, Nike Run Club, Peloton, Runna, Ladder get **live**
  AirPods HR during a workout (Strava shows it live on the recording screen, saves
  to Health on end).
- The enabling API is **iOS workout sessions** — `HKWorkoutSession` +
  `HKLiveWorkoutBuilder` / `HKLiveWorkoutDataSource`, **new to iPhone in iOS 26
  (WWDC25 session 322)**; previously workout sessions were watchOS-only. The OS
  "automatically handles getting heart rate data from paired external devices" and
  delivers it via the `workoutBuilder(_:didCollectDataOf:)` callback.
- **Ambiguity to confirm:** WWDC25 322 explicitly lists **Powerbeats Pro 2** and
  generic BLE-GATT monitors as iOS HR sources but **did not name AirPods Pro 3**.
  Since third-party fitness apps demonstrably *do* get AirPods HR live, the most
  likely path is that the OS routes in-ear AirPods Pro 3 HR into the active iOS
  workout session automatically (no public BLE, possibly no special entitlement) —
  but the exact mechanism/entitlement is **the thing to verify with the dev**.

```swift
// The likely shape (iOS 26+), to be confirmed:
let config = HKWorkoutConfiguration()
config.activityType = .mindAndBody        // a quiet, non-exertion type for a nap
let session = try HKWorkoutSession(healthStore: store, configuration: config)
let builder = session.associatedWorkoutBuilder()
builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
builder.delegate = self
// AirPods Pro 3 in-ear → HR arrives in workoutBuilder(_:didCollectDataOf:) as .heartRate
```

## What it means for SleepBank

- **A nap is not a workout**, so to keep AirPods HR streaming we'd run a **quiet
  `HKWorkoutSession` on the phone during the nap** — exactly the pattern we already
  use on the **watch** for sensor keepalive. The "workout" is just the mechanism
  that activates continuous HR sensing.
- It fuses straight into the existing `HeartRateImmobilityOnsetDetector`
  (HR-drop + immobility). AirPods also have motion sensors → potential **head-
  stillness** immobility signal via `CMHeadphoneMotionManager`.
- Could give a **phone-only, anywhere nap** real onset detection with no watch and
  no chest strap — just the earbuds already in for the audio.

## Open questions for the AirPulse developer (Christian Range)

1. **Exact access path:** is live AirPods Pro 3 HR just `HKWorkoutSession` +
   `HKLiveWorkoutDataSource` on iOS 26 with the OS auto-providing AirPods HR, or is
   there a dedicated API / entitlement / extra step?
2. **HR at rest:** does it report reliable HR while **lying still / nearly
   motionless** (we need to catch the small HR *drop* at sleep onset), or is it
   tuned for/only reliable during exercise?
3. **Update cadence & latency:** how often does HR update (per-second? every 5 s?)
   — anything ≤5 s works for onset detection.
4. **Audio coexistence (unique to us):** does HR sensing work while the AirPods are
   **actively playing audio** (our noise + TTS wind-down)? Any conflict?
5. **Workout housekeeping:** does the session create a Fitness/Health **workout
   entry** / affect activity rings, and can that be suppressed or made unobtrusive
   for a nap?
6. **Battery** over a 20–90 min session.

## Status

Research done; **not yet wired**. Next step is the developer confirmation above,
then add an `AirPodsHRService` feeding `OnsetSignal.heartRate` (and optionally
head-stillness into `movementIntensity`) in `PhoneNapController`, alongside the
H10/Muse sources.

## Sources

- DCRainmaker, AirPods Pro 3 sports/fitness review (Sept 2025) — IR sensor, no BLE-GATT broadcast, iPhone-only, workout-gated. https://www.dcrainmaker.com/2025/09/airpods-pro-3-in-depth-sports-fitness-review.html
- WWDC25 session 322, *Track workouts with HealthKit on iOS and iPadOS* — iOS workout sessions + live HR API. https://developer.apple.com/videos/play/wwdc2025/322/
- Strava live AirPods Pro 3 HR support. https://apple.gadgethacks.com/news/strava-adds-airpods-pro-3-support-for-live-heart-rate-on-iphone/
- Apple Support, *Track your heart rate during workouts with AirPods Pro 3*. https://support.apple.com/guide/airpods/track-heart-rate-workouts-airpods-pro-3-dev1b40fb47d/web
- HKLiveWorkoutBuilder. https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder
- AirPulse (Christian Range) — App Store. https://apps.apple.com/es/app/airpulse/id6760625679
