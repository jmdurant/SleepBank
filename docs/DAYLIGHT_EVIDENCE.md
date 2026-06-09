# SleepBank — Daylight / Morning-Light Evidence Base

> **Purpose.** A durable, citable record of the evidence behind SleepBank's
> "daylight booster" and the morning-light nudge — for future presentation or a
> journal write-up. From a fact-checked deep-research pass (2026-06-09): 5 search
> angles, 23 sources fetched, 104 claims extracted, 25 adversarially verified
> (3 votes each), **20 confirmed / 5 killed**. Companion to `NAP_BENEFIT_EVIDENCE.md`
> and `EEG_EVIDENCE.md`.
>
> *Provenance note:* the workflow's auto-synthesis step returned degraded summary
> fields; this doc is reconstructed from the **verified-claim log + the surviving
> findings + the killed-claim list**, citing only numbers that passed verification.
> **Verify every citation against the primary source before any external use.**

---

## 1. Headline: the robust benefit is circadian anchoring, not a big acute jolt

The honest, evidence-weighted picture — and it refines our design:

- **Strong & well-quantified:** morning light **phase-anchors and advances the
  circadian clock** (Process C). This is the reliable benefit, and it shows up
  *downstream* — a steadier rhythm and better night sleep — more than as an
  instant morning alertness spike.
- **Real but modest and inconsistent:** **acute daytime alerting** from brighter
  light. Some controlled studies show it (1000 vs 200 lux improves alertness /
  vigilance); several show **null effects up to 2000 lux**. Daytime alerting is
  **weaker and less reliable than the well-known night-time alerting** of light.
- **Defensible target:** the 2022 expert consensus — **≥250 lux melanopic EDI**
  at eye level during the day, **outdoor daylight preferred** (a *minimum*, not an
  optimum).

So SleepBank should sell morning daylight as **"anchor your rhythm and sleep
better tonight,"** with only a *soft* claim about immediate alertness — and frame
its curve effect mainly on **Process C stability**, not a large same-moment lift.

## 2. Circadian phase effects of morning light (the robust evidence)

- **Phase-Response Curve (PRC):** light **after** your core-body-temperature
  minimum (CBTmin, ~2–3 h before habitual wake) **advances** the clock; light
  **before** it **delays**. The PRC **crosses over near CBTmin**. *(high, 3-0.)*
  - Khalsa 2003 (n=21): Type-1 PRC amplitude **5.02 h**.
  - St Hilaire 2012 (n=34): amplitude ~**2.2 h**; crossover ~3 h before / ~9 h
    after DLMO.
- **Dose / magnitude** (Ohashi 2023, n=27 healthy young adults): dim light drifts
  the clock **−0.24 h (~14 min) later**; **1 h of ~8000 lux advances it ~+0.18 h
  (~11 min)**; intensity–response r = −0.62. *(high, 3-0.)*
- **Practical translation:** because the effect anchors/advances the clock, the
  value is in **morning** light (after you wake) and in **regularity** — it counters
  the natural drift-later and supports earlier, more consolidated sleep.

## 3. Acute daytime alerting (real but modest — and genuinely mixed)

**Supportive:**
- Smolders & de Kort 2012 (N=32) / 2014 (N=28, 106 sessions): **1000 vs 200 lux**
  at the eye modestly improves subjective alertness, vitality, arousal, and delayed
  PVT. *(3-0.)*
- Pan 2025 (N=39, mean age ~21): brighter light → **fewer PVT lapses**; crucially,
  **short-wavelength was NOT superior to long-wavelength** — so the daytime effect
  is **not solely melanopic**. *(3-0.)*

**Null:**
- Lafrance 1998 (n=14): no alerting effect, and **no melatonin suppression** (day
  melatonin is already low). *(3-0.)*
- Lok 2018 (n=50, non-sleep-deprived): **null up to 2000 lux**. *(3-0.)*
- Lok 2019 (n=10): null even after 5 mg melatonin.

> **Net:** daytime bright light *can* nudge alertness/vigilance, but the effect is
> small, condition-dependent, and not guaranteed — **far less reliable than its
> night-time alerting**. Don't over-claim a same-moment buzz.

## 4. Threshold & target — evidenced vs popular

- **Evidenced target (Brown et al. 2022, PLoS Biology expert consensus):**
  daytime **≥250 lux melanopic EDI** at the eye (vertical plane ~1.2 m); **prefer
  broad-spectrum daylight**; it's a **minimum, not an optimum**. *(3-0.)* For
  context, indoor ~100–500 lux often falls short at the eye; outdoor daylight is
  ~10,000–100,000 lux — hence "go outside."
- **Popular but NOT precisely evidenced:** specific minute prescriptions
  ("10 minutes of morning sun," "view the sunrise"). The peer-reviewed consensus
  gives an **illuminance threshold**, not a validated minutes-per-day dose. Treat
  Huberman-style minute targets as reasonable *heuristics*, not established numbers.

## 5. Downstream sleep & the Apple metric (supporting; confirm specifics)

- **Field/downstream sleep:** sources surfaced on daytime/daylight exposure
  improving night sleep and mood (e.g., office workers with more daylight) — see
  Boubekri 2014 (JCSM) and others in References. *Specific effect sizes not
  re-verified here; confirm before citing numbers.*
- **Apple "Time in Daylight"** (`HKQuantityTypeIdentifier.timeInDaylight`, Apple
  Watch ambient-light sensor, watchOS 10 / iOS 17): a daily total of estimated
  daylight minutes. We already read it and **sub-segment by window** (morning vs
  afternoon vs evening — see `Sources/SleepBankCore/Daylight.swift`), since *when*
  the light lands is what matters. Validation of the metric itself is limited;
  treat it as a useful **relative** signal, not a calibrated lux measurement.

