# SleepBank — EEG Sleep-Detection Evidence Base

> **Purpose.** A durable, citable record of the evidence behind SleepBank's
> Muse/frontal-EEG sleep detection, for future presentation or journal write-up.
> Compiled from a fact-checked deep-research pass (2026-06-08): 5 search angles,
> 26 sources fetched, 122 claims extracted, 25 adversarially verified (3 independent
> verifier votes each), 22 confirmed / 3 refuted. Confidence and vote tallies are
> noted per finding. Companion to `RATIONALE.md` (clinical rationale) and the
> memory note `muse-eeg-sleep-staging-research`.
>
> **Verify every citation against the primary source before any external/clinical/
> regulatory use.** Figures from preprints or secondary coverage are flagged.

---

## 1. Headline: the two product goals split by difficulty

Consumer frontal EEG (Muse-S; 4 ch AF7/AF8 + TP9/TP10, referenced near Fpz, 256 Hz)
reaches **substantial overall agreement with level-1 PSG** for automated 5-stage
staging — **Cohen's κ 0.76**, 88–96% accuracy, sensitivity 79–92%, specificity
90–99% (n=47 adults, AASM v3.0). *(high confidence, 3-0)*

But per-stage agreement is uneven, and it maps cleanly onto our two goals:

| Stage | κ vs PSG | Relevance |
|---|---|---|
| Wake | 0.84 | — |
| **N1 (wake→onset)** | **0.41** (fair; "most challenging stage") | our onset goal — **hard frontally** |
| N2 | 0.75 | — |
| **N3 (deep)** | **0.77** (substantial) | our wake-before-deep goal — **well-supported** |
| REM | 0.85 | — |

*(high confidence, 3-0.)* Mechanism: slow waves (N3) are **frontally dominant**
(the reason AASM 2007 added frontal derivations), while the canonical onset cue
(occipital alpha attenuation) is poorly captured frontally.

> **Important ceiling:** these κ come from **InteraXon's proprietary ML algorithm**
> on the full 4-channel set — a best-case ceiling, **not** what a fixed-threshold
> band-power heuristic achieves.

Sources: Sleep Advances zpaf089 (OUP) / PMC12782022.

## 2. AASM scoring criteria (encodable, but defined on central derivations)

- **Sleep onset** = start of the first epoch scored as any stage other than Wake.
- **N1, alpha generators:** alpha attenuated and replaced by low-amplitude
  mixed-frequency (predominantly 4–7 Hz theta) activity for **>50% of the epoch**.
- **N1, non-alpha generators:** earliest of (a) 4–7 Hz theta **with ≥1 Hz slowing**
  of background from wake, (b) vertex sharp waves, or (c) slow eye movements.
- **N3:** slow-wave activity **0.5–2.0 Hz, ≥75 µV peak-to-peak (frontal
  derivations), occupying ≥20% of a 30 s epoch.**
- Coarse band glossary: delta 0–3.99, theta 4–7.99, alpha 8–13, beta >13 Hz (no
  separate sigma/gamma band).
- All scoring is on **30 s epochs**. *(high confidence, 3-0.)*

> **Onset requires a relative spectral *shift* (theta rise + ≥1 Hz slowing), not a
> fixed absolute theta threshold**, and the rules are defined on **central (C3/C4)**
> derivations — frontal (AF7/AF8) application is an extrapolation.

Sources: AASM Manual 2012 (neumosur PDF); AASM v2.1 Summary of Updates.

## 3. Fixed µV thresholds do NOT transfer to Muse — calibrate per-subject/device

- Bipolar frontal slow-wave amplitude (Fz-Cz) is only **~60–65% of the referential
  F4-M1 amplitude** (cancellation); AASM directs using a central channel (C4-M1)
  as the primary N3-detection channel. Correction factors: F4-M1 ≈ 1.20, Fz-Cz ≈
  0.76 (ratio ~0.63). *(2-1 / 3-0; Duce 2014 JCSM, Kemp 2013.)*
- A Fpz-referenced wearable (Zmax, F7-Fpz/F8-Fpz, 256 Hz) **under-estimates
  bandpower across all bands by −0.41 to −0.74 log units** (active Fpz reference);
  a **per-subject N2-referenced calibration** removes the bias and beat N3/REM
  references (post-cal r=0.601 vs 0.479/0.489). *(medium confidence — non-peer-
  reviewed June 2026 preprint, device is Zmax not Muse; pattern likely transfers,
  specifics do not.)*

> **Implication:** the AASM ≥75 µV / ≥20% N3 rule must be **re-calibrated, not
> copied**, for Muse. SleepBank uses baseline-relative thresholds for exactly this
> reason. Sources: PMC4067446, PMC3733975, medRxiv 2026.06.01.26354593.

## 4. On-device single-channel deep learning is feasible

Single-channel EEG can do 5-class staging at **83.5% accuracy** (20-fold CV,
Sleep-EDF, Fpz-Cz), running near-real-time on **30 s epochs on-device** (TF-Lite
Android, BLE, no server). *(high confidence, 3-0; Koushik/Amores/Maes, IEEE BSN
2019 / arXiv:1811.10111.)*

> **Caveat:** 83.5% is on Sleep-EDF PSG data with a custom flexible headband, **not
> Muse-vs-PSG** — it establishes feasibility/benchmark, not a Muse-validated κ.

Sources: media.mit.edu/projects/sleep-staging-EEG; arXiv 1811.10111; github.com/AbhayKoushik/RealTimeSleepStaging.

