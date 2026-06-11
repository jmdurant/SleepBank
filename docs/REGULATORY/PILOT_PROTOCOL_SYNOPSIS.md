# SleepBank — Pilot Clinical Protocol Synopsis

> **DRAFT v0.1 — 2026-06-11.** A mechanism/pilot study to estimate the acute effect
> of device-guided paced breathing on pre-sleep arousal, and to power a later
> pivotal study. Written to be handed to a biostatistician and a psychology /
> sleep-medicine faculty collaborator for pressure-testing.
>
> **Not regulatory or legal advice.** Items marked **[VERIFY]** are my best guess
> and MUST be confirmed against the live source (FDA database/guidance, the
> instrument's terms, your IRB) before use. Companion to `../FDA_PATH.md`.

---

## 1. Title
Acute effect of haptic-guided paced breathing on pre-sleep arousal in high-stress
adults: a randomized, sham-controlled, within-subject crossover pilot.

## 2. Sponsor / Investigators
- **Sponsor / Device owner:** James DuRant, MD (SleepBank).
- **Site PI:** *(faculty collaborator — Psychology or Sleep Medicine)* — required;
  the sponsor's faculty status creates a conflict-of-interest and coercion
  sensitivity (see §15), so the day-to-day PI and recruiters should sit outside
  the sponsor's evaluative authority.

## 3. Background & rationale (brief)
Slow paced breathing with an extended exhale increases parasympathetic activity
and lowers acute arousal; this is the mechanism behind cleared device-guided
breathing products. SleepBank's `BreathingPacer` delivers a haptic-paced 4-7-8
cadence (inhale 4 s / hold 7 s / exhale 8 s). This pilot tests whether a single
guided session reduces *acute pre-sleep arousal* more than a sham cadence — the
device function we intend to label, and the basis for a biofeedback 510(k).
- **Predicate concept [VERIFY]:** device-guided slow-breathing relaxation aid
  (Resperate-class). Confirm the exact cleared device, K-number, and its
  indication wording in the FDA 510(k) database before citing it as predicate.

## 4. Device & intended use (the claim this study supports)
- **Device:** SleepBank guided-breathing feature (software + haptics on iPhone/Apple Watch).
- **Intended use (chosen framing):** *For adults experiencing situational pre-sleep
  arousal or stress that interferes with winding down, to guide slow paced breathing
  to reduce acute pre-sleep arousal.* A **relaxation** claim — deliberately **not** a
  claim to diagnose, treat, or prevent insomnia or any sleep disorder (see
  `FDA_PATH.md` §5). This framing is why a high-stress sample (e.g., trainees) is
  *appropriate*, not merely convenient.

## 5. Objectives
- **Primary:** Estimate the acute effect of active vs sham guided breathing on
  pre-sleep arousal (effect size + variance) to power a pivotal study.
- **Secondary:** Effect on autonomic markers (HRV/HR) and momentary sleepiness;
  feasibility (adherence to target cadence, acceptability, dropout).

## 6. Endpoints
- **Primary:** Within-subject difference between conditions in the change in
  **Pre-Sleep Arousal Scale (PSAS)** total from immediately pre- to immediately
  post-session — i.e. Δ(active) − Δ(sham). *(Somatic subscale as a key secondary,
  since paced breathing acts most directly on somatic arousal.)*
- **Secondary:**
  - HRV (RMSSD) and heart rate change, pre→post, active vs sham (objective corroboration).
  - **Karolinska Sleepiness Scale (KSS)** change.
  - A license-free visual-analog **calm/tension** rating *(avoid STAI — copyrighted)* **[VERIFY instrument licensing]**.
  - Adherence: measured respiration rate vs target during the session.
  - Acceptability (short post-session questionnaire), adverse events.

## 7. Design
Randomized, sham-controlled, **within-subject crossover** (each participant is
their own control — the most powerful, smallest-n design for an acute effect).
- **Two conditions, counterbalanced order:** *Active* (4-7-8 haptic pacing, ~10 min)
  vs *Sham*. **Washout** ≥ 24 h between conditions (separate visits preferred) to
  avoid carryover **[VERIFY adequacy with biostatistician]**.
- **Arousal induction (to defeat the floor effect):** Because a relaxed sample has
  little arousal to reduce, each session begins with a brief standardized stressor
  (e.g., time-pressured serial subtraction or a validated lab stress task) to lift
  baseline arousal off the floor before the intervention. *(Less critical in a
  high-stress sample, but standardizes the starting point.)* **[VERIFY task choice]**
- **Per-session flow:** consent/setup → baseline rest + baseline measures →
  arousal induction → **intervention (active or sham)** → immediate post measures →
  brief recovery. Target ~30–40 min/visit.

## 8. Sham comparator (the make-or-break element)
The sham must control for attention, posture, time, device contact, and
expectancy, while lacking the therapeutic mechanism (the *extended exhale*).
- **Proposed sham [VERIFY with collaborator]:** haptic cues at the participant's
  own resting respiratory rate with a **symmetric** in/out pattern (no exhale
  extension) — same device, same attention, no parasympathetic-biasing long exhale.
- Without a credible sham, the result reads as a relaxation/placebo effect and will
  not support a device-specific claim.

## 9. Population & eligibility
- **Target:** high-stress adults reporting difficulty winding down (the intended-use
  population). A trainee sample (e.g., medical students/residents) fits this framing.
- **Inclusion [VERIFY/refine]:** age ≥ 18; self-reported situational pre-sleep
  arousal / difficulty winding down (optionally a screening PSAS above a threshold);
  able to follow paced breathing.
- **Exclusion [VERIFY/refine]:** diagnosed sleep disorder under active treatment;
  significant cardiac/respiratory or psychiatric condition; current sedative/
  hypnotic/benzodiazepine use; pregnancy *(consider)*; conditions where paced
  breathing is contraindicated.

## 10. Sample size (PLACEHOLDER — biostatistician to finalize)
Illustrative only: a within-subject crossover detecting a moderate paired effect
(Cohen's d_z ≈ 0.5) at 80% power, two-sided α = 0.05 → ~**34 completers**; enroll
~**40** to cover dropout. The *real* number comes from this pilot's observed effect
and variance. **[VERIFY — do not treat as final.]**

## 11. Randomization & blinding
- Computer-generated, counterbalanced **condition order**; allocation concealed.
- **Single-blind:** participant naïve to which cadence is "therapeutic"; **outcome
  assessor and analyst blinded** to condition. Full double-blind is impractical
  (cadences differ), so blinding rests on participant naïveté + blinded assessment.

## 12. Statistical analysis (brief)
- Primary: linear mixed model (or paired t-test) on the within-subject condition
  difference in pre→post PSAS change; period and order as covariates.
- Per-protocol and intention-to-treat sets; report effect size + 95% CI (this is a
  *pilot* — estimation, not confirmatory hypothesis testing).
- Secondary endpoints analyzed analogously; no multiplicity-driven claims at pilot stage.

## 13. Procedures & data
- Source data captured per visit; device session logs (cadence, adherence) exported
  from the app. Data handling and retention per IRB and any sponsor–site agreement.

## 14. Risk determination
- **Non-Significant Risk (NSR) [VERIFY — IRB makes the determination].** Non-invasive
  guided breathing + questionnaires + optional surface HR sensing presents no
  significant risk; an NSR device study needs **IRB approval but not a full FDA IDE**
  (abbreviated requirements). The IRB must concur on NSR.

## 15. Regulatory & ethics
- IRB approval before any enrollment; informed consent emphasizing voluntariness.
- **Coercion/COI mitigation:** sponsor (faculty) must not recruit, consent, or
  evaluate students under his authority; use neutral recruiters and a non-sponsor PI.
- Run to FDA-usable rigor (pre-specified protocol, consent, device accountability,
  clean source data) so the data can support a later submission — see `FDA_PATH.md`.

## 16. Recruitment-route decision note
| Route | Pros | Cons |
|---|---|---|
| **Psych subject pool** (e.g., Queens Univ. of Charlotte) | Fast, cheap recruitment via course-credit pool; psych labs run exactly this design; often have HR/HRV gear | Low baseline arousal → leans hard on the induction task; young-adult general sample, weaker intended-use match |
| **UNC trainees (med students/residents)** | High baseline arousal → bigger signal *and* matches the "stressed adults" intended use; research-heavyweight IRB/biostat/sleep infrastructure for the later pivotal | No subject pool → recruitment is the bottleneck; schedule confounders (call/exams) add variance; sharper COI/coercion handling needed |

**Recommendation:** align the *sample to the intended use*. If the label is "stressed
adults who struggle to wind down," a trainee sample is appropriate and yields a
stronger signal — but expect harder recruitment and handle COI carefully. A
pragmatic hybrid: run the quick mechanism **pilot** wherever recruitment is fastest,
and align the **pivotal** study population to the final intended-use label at the
research-heavy site.

## 17. Open questions to take to the FDA Pre-Submission
- Is a **daytime-lab arousal proxy** acceptable to support a *pre-sleep* relaxation
  claim, or does FDA expect an at-bedtime endpoint? **[Pre-Sub question]**
- Confirm **predicate** and that the proposed indication is a 510(k) (vs De Novo). **[VERIFY]**
- Confirm **NSR** posture and any cybersecurity/SaMD documentation expectations. **[VERIFY]**

## 18. Limitations
Pilot (estimation, not confirmatory); lab session is a controlled proxy for the
real bedtime context; single-blind; convenience sample. These are acceptable for a
pilot whose job is to de-risk and power the pivotal study — not to clear the device.
