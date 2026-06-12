# SleepBank — Hypotheses & Analysis Plan (Pre-Registration Draft)

> **DRAFT v0.1 — 2026-06-12.** The falsifiable science behind SleepBank, written so
> a sleep-medicine / psychology faculty collaborator and a biostatistician can
> pressure-test it and so the early naps already being collected become a *formal
> pilot* that powers a sample-size calculation. This is the **measurement &
> efficacy** track (onset detection + nap alertness + stimulant reliance) — the
> **breathing/biofeedback** pilot lives separately in `PILOT_PROTOCOL_SYNOPSIS.md`
> and supports the FDA 510(k); the two share infrastructure but answer different
> questions.
>
> **Not regulatory, statistical, or legal advice.** Items marked **[VERIFY]** are my
> best guess and must be confirmed with the academic partner, the biostatistician,
> and the IRB before use. Effect sizes marked **[PILOT]** are placeholders to be
> filled from the n=1 / early-cohort data. Companion to `DATA_ARCHITECTURE.md`.

---

## 1. The one-sentence thesis
A phone-centered system that **times** rest and light to the user's own circadian
rhythm — and detects when they actually fall asleep so it can wake them before deep
sleep — can deliver the alertness benefit of a nap **reliably and at scale**, and
over time **reduce reliance on caffeine and stimulants** in a high-demand
population (college students / trainees).

This breaks into three independently-testable claims: the instrument **measures**
sleep onset validly (Aim 1), a *detected-onset* nap **works** better than an
untimed one (Aim 2), and sustained use **changes behavior** (Aim 3).

---

## 2. Why this is fundable / publishable
- **Gap:** college-age and trainee populations lean heavily on caffeine, nicotine,
  and prescription stimulants (modafinil, amphetamine salts) to offset chronic
  sleep debt — a behavior with real downstream harms and little non-drug tooling.
- **What's new methodologically:** a single instrument that runs from *zero extra
  hardware* (phone-only timer) up to *near-PSG fidelity* (chest ECG + frontal EEG),
  so the same protocol can recruit broadly **and** validate against ground truth.
- **The honest framing (load-bearing):** SleepBank helps a person *cope with and
  optimize* a short-sleep day — it does **not** claim to replace needed sleep or to
  treat any sleep disorder. (Mirrors the product's own copy; keeps us in a wellness
  / behavioral lane, not a diagnostic one.)

---

## 3. The instrument (what produces the data)
A multi-rung sensor stack, fused on-device, that degrades gracefully:

| Rung | Live signals | Role in this plan |
|---|---|---|
| Phone only | motion (weak) | Baseline / manual timer arm |
| + AirPods Pro | HR + **head-stillness** | The *scalable* index test |
| + Apple Watch | wrist HR + motion | Alternate scalable index test |
| + Polar H10 | ECG-grade HR, HRV, breathing, chest accel | High-fidelity comparator |
| + Muse | frontal EEG (onset + N3-approach) | High-fidelity comparator |
| **PSG (partner lab)** | full montage | **Reference standard** |

Validated self-report already instrumented in-app: **KSS** (momentary sleepiness,
pre/post nap), **Epworth/ESS** (trait daytime sleepiness), **PSAS** (pre-sleep
arousal), and **PHQ-9 / GAD-7** (mood comorbidity, read from HealthKit). See
`../NAP_BENEFIT_EVIDENCE.md`, `../EEG_EVIDENCE.md`, `../MOVEMENT_EVIDENCE.md`.

---

## 4. Specific aims, hypotheses & primary endpoints

### Aim 1 — Validation: does the scalable stack detect onset?
> **H1.** Sleep-onset time estimated from the phone-accessible stack (AirPods-only;
> secondarily Watch-only) agrees with PSG-scored sleep onset within a pre-specified
> clinically acceptable margin.

- **Design:** within-subject **method-comparison** study. Each participant is
  instrumented *simultaneously* with phone+AirPods, Watch, H10, Muse, **and** PSG
  during a single afternoon nap opportunity in the partner sleep lab.
- **Reference standard:** PSG sleep onset = AASM-scored first epoch of any sleep
  (and, separately, first epoch of N1) **[VERIFY scorer blinding & epoching]**.
- **Index tests:** app-derived onset timestamp per rung.
- **Primary endpoint:** **mean absolute error (MAE) in onset latency**, app vs PSG,
  for the AirPods rung. **Pre-specified equivalence margin: ±5 min [VERIFY]** (an
  error small relative to a 20-min power nap).
- **Agreement analysis:** Bland–Altman (bias + 95% limits of agreement) and ICC(2,1)
  for continuous onset latency; epoch-level **sensitivity/specificity** and Cohen's
  κ for sleep/wake classification vs PSG.