## 5. Open-source tools (the practical path — the field is ML, not fixed thresholds)

- **YASA** — peer-reviewed automatic staging + native **spindle / slow-wave / REM
  detectors**, single- or multi-channel. **86.6% accuracy / κ 0.80** vs 5-expert
  consensus on >30,000 h PSG. BSD-3 (permissive). *(high confidence, 3-0.)*
  Validated on full PSG, **not frontal-only consumer montages** (validation gap).
  Vallat & Walker, eLife 2021 (10.7554/eLife.70092); github.com/raphaelvallat/yasa.
- **U-Sleep / U-Time** — fully-convolutional, **montage-agnostic** (on-the-fly random
  channel configs), retrainable; trained on 15,660 participants / 16 studies.
  *(high confidence, 3-0.)* **Caveat:** deployed model needs ≥2 ch (1 EEG + 1 EOG);
  Muse has no true EOG → frontal-only use requires **retraining**, not just
  inference. Perslev et al., npj Digital Medicine 2021 (PMC8050216);
  github.com/perslev/U-Time.
- **muse-lsl** — Muse BLE → LSL streaming (github.com/alexandrebarachant/muse-lsl).
- **Sleep-EDF** — the open PSG corpus to train on.

## 6. Not supported — claims REFUTED in verification (do NOT cite)

- ✗ *"Across 42 validation studies, EEG wearables show consistently high staging
  accuracy vs PSG"* — **0-3** (overstated/unsupported as worded).
- ✗ *"The AASM 75 µV / ≥20% N3 rule is defined over frontal regions and applies
  directly to Muse AF7/AF8"* — **0-3** (the rule is central-derivation-defined;
  amplitude does not transfer literally — see §3).
- ✗ *"YASA spindle under-detection is fixed by lowering its relative sigma-power
  pre-filter"* — **1-2** (not established).

## 7. Open questions (gaps a study would need to fill)

1. Sensitivity/specificity and **detection latency** of a calibrated band-power
   onset heuristic on Muse 2 vs PSG — no source gave Muse-specific real-time onset
   numbers (only stage-level κ).
2. Whether **FOOOF/specparam** aperiodic (1/f) correction, and relative vs absolute
   vs ratio band power [e.g. (δ+θ)/(α+β)], measurably improves frontal-only staging.
3. Whether the Zmax N2-referenced calibration transfers to Muse's near-Fpz montage,
   and Muse's equivalent calibration factor.
4. Whether a fine-tuned U-Sleep / retrained YASA on Muse/frontal-only EEG (handling
   the missing EOG) can match InteraXon's 0.76 proprietary ceiling.

## 8. How SleepBank applies this (design decisions)

- EEG used **primarily for N3-approach** (frontally reliable); onset leans on
  HR/HRV/immobility/breathing with EEG as a high-bar corroborator (N1 is weakest
  frontally).
- Decisions on **30 s rolling epochs**, **baseline-relative** thresholds (not
  absolute µV), per the calibration findings.
- Roadmap: label naps offline with **YASA** (silver standard) → train an on-device
  model (CreateML / TF-Lite) → swap into `CoreMLOnsetDetector`. The in-app
  validation pipeline + `tools/yasa/` capture and process the data.

---

## References

1. Estimating sleep stages from Muse-S vs level-1 PSG (κ 0.76). Sleep Advances, zpaf089. https://academic.oup.com/sleepadvances/advance-article/doi/10.1093/sleepadvances/zpaf089/8377974 · mirror https://pmc.ncbi.nlm.nih.gov/articles/PMC12782022/
2. AASM Manual for the Scoring of Sleep (2012). https://www.neumosur.net/files/grupos-trabajo/suenio/AASM-Manual-2012.pdf
3. AASM v2.1 Summary of Updates. https://aasm.org/wp-content/uploads/2017/11/Summary-of-Updates-in-v2.1-FINAL.pdf
4. Ruehland et al., frontal/occipital derivation rationale, Sleep 2011. https://pmc.ncbi.nlm.nih.gov/articles/PMC3001799/
5. Duce et al., bipolar frontal slow-wave amplitude, JCSM 2014. https://pmc.ncbi.nlm.nih.gov/articles/PMC4067446/
6. Kemp et al., derivation amplitude correction factors, 2013. https://pmc.ncbi.nlm.nih.gov/articles/PMC3733975/
7. Zmax wearable bandpower bias + N2 calibration (preprint, 2026). https://www.medrxiv.org/content/10.64898/2026.06.01.26354593v1.full
8. Koushik/Amores/Maes, real-time single-channel staging, IEEE BSN 2019. https://www.media.mit.edu/projects/sleep-staging-EEG/overview/ · https://arxiv.org/pdf/1811.10111 · https://github.com/AbhayKoushik/RealTimeSleepStaging
9. Vallat & Walker, YASA, eLife 2021. https://doi.org/10.7554/eLife.70092 · https://github.com/raphaelvallat/yasa
10. Perslev et al., U-Sleep, npj Digital Medicine 2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC8050216/ · https://github.com/perslev/U-Time
11. muse-lsl. https://github.com/alexandrebarachant/muse-lsl
12. Additional spectral/real-time-onset sources surfaced: eNeuro 0192-20.2020, eNeuro 0094-22.2022, PMC8516415, Nature s44271-025-00334-2, PubMed 25570439, PMC3048302, PMC4239919, PMC4828461, PMC6456684.
