# Ways to Use SleepBank — Sensor Configurations & Trade-offs

> **The point of this doc.** SleepBank is built so it works *however you show up*.
> The smart alarm, the predicted alertness curve, the wind-down breathing, the
> sounds, and the recap all run with **nothing but the phone in your hand**. Every
> sensor you add only makes one thing better — *how precisely it knows you actually
> fell asleep* — so the smart wake fires at the right moment instead of on a timer.
> Nothing is gated behind hardware. You can nap with an empty pocket today and add a
> sensor the day it arrives.

## The one thing sensors change: onset detection

Everything in the app works without a sensor **except** knowing the exact second you
drift off. That single fact — *onset* — is what lets the alarm wake you **before**
deep sleep (so you skip grogginess) and time the wake to a real sleep window instead
of a fixed countdown. The detector ([`HeartRateImmobilityOnsetDetector`]) fuses up
to five signals; the more (and better) signals it has, the earlier and more
confidently it catches onset:

| Signal | What it tells the detector | Best source |
|---|---|---|
| **Heart rate** | The small HR *drop* as you fall asleep | H10 > AirPods ≈ Watch |
| **Immobility** | Body gone still (actigraphy) | H10 chest > Watch wrist > AirPods head > phone |
| **HRV (RMSSD)** | Parasympathetic shift into sleep | **H10 only** (live) |
| **Breathing rate** | Respiration slowing/steadying | **H10 only** (live) |
| **EEG** | Brainwave onset + approach to deep (N3) | **Muse only** |

Two practical truths that shape the table:
- The **phone alone** has no heart rate and only its own accelerometer — and the
  phone usually sits on a nightstand, so its motion barely moves. That's why phone-
  only falls back to a **manual / timer** experience (below).
- A sensor is only useful if it's **on your body**. That's the whole logic of the
  immobility priority chain: chest → wrist → head → (last resort) phone.

---

## The configurations

### 1. Phone only — manual nap tracker & timer
**Hardware:** just your iPhone. No pairing, no wearable.

**What you get**
- Pick Power Nap (~20 min) or Cycle Nap (~90 min); the smart alarm runs as a
  **reliable timed wake** (ceiling timer) and sounds through Focus / Do Not Disturb.
- Full wind-down: the 4-7-8 breathing circle + haptics, relaxing sounds / brown
  noise, optional guided body-scan.
- The predicted **alertness curve**, daylight + movement nudges, KSS sleepiness
  before/after, and the nap recap — all unaffected by sensors.
- Background keep-alive so the timer survives the screen locking.

**Pros**
- Works anywhere, instantly, for everyone — the true zero-friction entry point.
- Nothing to charge, wear, or connect; nothing can drop mid-nap.
- Perfectly good as a **deliberate-rest timer**: lie down, breathe, get woken.

**Cons**
- **No real onset detection** — the wake is a countdown, not "wake me 20 min after I
  actually fall asleep." If you take 15 min to drop off, the timer doesn't know.
- No HR / HRV / breathing / EEG in the recap; the sleep chart is estimated, not
  measured.

**Best for:** first run, travelers, anyone who just wants a smart-ish nap timer with
a great wind-down — and the baseline everyone can rely on.

---

### 2. Phone + AirPods Pro — zero-extra-hardware sensing
**Hardware:** iPhone + AirPods Pro 3 (or HR-capable AirPods). The earbuds are both
the **audio output** (our sounds/guidance) *and* the **sensors**.

**What you get**
- **Continuous heart rate** during the nap via an iOS 26 workout session (the
  "AirPulse" path — opened then discarded, so nothing is saved to Health/Activity).
- **Head-stillness** as the immobility signal via `CMHeadphoneMotionManager` — the
  AirPods are on your head, so this is a *real* body-motion signal, far better than
  the nightstand phone. (Live "Head movement %" is visible in Sensors → AirPods Pro.)

**Pros**
- **Real onset detection with gear you already wear for the audio** — no extra
  device, no extra cost, nothing new to charge specifically for this.
- HR + head motion together are enough for a solid wake-before-deep decision.
- Most people already nap with earbuds in; this is the sweet-spot upgrade.

