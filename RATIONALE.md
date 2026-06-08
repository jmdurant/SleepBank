# SleepBank — Scientific Rationale & Evidence

> **Status: investigational / pre-validation.** SleepBank is a research and
> wellness prototype. It is **not** a cleared or approved medical device and
> makes no diagnostic claim. Nothing here is medical advice. Figures attributed
> to secondary sources are flagged and **must be confirmed against primary
> literature before any clinical, marketing, or regulatory use.**

This document records *why* SleepBank is built the way it is, the evidence base
behind each design decision, what is well-established versus what we must still
validate ourselves, and considerations for future positioning. It is written to
support later presentation, publication, or a regulatory pathway — so it
deliberately distinguishes **established science** from **claims requiring our
own data**.

---

## 1. The problem

Chronic sleep restriction is common among caregivers, clinicians, shift workers,
and parents of children with high needs. Recovering a full night is often
impossible. The question SleepBank addresses is narrow and practical: **can a
short, well-timed nap recover a meaningful amount of alertness — and can a
consumer wrist device time that nap well enough to deliver the benefit while
avoiding the downside (grogginess)?**

---

## 2. Why short naps (homeostatic basis)

**Established.** Sleep propensity is governed by the interaction of a homeostatic
process (Process S — sleep pressure that builds with time awake and dissipates
during sleep) and a circadian process (Process C). A nap discharges
accumulated homeostatic pressure and transiently restores alertness.

- Borbély, A. A. (1982). *A two process model of sleep regulation.* Human
  Neurobiology, 1(3), 195–204. *(Foundational two-process model.)*
- Borbély, A. A., et al. (2016). *The two-process model of sleep regulation: a
  reappraisal.* Journal of Sleep Research, 25(2), 131–143.

**Design implication.** We treat the "sleep bank" as a **plain descriptive
tally** of sleep recovered, not a quantitative ledger. Naps do not fully repay
chronic debt, and the recovery value of a nap depends on prior pressure,
circadian timing, and stages reached — so a precise "deposit value" would
overstate what the science supports. We deliberately avoid that.

---

## 3. Why ~10–20 minutes (the power-nap window)

**Established.** Brief naps improve alertness and performance; very short naps
deliver much of the benefit with the least post-nap impairment.

- Brooks, A., & Lack, L. (2006). *A brief afternoon nap following nocturnal sleep
  restriction: which nap duration is most recuperative?* Sleep, 29(6), 831–840.
  *(Compared 5/10/20/30-min naps; ~10 min was strongly favorable for immediate,
  sustained alertness with minimal inertia.)*
- Tietzel, A. J., & Lack, L. C. (2001/2002). *The recuperative value of brief and
  ultra-brief naps on alertness and cognitive performance.*
- Rosekind, M. R., et al. (1995). NASA Ames "planned cockpit rest" / fatigue
  countermeasure work — operational basis for the ~20–26 min planned nap.

**Design implication.** Our default **Power Nap** targets waking in N1/early-N2,
before substantial slow-wave (N3) sleep consolidates. A **Cycle Nap** (~90 min)
option targets the end of one full sleep cycle. Cycle length varies (~70–120 min
between individuals), so the 90-minute figure is a default, not a precision claim.

---

## 4. Why wake timing matters (sleep inertia)

**Established.** *Sleep inertia* — transient grogginess and impaired performance
on waking — is most severe when waking out of slow-wave sleep (N3). Avoiding N3,
or waking from lighter stages, reduces inertia.

- Hilditch, C. J., & McHill, A. W. (2019). *Sleep inertia: current insights.*
  Nature and Science of Sleep, 11, 155–165.
- Tassi, P., & Muzet, A. (2000). *Sleep inertia.* Sleep Medicine Reviews, 4(4),
  341–353.

**Design implication — the core insight.** The alarm is **onset-relative, not
clock-relative.** Most nap timers count from when the user presses start;
physiology runs from *sleep onset*. SleepBank times the wake from detected onset
(target ≈ onset + 18 min for a power nap), with an absolute session ceiling as a
safety net, and — when EEG is present — an early-wake trigger if slow-wave
encroachment is detected. This is the primary differentiator.

