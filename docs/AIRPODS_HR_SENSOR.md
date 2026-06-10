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

> **✅ CRUX RESOLVED (AirPulse dev Christian Range, 2026-06-10).** There is **no
> secret non-workout API.** In his words: *"I start a workout just as every other
> app as well and delete it afterwards. That's the only way I know to start the
> heart rate sensor and receive the data in Apple Health, which I can then read from
> Apple Health."* So it's **path (B): workout-gated.** The recipe:
> 1. **Start a workout** → activates the AirPods Pro 3 HR sensor.
> 2. HR streams into **HealthKit** during the workout.
> 3. **Read it** (from HealthKit, or directly off the live workout builder).
> 4. **Delete the workout afterward** so it doesn't litter Fitness / the rings.
>
> AirPulse's "anytime you put them in / live graph" is just an auto-started workout
> under the hood. For SleepBank this is the path we already use on the watch — run a
> quiet `.mindAndBody` `HKWorkoutSession` during the nap, read AirPods HR (live via
> `HKLiveWorkoutBuilder`), fuse into onset detection, and delete the workout on nap
> end. Path (A) passive HealthKit remains too sparse for onset.

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

## Open questions

**#0 (access path) — ✅ ANSWERED by Christian:** workout-gated. Start a workout →
sensor on → HR to HealthKit → read it → delete the workout after. No special API or
non-workout path.

**Still worth confirming when we build/test on-device:**

1. **HR once asleep / still:** does HR keep streaming after the user stops moving and
   falls asleep, or does workout auto-pause / no-motion stop it? (We need the onset
   HR *drop* from a near-motionless person — so disable auto-pause.)
2. **Audio coexistence:** does HR sensing run while AirPods play our noise + TTS?
   (Rhythm plays audio while reading HR, so likely yes.)
3. **Update cadence & latency:** how often does HR land in Health / the builder?
   (≤5 s is fine for onset.) Reading off `HKLiveWorkoutBuilder` directly is likely
   fresher than round-tripping through HealthKit.
4. **Workout housekeeping:** Christian deletes the workout afterward so it doesn't
   litter Fitness/rings — we'll do the same (and may log a `mindfulSession` for
   Mindful Minutes instead).
5. **Battery** over a 20–90 min session.

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

Research done, **access path confirmed by the AirPulse dev (workout-gated)**, **not
yet wired**. Implementation plan, now unblocked:
1. `AirPodsHRService` runs an `HKWorkoutSession` (`.mindAndBody`) + `HKLiveWorkoutBuilder`
   during a phone nap, with auto-pause disabled.
2. Read HR from the live builder's `didCollectDataOf` callback → feed
   `OnsetSignal.heartRate` in `PhoneNapController`, alongside H10/Muse.
3. Optionally feed AirPods head-stillness (`CMHeadphoneMotionManager`) into
   `movementIntensity`.
4. On nap end, finish and **delete the workout** (Christian's tip) so it doesn't
   litter Fitness/rings; optionally write a `mindfulSession`.
Gives a phone-only, anywhere nap with real onset detection from the earbuds already
in for the wind-down audio.

## Sources

- DCRainmaker, AirPods Pro 3 sports/fitness review (Sept 2025) — IR sensor, no BLE-GATT broadcast, iPhone-only, workout-gated. https://www.dcrainmaker.com/2025/09/airpods-pro-3-in-depth-sports-fitness-review.html
- WWDC25 session 322, *Track workouts with HealthKit on iOS and iPadOS* — iOS workout sessions + live HR API. https://developer.apple.com/videos/play/wwdc2025/322/
- Strava live AirPods Pro 3 HR support. https://apple.gadgethacks.com/news/strava-adds-airpods-pro-3-support-for-live-heart-rate-on-iphone/
- Apple Support, *Track your heart rate during workouts with AirPods Pro 3* — lists Fitness+ Meditation/Yoga as HR-tracked workout types. https://support.apple.com/guide/airpods/track-heart-rate-workouts-airpods-pro-3-dev1b40fb47d/web
- HKLiveWorkoutBuilder. https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder
- *Rhythm • Heart Rate Meditation* — third-party app reading live AirPods Pro 3 HR during guided meditation (precedent for at-rest HR + audio coexistence). https://apps.apple.com/us/app/rhythm-heart-rate-meditation/id6752779850
- AirPulse (Christian Range) — App Store. https://apps.apple.com/es/app/airpulse/id6760625679