**Cons**
- No HRV or breathing rate (in-ear PPG + a workout session don't expose those live).
- Signal stops the instant an earbud leaves your ear; battery drains over a long
  cycle nap; in-ear PPG is slightly noisier than a chest ECG.

**Best for:** the everyday power-napper who wants accurate wakes without buying a
strap. **This is the recommended default once past phone-only.**

---

### 3. Phone + Apple Watch — wrist HR & motion, hands-free
**Hardware:** iPhone + Apple Watch (with the SleepBank watch app open/reachable).

**What you get**
- **Wrist heart rate** and **wrist motion** forwarded from the watch to the phone
  (the watch runs a brief workout to read HR; it's discarded, not saved).
- Lets you nap with the phone across the room and the watch doing the sensing.

**Pros**
- A wearable most users already own; nothing in your ears if you don't want audio.
- Wrist motion is genuine body actigraphy (better than the phone).
- Frees the AirPods to be purely audio, or to skip audio entirely.

**Cons**
- The phone **can't wake the watch app** — the watch app has to be open/reachable,
  so it needs a deliberate start (tap Check / open the watch app).
- **No live HRV or respiratory rate** — the watch samples HRV sporadically
  (retrospective) and only measures respiration during tracked sleep, so neither is
  available for live onset.
- Depends on a reachable Bluetooth link; wrist HR is a touch noisier than chest.

**Best for:** Apple Watch owners who'd rather wear the watch than earbuds, or who
want the phone out of reach during the nap.

---

### 4. Phone + Polar H10 — the gold standard
**Hardware:** iPhone + Polar H10 chest strap (BLE).

**What you get**
- **Continuous ECG-grade heart rate**, **HRV (RMSSD)**, **breathing rate**, and
  **chest accelerometer** (movement, posture, orientation) — the richest live feed
  the app supports, and the *only* live source of HRV and breathing.

**Pros**
- The most accurate, earliest, most confident onset detection — HR drop + true
  stillness + HRV shift + breathing slowdown all at once.
- Research-quality data; the best source for **training the on-device YASA model**
  and validating everything else against ground truth.

**Cons**
- A chest strap you have to wear, dampen, and charge — the highest friction.
- Overkill for a casual nap; most users won't wear one daily.

**Best for:** you (n=1 validation), data collection, and anyone who wants the most
reliable wake possible and doesn't mind the strap.

---

### 5. Add Muse — the only brain signal
**Hardware:** any config above **+ Muse headband** (EEG).

**What you get**
- **EEG-based onset** and, uniquely, **approach-to-deep-sleep (N3) detection** —
  the only sensor that can see you *heading into* slow-wave sleep so the alarm can
  pull you out just before it.

**Pros**
- The closest thing to PSG staging in the kit; the only signal that reads the brain
  directly rather than inferring sleep from the body.
- Strongest "wake before deep" timing when paired with H10.

**Cons**
- A headband to wear and fit (contact quality matters); the highest setup effort.
- Frontal-only EEG; onset from frontal channels is the hard case (see
  [`EEG_EVIDENCE.md`](EEG_EVIDENCE.md)) — best as an *addition* to HR + motion, not
  alone.

**Best for:** the deepest data sessions and the "never wake me groggy" goal —
typically stacked **H10 + Muse + (Watch or AirPods)**.

---

## Stacking & the priority chain

You can connect several at once; SleepBank **fuses** them and always uses the best
available source per signal, falling back automatically as devices drop:

- **Heart rate:** H10 → Watch → AirPods
- **Immobility:** H10 chest → Watch wrist → AirPods head → phone
- **HRV / breathing:** H10 only
- **EEG (onset + deep):** Muse only

The active-nap stat row and the home **Sensors** card adapt to whatever's connected,
so you only see the readouts you actually have. Add a sensor mid-journey and the app
just gets sharper — no mode to switch, no setting to flip.

## Quick chooser

| If you… | Use |
|---|---|
| Just want to lie down and be woken | **Phone only** |
| Already nap with earbuds in | **Phone + AirPods Pro** *(recommended)* |
| Wear an Apple Watch, no earbuds | **Phone + Watch** |
| Want the most accurate wake / are collecting data | **Phone + H10** |
| Want brain-based "wake before deep" | **+ Muse** |

> **Bottom line:** the floor is a genuinely useful manual nap timer that anyone can
> use today; the ceiling is near-lab-grade onset detection. You move up the rungs
> only as far as you want to — the app meets you at every one.