## 6. Over-claims to AVOID — killed in verification (0-3 / 1-2)

- ✗ "Daytime bright light has **no** stimulating effect even when sleep-deprived" —
  **killed (1-2).** (Don't claim light does nothing in the day.)
- ✗ "2000 lux **fails** to improve alertness in well-rested adults" — **killed (0-3).**
- ✗ "Systematic review: only 7/20 daytime studies positive → daytime alerting is
  unreliable" — **killed (1-2)** as worded.
- ✗ "200→1000 lux increased vitality with a 30-min exposure lasting ≥20 min" —
  **killed (0-3)** (too specific/over-stated).
- ✗ "Daytime alerting is **independent of melatonin** because none is produced in
  the day" — **killed (0-3)** as a mechanistic claim.

> The throughline: the **strong nulls AND the strong positives both got refuted** —
> daytime alerting is genuinely **mixed**. Our copy should reflect that, and lean on
> the **circadian** evidence, which is solid.

## 7. Honest contrast with caffeine

Caffeine **blocks adenosine** — it *masks* accumulated sleep pressure without
discharging it, and taken late it **impairs the subsequent night's sleep**. It does
**not** repay sleep debt. Morning daylight, by contrast, is a **natural** lever that
**anchors the clock and can improve tonight's sleep** — additive to, not borrowed
against, real rest. This is why SleepBank foregrounds light + naps and defers
caffeine (and would only ever show it honestly, as a mask with a cutoff-time
warning). See `NAP_BENEFIT_EVIDENCE.md` §4 for the sleep-debt framing.

## 8. How SleepBank applies this (design decisions)

- **Frame the booster as circadian anchoring**, not a big acute spike: morning
  daylight "anchors your rhythm and helps you sleep tonight." Any curve effect in
  `AlertnessRhythm` should be **modest** and act mainly on **Process C
  stability/phase**, not a large same-moment Y bump.
- **Morning window matters** — we already bucket Time in Daylight wake-relative
  (`DaylightDay.morning`). The nudge targets *getting outside in the morning*.
- **Target:** "aim to get outdoors in the morning" (toward ≥250 lux mEDI / real
  daylight). **Avoid a hard minutes prescription** in copy — the evidence supports
  an illuminance threshold and "more/earlier daylight," not a validated dose.
- **Honesty:** don't promise an instant alertness jolt from light; the durable,
  evidenced win is the rhythm and the night that follows.

---

## References

1. Khalsa SBS et al. *A phase response curve to single bright light pulses in human subjects.* J Physiol 2003. https://pmc.ncbi.nlm.nih.gov/articles/PMC2342968/
2. St Hilaire MA et al. *Human phase response curve to a 1-h pulse of bright white light.* J Physiol 2012. https://pmc.ncbi.nlm.nih.gov/articles/PMC3406389/
3. Ohashi/colleagues 2023 — daytime light intensity and circadian phase (dim vs 8000 lux, dose-response). https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10594521/
4. Revell/Czeisler-lineage PRC / CBTmin crossover. https://pmc.ncbi.nlm.nih.gov/articles/PMC2270041/
5. Smolders & de Kort 2012, *Daytime light exposure and feelings of vitality.* J Environ Psychol. https://www.sciencedirect.com/science/article/abs/pii/S0272494413001060 · 2014 follow-up https://www.sciencedirect.com/science/article/abs/pii/S0272494413000716
6. Lafrance et al. 1998 — daytime bright light, alertness, melatonin. https://pubmed.ncbi.nlm.nih.gov/9618002/
7. Lok et al. 2018, *Light, alertness, and alerting effects of white light* (null ≤2000 lux daytime). J Biol Rhythms. https://journals.sagepub.com/doi/10.1177/0748730418796036
8. Lok et al. 2019 — daytime light after exogenous melatonin (null). https://pmc.ncbi.nlm.nih.gov/articles/PMC6767594/
9. Pan et al. 2025 (N=39) — daytime light, PVT lapses, wavelength. Sci Rep. https://www.nature.com/articles/s41598-025-29154-4
10. Brown TM et al. 2022 — *Recommendations for daytime, evening, and night-time light exposure* (≥250 lux mEDI daytime consensus). PLoS Biology. https://journals.plos.org/plosbiology/article?id=10.1371%2Fjournal.pbio.3001571 · https://pmc.ncbi.nlm.nih.gov/articles/PMC8929548/
11. Boubekri et al. 2014 — daylight exposure in office workers and sleep. JCSM. https://jcsm.aasm.org/doi/full/10.5664/jcsm.3780
12. Daylight exposure & sleep (Sleep Health 2017). https://www.sleephealthjournal.org/article/S2352-7218(17)30041-4/abstract
13. Daytime light & sleep/health (2022). https://pubmed.ncbi.nlm.nih.gov/36058557/
14. Apple — *See your time in daylight on Apple Watch.* https://support.apple.com/guide/watch/see-time-in-daylight-apd3ab22534c/watchos
15. Light exposure & sleep validation work. https://academic.oup.com/sleep/article/48/4/zsae230/7815486 · https://pmc.ncbi.nlm.nih.gov/articles/PMC9541543/ · https://journals.sagepub.com/doi/10.1177/07487304211013995
16. ⚠️ Popular/blog (flagged, not peer-reviewed): Huberman Lab, *Using light for health.* https://www.hubermanlab.com/newsletter/using-light-for-health