**Risk we must validate (the deprivation paradox).** Chronically sleep-deprived
users — our target — have elevated sleep pressure and may descend into N3 *faster*
and be *more* inertia-prone. A fixed post-onset window may be too long for exactly
the people who most need the product. Quantifying per-user descent rate and
tuning the window (or relying on EEG delta detection) is a primary validation aim.

---

## 5. Sensor basis for onset detection

We detect sleep onset by fusing established physiological correlates. Each is
individually imperfect; the fusion and an immobility gate raise specificity.

- **Actigraphy (motion).** Sustained immobility is the classic actigraphic sleep
  marker (Cole-Kripke, Sadeh algorithms). Known limitation: high sensitivity, low
  specificity — quiet wakefulness reads as sleep. We therefore never declare
  onset on immobility alone.
- **Heart rate.** HR drops from quiet-wake baseline at onset.
- **Heart-rate variability.** Parasympathetic tone rises at onset (↑ RMSSD / HF
  power). Captured via the Polar H10's beat-to-beat RR intervals.
- **EEG (gold-standard signal).** Frontal EEG (Muse: AF7/AF8, TP9/TP10) captures
  the alpha-attenuation → theta-emergence transition that *defines* N1, frontally
  maximal K-complexes (N2), and rising delta (approaching N3). This is the
  highest-fidelity onset and "wake-now" signal and our reference label source.
  - Reference for actigraphy+HR staging feasibility: Walch, O., et al. (2019),
    *Sleep stage prediction with raw acceleration and photoplethysmography from a
    consumer wearable device*, Sleep.

**Design implication — graceful degradation.** The watch is always self-sufficient
(HR + immobility). The Polar H10 adds reliable continuous HR + HRV; Muse adds EEG.
The detector requires immobility AND a cardiac/EEG onset sign, and falls back to
fewer signals when richer ones are absent.

---

## 6. What Apple Watch does — and does not — do

*(Accurate as of this writing; secondary figures flagged for verification.)*

**Apple's nighttime sleep staging** classifies Awake/REM/Core/Deep from
accelerometer motion, heart-rate dynamics, and blood oxygen over 30-second
epochs, validated against PSG/EEG.
- Apple (Oct 2025). *Estimating Sleep Stages from Apple Watch.*
  https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf

**Apple's nap detection** (added watchOS 11, 2024) automatically records naps even
without Sleep Focus, with a **user-configurable minimum duration (reported as
10 / 15 / 20 min, default 15)** and a technical floor around ~6 minutes of
sustained low motion. *So Apple can and does record short naps above the
threshold — an earlier internal claim that it ignores all sub-1-hour naps was
incorrect and has been retracted.*

**The actual, durable gaps SleepBank addresses:**
1. **No real-time intervention.** Apple's staging is **retrospective** — computed
   after the session. Apple has **no smart nap alarm and no wake-before-deep-sleep
   capability.** Recording that a nap happened is orthogonal to waking the user at
   the optimal moment. This gap is fundamental and unaffected by Apple's nap
   recording.
2. **Passive short-nap accuracy is limited.** Secondary coverage of a 2024
   evaluation reports automatic/passive detection concordance dropping to
   **~64% for naps < 25 min** versus **~89% for manually-started sessions ≥ 15
   min** against actigraphy. ⚠️ *Secondary source — obtain and cite the primary
   study before any external use.* If borne out, it means Apple's auto-detection
   is weakest precisely in the power-nap range, while the manual-start regime
   SleepBank operates in is where accuracy is best.