- **Falsified if:** the 95% CI for mean error excludes the equivalence margin, or
  limits of agreement exceed ±10 min.

### Aim 2 — Mechanism/efficacy: does a *detected-onset* nap work better?
> **H2.** Naps in which onset is detected (and wake is timed before deep sleep)
> produce a larger reduction in momentary sleepiness than time-matched naps without
> detected onset.

- **Design:** within-subject comparison across each participant's logged naps; in a
  controlled arm, randomize **smart-onset wake vs fixed-timer wake** at matched
  durations.
- **Primary endpoint:** **ΔKSS** (immediately pre → ~10 min post nap).
- **Key secondaries:** sleep-inertia severity (KSS at wake vs +10/+20 min — captures
  the "woken from deep sleep" grogginess the smart wake is meant to avoid),
  self-reported nap quality, objective HRV recovery (H10 sub-sample).
- **Analysis:** linear mixed-effects model, ΔKSS ~ condition + nap duration +
  circadian time + baseline KSS + (1 | participant). **[VERIFY covariates]**
- **Falsified if:** condition coefficient is null / favors the untimed nap.

### Aim 3 — Behavioral: does sustained use reduce stimulant reliance?
> **H3.** Over an 8-week field period **[VERIFY duration]**, regular use is
> associated with reduced daytime sleepiness and reduced self-reported
> caffeine/stimulant use.

- **Design:** field cohort (college students via Campus Health), single-arm pilot
  for effect-size estimation; a waitlist-randomized arm if powered. **[VERIFY]**
- **Co-primary endpoints:** change in **ESS** (baseline → week 8); change in a
  **daily stimulant-use log** (caffeine mg-equivalents; any prescription/OTC
  stimulant use).
- **Secondaries:** nap frequency/adherence, morning-daylight adherence, PSAS,
  PHQ-9/GAD-7 as covariates, retention.
- **Analysis:** mixed-effects models on repeated measures; pre-registered handling
  of dropout (intention-to-treat with multiple imputation). **[VERIFY]**
- **Falsified if:** no detectable change in ESS or stimulant use vs baseline/control.

---

## 5. Phasing (each phase de-risks the next)
0. **Dogfood pilot (underway):** sponsor n=1 + small convenience sample. Purpose:
   shake out the instrument, generate **[PILOT]** effect-size & variance estimates
   for the Aim-1 margin and Aim-2 ΔKSS. **Not for inference.**
1. **Aim 1 validation (partner sleep lab):** the simultaneous-PSG method-comparison
   study. Small n (within-subject agreement needs fewer subjects than between-group
   efficacy). This is the credibility keystone — everything scalable rests on it.
2. **Aim 2/3 field study (campus):** powered off Phase-0/1 estimates.

---

## 6. Sample size (logic, not numbers yet)
- **Aim 1** is an **agreement** study: n driven by the precision of the limits of
  agreement, not a group contrast — typically far smaller (order ~20–30 nap-PSG
  pairs) **[VERIFY with biostatistician once [PILOT] SD of onset error is known]**.
- **Aim 2** within-subject ΔKSS: powered on the **[PILOT]** ΔKSS effect size and its
  within-person SD.
- **Aim 3** field: powered on **[PILOT]**/literature ESS change.
- All three calculations are **gated on the Phase-0 pilot** — which is precisely why
  the naps being collected now matter.

---

## 7. Pre-registration & rigor commitments
- Register the analysis plan (OSF / ClinicalTrials.gov as appropriate) **before**
  Phase 1/2 data collection; primary vs secondary endpoints fixed in advance.
- PSG scoring **blinded** to app output; app onset computed by frozen algorithm
  version (git SHA recorded per session) so the index test can't be tuned to truth
  post hoc.
- Pre-specified handling of missing data, multiplicity (Aim 3 co-primaries), and
  stopping.
- Data governance per `DATA_ARCHITECTURE.md`: on-device-first, consented flow to a
  partner-controlled backend (REDCap), never CloudKit.

## 8. Conflicts & ethics (flagged, see protocol synopsis §15)
The sponsor holds adjunct faculty appointments; day-to-day PI, recruitment, and
consent must sit **outside** the sponsor's evaluative authority over students to
avoid coercion. Sponsor's role is device + analysis, not subject-facing recruiting.

## 9. Open questions for the biostatistician / collaborator
- Equivalence margin for onset MAE — is ±5 min defensible for a power nap? **[VERIFY]**
- Reference definition of "onset" — first-sleep vs first-N1 vs 3-min rule. **[VERIFY]**
- Aim 3 design — single-arm pilot vs waitlist RCT given recruiting realities.
- Instrument licensing for any added scales (ESS/KSS/PSAS usage terms). **[VERIFY]**
