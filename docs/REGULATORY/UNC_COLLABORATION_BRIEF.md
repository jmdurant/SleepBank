# SleepBank × UNC — Collaboration Brief (One-Pager)

> **DRAFT v0.1 — 2026-06-12.** A faculty-triage one-pager. Goal: get a 30-minute
> meeting with a UNC sleep-medicine / psychology collaborator. Keep it to one page
> when sent. Names/titles marked **[VERIFY]** before sending. Companion to
> `HYPOTHESES_AND_ANALYSIS_PLAN.md`.

---

**SleepBank — a scalable, validatable instrument for timed-nap & light interventions
to reduce stimulant reliance in students and trainees.**

**Investigator:** James DuRant, MD — developmental-behavioral pediatrics; adjunct
faculty, UNC **[VERIFY appointment/title]**; UNC '03; former undergraduate research
assistant in Dr. Josephine Johns' lab (UNC Psychiatry).

### The problem
College students and clinical trainees run on chronic sleep debt and offset it with
caffeine, nicotine, and prescription stimulants (modafinil, amphetamine salts) —
common, escalating, and under-addressed, with few validated *non-drug* tools.

### The approach
SleepBank times rest and light to the user's own circadian rhythm and detects the
moment they fall asleep, so it can wake them **before** deep sleep — delivering a
nap's alertness benefit without the grogginess, and anchoring morning light to
stabilize the rhythm. It is explicit that it helps a person *optimize* a short-sleep
day, **not** replace needed sleep or treat a sleep disorder (a wellness/behavioral
lane, by design).

### Why it's research-grade (not just an app)
- **Runs from zero hardware to near-PSG fidelity on one instrument:** phone-only →
  AirPods (HR + head-stillness) → Apple Watch → Polar H10 (ECG HR, HRV, breathing)
  → Muse (frontal EEG). The *same* protocol can recruit broadly **and** validate
  against ground truth.
- **Validated self-report already built in:** Karolinska Sleepiness (KSS), Epworth
  (ESS), Pre-Sleep Arousal (PSAS), and PHQ-9/GAD-7 (from Apple Health).
- **An analyzable data pipeline:** time-stamped features + raw EEG export and an
  on-device sleep-staging model path (YASA-based), with on-device-first, consented
  data governance.

### What we'd test (see analysis plan)
1. **Validation:** does phone/AirPods-detected sleep onset agree with **PSG** within
   ±5 min? *(method-comparison study in a UNC sleep lab)*
2. **Efficacy:** do *detected-onset* naps reduce momentary sleepiness (ΔKSS) more
   than untimed naps?
3. **Behavioral:** over 8 weeks, does use lower daytime sleepiness (ESS) and
   self-reported stimulant use in a student cohort?

### The ask (any subset is a start)
- A **simultaneous-PSG validation session or two** in the UNC Sleep Disorders Center
  to ground-truth onset detection.
- A path to a **student cohort** (e.g., via Campus Health) for the field study.
- A faculty **co-investigator / site PI** (recruitment & consent sit outside the
  sponsor's evaluative authority — see ethics note in the analysis plan).
- Optionally, a joint **UNC Sleep Research pilot-grant** application.

### Why UNC
Beyond the personal tie ('03; the Johns lab): UNC has the clinical sleep
infrastructure (**Dr. Bradley Vaughn**, UNC Sleep Disorders Center **[VERIFY]**), a
**Neurodiagnostics & Sleep Science** program training the technologists who run
PSG (**Mary Ellen Wells [VERIFY]**) — both a validation resource *and* a student
workforce — a standing **Sleep Research pilot-grant** mechanism, and the exact
student population the thesis targets, on one campus.

---
*Status: investigational wellness prototype — not a medical device, no diagnostic
claim. IRB approval and a faculty site PI required before any data collection.*
