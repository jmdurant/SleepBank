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

## The meditation / mind-and-body angle (the clean way in)

Rather than fake a cardio "workout," frame the nap's **guided wind-down as a
mind-and-body / meditation session** — which is what it genuinely is (our
`GuidedRelaxationService` already runs 4-7-8 breathing + body relaxation; this is
NSDR / "non-sleep deep rest"). This is both honest and the technical key:

- **Meditation/yoga ARE workout activity types that stream AirPods HR.** Apple
  Fitness+ lists **Meditation** and **Yoga** as workout types, and connecting
  AirPods Pro 3 "adds heart rate" to them — so HR is **not** gated to cardio.
- **Precedent that de-risks it:** **"Rhythm • Heart Rate Meditation"** (App Store)
  reads **live AirPods Pro 3 HR during guided meditation** *and plays audio*
  (you hear your heartbeat). That strongly suggests the two earlier worries are
  fine: **HR works at near-rest**, and **HR sensing coexists with audio playback**.
- **Use the right HealthKit construct — and note the trap:**
  - **`HKWorkoutSession` with `activityType = .mindAndBody`** → IS a workout →
    **activates AirPods HR.** This is what we run during the nap.
  - **`mindfulSession` (Mindful Minutes)** is a *category sample*, **NOT** a workout
    → would **not** activate HR. We can *also* log a `mindfulSession` so the nap
    earns Mindful Minutes in Health (a nice feature), but it's not the HR trigger.

## What it means for SleepBank

- We run the nap as a **`.mindAndBody` `HKWorkoutSession` on the phone** — honest
  (a guided-relaxation nap really is a mind-and-body session), it **activates
  AirPods HR**, and it earns the user a gentle Health/Mindful-Minutes entry instead
  of a bogus "workout." Same session-keepalive pattern we already use on the
  **watch**; the session just needs to keep running as the user transitions from
  meditating → asleep.
- It fuses straight into the existing `HeartRateImmobilityOnsetDetector`
  (HR-drop + immobility). AirPods also have motion sensors → potential **head-
  stillness** immobility signal via `CMHeadphoneMotionManager`.
- Could give a **phone-only, anywhere nap** real onset detection with no watch and
  no chest strap — just the earbuds already in for the audio.

## Open questions for the AirPulse developer (Christian Range)

*(The Fitness+ Meditation/Yoga support and the Rhythm app largely answer #2 and #4
already — confirm rather than discover.)*

1. **Exact access path:** is live AirPods Pro 3 HR just `HKWorkoutSession` +
   `HKLiveWorkoutDataSource` on iOS 26 with the OS auto-providing AirPods HR, or is
   there a dedicated API / entitlement / extra step?
2. **`.mindAndBody` activates HR?** confirm a low-intensity mind-and-body/meditation
   workout type streams AirPods HR (Fitness+ Meditation suggests yes).
3. **HR once asleep:** does HR keep streaming after the user stops "meditating" and
   actually **falls asleep / goes fully still** — or does auto-pause / no-motion
   stop it? (We'd disable workout auto-pause.) Need the onset HR *drop*.
4. **Audio coexistence:** confirm HR sensing runs while AirPods play our noise + TTS
   (Rhythm plays audio, so likely yes).
5. **Update cadence & latency:** how often HR updates (≤5 s is fine for onset).
6. **Workout housekeeping:** does the `.mindAndBody` session create a Fitness/Health
   entry / affect rings, and is that acceptable/suppressible? (We may also log a
   `mindfulSession` for Mindful Minutes.)
7. **Battery** over a 20–90 min session.

## Status

Research done; **not yet wired**. Next step is the developer confirmation above,
then add an `AirPodsHRService` feeding `OnsetSignal.heartRate` (and optionally
head-stillness into `movementIntensity`) in `PhoneNapController`, alongside the
H10/Muse sources.

## Sources

- DCRainmaker, AirPods Pro 3 sports/fitness review (Sept 2025) — IR sensor, no BLE-GATT broadcast, iPhone-only, workout-gated. https://www.dcrainmaker.com/2025/09/airpods-pro-3-in-depth-sports-fitness-review.html
- WWDC25 session 322, *Track workouts with HealthKit on iOS and iPadOS* — iOS workout sessions + live HR API. https://developer.apple.com/videos/play/wwdc2025/322/
- Strava live AirPods Pro 3 HR support. https://apple.gadgethacks.com/news/strava-adds-airpods-pro-3-support-for-live-heart-rate-on-iphone/
- Apple Support, *Track your heart rate during workouts with AirPods Pro 3* — lists Fitness+ Meditation/Yoga as HR-tracked workout types. https://support.apple.com/guide/airpods/track-heart-rate-workouts-airpods-pro-3-dev1b40fb47d/web
- HKLiveWorkoutBuilder. https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder
- *Rhythm • Heart Rate Meditation* — third-party app reading live AirPods Pro 3 HR during guided meditation (precedent for at-rest HR + audio coexistence). https://apps.apple.com/us/app/rhythm-heart-rate-meditation/id6752779850
- AirPulse (Christian Range) — App Store. https://apps.apple.com/es/app/airpulse/id6760625679
