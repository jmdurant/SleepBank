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

## How third-party apps get it — TWO paths, and the one that matters for us

There are two distinct ways to get AirPods Pro 3 HR, and the difference between
them is the whole ballgame for onset detection:

**(A) Passive / background → NOT continuous.** AirPods Pro 3 record HR passively
whenever they're in your ears ("on by default"), written automatically to
HealthKit (visible in the Health app). A third-party app reads it with ordinary
HealthKit queries (`HKObserverQuery` + `HKAnchoredObjectQuery`, background
delivery) — **no workout, no entitlement.** BUT the samples are **sparse/irregular**
(ambient sampling, not a steady stream), so this is **too coarse to catch the small
HR *drop* at sleep onset.** Onset detection needs a near-continuous trace.

**(B) Workout session → continuous.** During an active **iOS `HKWorkoutSession`**
(`HKLiveWorkoutBuilder` / `HKLiveWorkoutDataSource`, new to iPhone in iOS 26 /
WWDC25 322), AirPods HR streams continuously via `workoutBuilder(_:didCollectDataOf:)`.
Strava/Nike/Peloton use this. A `.mindAndBody` session (our meditation-framed nap,
below) is the honest way to trigger it. **This is the path our onset detection
needs.**

> **The crux — and the key question for the AirPulse dev.** AirPulse advertises
> "automatically records your heart rate **anytime** you put in your AirPods Pro 3"
> with a **live graph** — i.e. it appears to get a *continuous-ish* live stream
> **without** running a workout. That shouldn't be possible via path (A) alone
> (too sparse) and path (B) requires a workout. So **either** AirPulse's "live" is
> actually denser passive HealthKit delivery than we assume, **or** there's a
> non-workout continuous API we haven't found, **or** it quietly runs a lightweight
> session. **Resolving this is the entire value of the dev conversation** — if there
> is a no-workout continuous path, it's strictly better for a nap (no workout
> housekeeping); if not, we use a `.mindAndBody` session.
>
> WWDC25 322 listed **Powerbeats Pro 2** and BLE-GATT monitors as iOS HR sources
> but **did not name AirPods Pro 3** — so even path (B)'s exact mechanism for
> AirPods is unconfirmed in public docs.

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

**THE one that matters most:**

0. **Continuous without a workout?** AirPulse records HR "anytime you put in your
   AirPods" with a live graph. Is that a genuine **continuous** stream **without** an
   `HKWorkoutSession` — and if so, *how*? (denser passive HealthKit delivery via
   `HKObserverQuery`/`HKAnchoredObjectQuery`? a non-workout HR API? a hidden
   lightweight session?) Or is the "live" view actually sparse passive samples? This
   determines whether we can skip the workout entirely.

Then:

1. **Exact access path** if it *is* workout-based: just `HKWorkoutSession` +
   `HKLiveWorkoutDataSource` on iOS 26 with the OS auto-providing AirPods HR, or a
   dedicated API / entitlement / extra step?
2. **`.mindAndBody` activates HR?** does a low-intensity mind-and-body / meditation
   workout type stream AirPods HR (Fitness+ Meditation suggests yes)?
3. **HR once asleep / still:** does HR keep streaming after the user stops moving and
   falls asleep, or does auto-pause / no-motion stop it? (We need the onset HR *drop*
   from a near-motionless person.)
4. **Audio coexistence:** does HR sensing run while AirPods play our noise + TTS?
   (Rhythm plays audio, so likely yes.)
5. **Update cadence & latency:** how often does HR update? (≤5 s is fine for onset.)
6. **Workout housekeeping:** does a session create a Fitness/Health entry / affect
   rings, and is that suppressible? (We may also log a `mindfulSession` for Mindful
   Minutes.)
7. **Battery** over a 20–90 min session.

## Draft message to Christian

> Hey Christian — I'm the SleepBank beta tester; I'm building a power-nap app with a
> smart alarm that wakes you before deep sleep, and AirPods Pro 3 HR would be a
> perfect onset sensor since people already wear the buds for the wind-down audio.
>
> The thing I can't figure out from the docs: AirPulse seems to give a **continuous
> live** HR readout **without** running a workout. As far as I can tell, the passive
> HealthKit HR that AirPods write in the background is too sparse for that — so how
> are you getting a steady live stream? Is it (a) denser passive HealthKit delivery
> than I'd expect (observer/anchored queries + background delivery), (b) some
> non-workout HR API, or (c) a lightweight session under the hood?
>
> And a few specifics if you're up for it: does the HR keep updating when the person
> is **lying nearly still** (I need to catch the small HR dip at sleep onset)? Does
> sensing work **while audio is playing**? Roughly **how often** does it update? No
> worries if any of this is secret sauce — even a nudge toward the right API would
> save me a lot of trial and error. Thanks!

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
