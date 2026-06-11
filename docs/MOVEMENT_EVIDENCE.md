# SleepBank — Movement / Acute-Exercise Evidence Base

> **Purpose.** The evidence behind the curve's *movement* lift — the `arousal()`
> walk/workout coefficients and the `morningActivityDose` in `AlertnessRhythm`, and
> the "Movement" row in the Alertness Score explainer. Now at the same rigor as
> `NAP_BENEFIT_EVIDENCE.md` and `DAYLIGHT_EVIDENCE.md`.
>
> Compiled from a fact-checked deep-research pass (2026-06-11): 5 angles, 20 sources
> fetched, 90 claims extracted, 25 adversarially verified (3 independent votes each),
> 19 confirmed / 6 killed. Confidence noted per finding. **Verify every citation
> against the primary source before any external/clinical/regulatory use.**

---

## 1. Headline: a small lift that lands *after* you finish — and a brisk walk barely moves it

A single bout of aerobic exercise produces a **small acute improvement in alertness
and reaction time that appears AFTER the bout ends, not during it**, and is carried
by **faster reaction time, not accuracy**. The effect is **intensity-graded** (more
vigorous → larger), and a **brisk walk specifically is close to null** for cognition
— so our old "a walk is worth half a workout" *under-stated* the gap (the walk floor
is lower than half). Exercise is also a **real but weak circadian zeitgeber** (~⅓ the
strength of bright light). It is a different transaction from a nap: an arousal/
performance lift, **not** a discharge of homeostatic sleep pressure.

## 2. Acute alerting effect — magnitude, timing, decay

- **During vs after:** the benefit is a **post-bout** effect. *Lambourne &
  Tomporowski 2010* (Brain Research, PMID 20381468): **d = −0.14 during** exercise
  (i.e. slight impairment) vs **+0.20 after**. *Garrett et al. 2024* (Communications
  Psychology, 113 studies): **during g = 0.02 (null)** vs **post g = 0.16**; high
  intensity impairs *during* (14/20 studies) but clears within **~6 min** of stopping.
  *(high confidence, 3-0)*
- **What improves:** reaction time, not accuracy — cognition **g ≈ 0.13**, **RT
  g ≈ 0.27**, accuracy null (Garrett 2024; Cantelon & Giles 2021, Frontiers in
  Psychology). *(high)*
- **On vigilance (PVT) specifically** — the measure closest to "alertness":
  moderate exercise **speeds PVT RT ~19 ms / ~5.5%** and **prevents the within-task
  vigilance decrement**, while **light exercise does not**; in head-to-heads it beat
  a sitting nap and blue light (Aguirre-Berrocal 2018, n=24; Du & Zhao 2022, Sci Rep,
  n=74; the exercise-vs-nap study PMC8987024). *(medium — small samples)*
- **Decay:** **no clean decay constant exists.** Two specific decay claims (benefit
  fades by ~1 h; intensity-dependent decay by ~2 h) were **killed (0-3)** in
  verification. Treat any fade time as a modeling placeholder, not an established fact.

## 3. Intensity & duration dose-response

- **Intensity-graded, monotonic — NO inverted-U.** Executive-function RT scales with
  intensity (moderate **−0.19**, vigorous **−0.34**, HIIT **−0.61**; Oberste 2019,
  PMC6881262, overall g = −0.26, **light = ns**). The **inverted-U hypothesis was
  refuted (0-3)**. *(high)*
- **A brisk walk ≈ null for cognition** (Garrett 2024: **walk g = 0.04, BF = 0.07**),
  while cycling 0.21, vigorous 0.19, **HIIT 0.73** drive the pooled effect. So the
  *type* matters and a gentle walk sits near the floor. **This corrects our model:**
  a walk should be a *small* lift, and clearly less than half a workout. *(high)*
- **Caveat — these are COGNITION effect sizes, not subjective sleepiness (KSS/VAS).**
  Whether a brisk walk relieves *felt* sleepiness despite a null cognitive-RT effect
  is an open question — plausible via arousal, but not established.
- **Duration (6–60 min):** comparable acute benefits across bout lengths in the
  moderate range; longer/harder bouts may slightly impair *complex* cognition (a
  duration→memory effect was only weakly supported, 1-2).

## 4. Mechanism — and why it's not a nap