**Are we using Apple's data?** Yes, where useful: we read `HKCategoryValueSleep
Analysis` for context and, critically, we **compare each of our nap decisions
against Apple's retrospective staging of the same window** (excluding our own
written sample) to quantify agreement — see §8.

---

## 7. Differentiator (positioning)

SleepBank is not "a better nap recorder." It is a **closed-loop, onset-timed
smart-wake system** for short naps, with an upgrade path from wrist-only signals
to clinical-grade EEG:

- Onset-relative wake to avoid slow-wave grogginess (no consumer equivalent).
- Tiered, escalating haptic→audio alarm on the wrist.
- Sensor-fusion ladder: watch (HR + motion) → Polar H10 (HR + HRV) → Muse (EEG).
- Writes naps to Apple Health; surfaces them in a Live Activity and home widget.
- A built-in **validation + labeled-data pipeline** that turns each nap into
  evidence and training data.

---

## 8. Validation plan

The product is designed to generate its own evidence. The architecture already
captures, per nap, a full per-second feature trace, the onset/wake decision and
which signal fired, and (where available) the EEG state — and compares it to
Apple's retrospective staging.

**Proposed staged validation:**
1. **n = 1 instrumented (now).** Self-testing with Muse EEG as a reference label
   to characterize the watch-only detector's onset latency and false-positive
   rate; compare to Apple's staging on ≥ threshold naps.
2. **Small cohort, PSG-referenced.** Sensitivity/specificity and onset-latency
   error of the detector against laboratory polysomnography (the diagnostic gold
   standard) — the minimum bar for any accuracy claim.
3. **Outcome study.** Does onset-timed waking reduce post-nap sleep inertia
   (e.g., PVT reaction time, subjective Stanford Sleepiness Scale) versus a fixed
   clock-timer control?

**Labels, honestly:** EEG-derived labels (Muse naps) are strong; Apple-derived
labels exist only for naps above the recording threshold; our own decisions are
weak (circular) labels. The CSV exporter tags every row with its label source so
weak labels can be excluded from model training.

---

## 9. Regulatory positioning (considerations, not advice)

If pursued, the likely fork is **General Wellness** vs **Software as a Medical
Device (SaMD)**:

- **General Wellness (lowest burden).** Claims limited to relaxation, general
  alertness, and sleep-habit support, with no diagnosis/treatment claim. The
  FDA's *General Wellness: Policy for Low Risk Devices* guidance is the reference
  frame. Most consumer nap features sit here.
- **SaMD / De Novo or 510(k).** Any claim of *detecting sleep state* or
  *clinically managing sleep inertia/fatigue* would likely cross into device
  territory and require prospective, PSG-referenced validation and a predicate or
  De Novo pathway. Accuracy claims (sensitivity/specificity, onset-latency error)
  must be substantiated by the §8 studies before they can be made.

**Claims discipline:** until §8 data exist, externally we should describe
SleepBank's benefits in mechanism/intent terms ("designed to time waking before
deep sleep") rather than efficacy terms ("prevents grogginess"), and avoid any
diagnostic language.

---

## 10. References (verify primary sources before formal use)

1. Borbély AA. *A two process model of sleep regulation.* Hum Neurobiol. 1982.
2. Borbély AA, Daan S, Wirz-Justice A, Deboer T. *The two-process model of sleep
   regulation: a reappraisal.* J Sleep Res. 2016.
3. Brooks A, Lack L. *A brief afternoon nap following nocturnal sleep restriction:
   which nap duration is most recuperative?* Sleep. 2006.
4. Tietzel AJ, Lack LC. *The recuperative value of brief and ultra-brief naps…*
   Sleep / J Sleep Res. 2001–2002.
5. Rosekind MR et al. *Alertness management: strategic naps in operational
   settings.* J Sleep Res. 1995 (NASA Ames).
6. Hilditch CJ, McHill AW. *Sleep inertia: current insights.* Nat Sci Sleep. 2019.
7. Tassi P, Muzet A. *Sleep inertia.* Sleep Med Rev. 2000.
8. Walch O et al. *Sleep stage prediction with raw acceleration and PPG from a
   consumer wearable.* Sleep. 2019.
9. Apple. *Estimating Sleep Stages from Apple Watch.* Oct 2025.
10. ⚠️ 2024 evaluation of Apple Watch nap-detection concordance (89% manual ≥15 min
    / 64% passive < 25 min) — **primary citation to be located and confirmed.**
11. FDA. *General Wellness: Policy for Low Risk Devices* (guidance).

---

*Maintained alongside the implementation in `ARCHITECTURE.md`. Corrections welcome
— accuracy here matters more than optimism, especially for anything that may
later support a regulatory or clinical claim.*
