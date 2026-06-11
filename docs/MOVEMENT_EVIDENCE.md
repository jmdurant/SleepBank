# SleepBank — Movement / Acute-Exercise Evidence Base

> **Purpose.** The evidence behind the curve's *movement* lift — the
> `morningActivityDose` and the `arousal()` walk/workout coefficients in
> `AlertnessRhythm`, and the "Movement" row in the Alertness Score explainer.
> Brings movement up to the citation standard of `NAP_BENEFIT_EVIDENCE.md` and
> `DAYLIGHT_EVIDENCE.md`.
>
> **Transparency on rigor:** unlike the nap and daylight bases (each a full 5-angle,
> ~18-source, adversarially-verified deep-research pass), this is a **lighter pass**
> (a review + targeted studies, 2026-06-11) anchoring the claim we already make.
> Flagged for a full deep-research upgrade. **Verify every citation against the
> primary source before any external/clinical/regulatory use.**

---

## 1. Headline: a brisk bout gives a *mild, short-lived* alertness lift

Acute moderate-intensity aerobic exercise (a brisk walk, ~10–30 min) reliably
produces a **small, fairly immediate improvement in alertness and reaction time**
that is present during and shortly after the bout — distinct in *kind* from a nap:
it's an **arousal/catecholamine + core-temperature** lift, **not** a discharge of
sleep pressure. So, like morning light's acute effect, it is **mild and transient**
— the bigger, more durable value of regular morning movement is as a **circadian
zeitgeber** (a daily timing cue), parallel to morning light.

This matches how the model treats it: movement is a **smaller, shorter** lift than a
nap, on the order of the morning-light effect, with a workout worth roughly twice a
walk.

## 2. The evidence

- **Cantelon (2021), *Frontiers in Psychology* — "A Review of Cognitive Changes
  During Acute Aerobic Exercise."** Moderate-intensity exercise consistently speeds
  reaction time (e.g., Go/No-Go) with no decrements; benefits appear **during** the
  bout and through roughly the **first ~30 min** of continuous moderate activity.
  DOI: 10.3389/fpsyg.2021.653158.
- **Acute exercise vs. nap (PMC8987024)** — "Planning Ability and Alertness After
  Nap Deprivation: Beneficial Effects of Acute Moderate-Intensity Aerobic Exercise
  Greater Than Sitting/Naps." Direct head-to-head support that a moderate bout lifts
  alertness/planning acutely. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8987024/
- **Arousal-vigilance work (e.g., Sanchis et al., 2020, *Sci Rep*)** — exercise
  intensity modulates arousal vigilance, consistent with a catecholamine/arousal
  mechanism rather than homeostatic sleep-pressure relief.

## 3. How it maps to the model (`AlertnessRhythm`)

- **`morningActivityPeak ≈ 0.10`** — the morning-movement lift, set on par with the
  morning-light peak (~0.12): both are *modest* morning levers.
- **`arousal()` coefficients** — walk ≈ 0.10, workout ≈ 0.21 (workout ≈ 2× a walk),
  a short-lived bump that builds over ~min and fades over ~1.5 h — i.e., placed late
  it keeps the evening elevated (the honest "exercise too close to bed" cost).
- **Magnitude shown in-app:** *Mild boost · short-lived* — deliberately below the
  nap's *Moderate · ~1–3 h*, consistent with the evidence and the model.

## 4. Open question for the full pass
Quantify the acute-alertness effect size (and its decay) for a *brisk walk
specifically* in non-athletes, and whether morning timing adds a circadian-anchoring
benefit beyond the acute bump (parallel to the morning-light CAR story).