The lift is attributed to **arousal (catecholamines/noradrenaline), core-temperature
rise, and cerebral blood flow**, with BDNF more relevant to lasting/learning effects.
But mechanism is **contested** — in at least one study physiological arousal did **not**
correlate with the cognitive benefit (Ludyga 2020, n=16). Crucially, exercise is an
**arousal/performance** lever, **not** a discharge of sleep pressure — so movement and
a nap are *different transactions* (the nap pays down Process S; the bout transiently
raises arousal). The exercise-vs-nap study (PMC8987024) found a bout beat a sitting
nap for alertness in nap-deprived adults.

## 5. Exercise as a circadian zeitgeber (Youngstedt PRC)

- **Validated, but small.** *Youngstedt et al. 2019* (J Physiol, 10.1113/JP276943,
  n=101) produced a human **exercise phase-response curve**: exercise at **~7 am and
  ~1–4 pm phase-ADVANCES** the clock; exercise at **~7–10 pm phase-DELAYS** it.
  Shifts are **sub-hour** and roughly **⅓ the magnitude of bright light**. Evening
  melatonin-rhythm delay on the order of **−0.45 to −0.62 h**. *(high, 3-0)*
- **Implication:** morning movement *is* a daily timing cue parallel to morning light
  — but a **weaker** one. Our model treating morning movement on par with light over-
  weighted it; it should be **smaller than the light credit**. Whether the morning
  benefit is partly cortisol/circadian vs pure acute arousal is **not quantified**.

## 6. Evening / too-close-to-bed cost

Evening exercise is **mostly fine** for sleep — the meta-analytic picture (Stutz et al.
2019, Sports Medicine, 10.1007/s40279-018-1015-0) is that evening exercise does not
generally harm sleep **except vigorous exercise ending within ~1 h of bed**, which can
delay onset and raise arousal. Combined with the PRC, **late-evening exercise also
phase-delays the clock (~0.5 h)** — so it keeps the evening more alert. This validates
(directionally) our model's "exercise placed late keeps the evening elevated" behavior,
though the magnitude is modest.

## 7. What we changed in the model (`AlertnessRhythm`)

| Parameter | Was | Now | Why |
|---|---|---|---|
| `arousal()` walk coef | 0.10 | **0.06** | A brisk walk is near the floor (cognition g≈0.04); keep a small subjective/vigilance lift but well below a workout. |
| `arousal()` workout coef | 0.21 | **0.20** | Moderate-to-vigorous is the real driver; workout now ~3× a walk (was 2×), matching the intensity gradient. |
| `morningActivityPeak` | 0.10 | **0.06** | Exercise's circadian zeitgeber is ~⅓ of light's (0.12), so morning movement's anchor credit must sit *below* the light credit, not on par. |

Unchanged and still defensible: the acute lift **builds then peaks shortly after the
bout** (matches the post-bout finding) and **fades over ~1.5 h** (a placeholder — no
clean decay constant exists, flagged above). The in-app magnitude stays **"Mild boost ·
short-lived,"** which the evidence supports.

## 8. Open questions (a future pass / our own study could fill)
1. Does a brisk **walk** relieve **subjective** sleepiness despite a null cognitive-RT effect?
2. The **decay time constant** for a walk vs a workout — no clean curve exists.
3. Is the **morning** benefit partly circadian/cortisol vs pure acute arousal?
4. Mechanism split — core-temp vs blood-flow vs catecholamine vs BDNF — remains contested.

## 9. Key sources
- Garrett et al. (2024), *Communications Psychology* — https://www.nature.com/articles/s44271-024-00124-2
- Lambourne & Tomporowski (2010), *Brain Research* — PMID 20381468 (during vs after)
- Oberste et al. (2019) — https://pmc.ncbi.nlm.nih.gov/articles/PMC6881262/ (intensity gradient)
- Moreau & Chou (2019), *Perspectives on Psych. Science* — https://journals.sagepub.com/doi/10.1177/1745691619850568
- Youngstedt et al. (2019), *J Physiol* — https://physoc.onlinelibrary.wiley.com/doi/full/10.1113/JP276943 (exercise PRC)
- Aguirre-Berrocal 2018 — https://pmc.ncbi.nlm.nih.gov/articles/PMC6295642/ ; Du & Zhao 2022 — https://www.nature.com/articles/s41598-020-65197-5 ; exercise-vs-nap — https://pmc.ncbi.nlm.nih.gov/articles/PMC8987024/
- Stutz et al. (2019), *Sports Medicine* — https://link.springer.com/article/10.1007/s40279-018-1015-0 (evening exercise & sleep)
- Cantelon & Giles (2021), *Frontiers in Psychology* — https://doi.org/10.3389/fpsyg.2021.653158
