# SleepBank — FDA / Regulatory Strategy

> **Purpose.** A durable, citable record of *which clearable medical-device an
> app like SleepBank could become*, the cleanest pathway, and the evidence we
> need to bank now to keep that door open — without forfeiting the general-wellness
> exemption we ship under today. Retargets the regulatory framework already worked
> out in the companion SexKit project (`SexKit/CLINICAL_RATIONALE.md`) to sleep.
> Companion to `NAP_BENEFIT_EVIDENCE.md`, `EEG_EVIDENCE.md`, and `DAYLIGHT_EVIDENCE.md`.
>
> **This is strategy, not legal advice.** Verify every classification, predicate,
> and claim against FDA guidance and regulatory counsel before any submission or
> external use. Terminology: FDA *clears* a 510(k), *authorizes/grants* a De Novo,
> and *approves* only a PMA — "FDA-approved app" is almost always a clearance or
> a De Novo authorization.

---

## 1. The line FDA actually draws: it's the claim, not the tech

Under the FD&C Act §201(h), software becomes a *device* the moment its **intended
use** is to diagnose, treat, cure, mitigate, or prevent a **disease**. FDA's
**General Wellness: Policy for Low Risk Devices** guidance (2016) carves out
low-risk products that promote "a general state of health" or a "healthy activity."

| What we say | Classification | Friction |
|---|---|---|
| "Time your naps, feel more rested and alert, wind down at night" | **General wellness** — no FDA | Ship today (current state) |
| "Detects your sleep stages / screens for a sleep disorder / treats your insomnia" | **Medical device** | Clearance + clinical evidence required |

The same code is either one depending on the marketing copy. **The single most
important operational rule: do not make a device claim in app-store copy, UI, or
marketing** until and unless we are pursuing the matching clearance — doing so
forfeits the wellness exemption *without* giving us the validation that would
justify a clearance.

---

## 2. The three classifications SleepBank could qualify for

Mirrors the SexKit framing (biofeedback / DTx / CDS), retargeted to sleep and
ranked by path quality.

| Classification | SleepBank mechanism | Cleared analogues / predicates | Path quality |
|---|---|---|---|
| **Biofeedback device** | `BreathingPacer` — HR/HRV-informed paced 4-7-8 breathing to lower pre-sleep arousal | **Resperate** (paced-breathing device, cleared); HRV-biofeedback and pelvic-floor/cardiac-rehab biofeedback systems | **Cleanest** — settled Class II 510(k) space, low risk, deep predicate base |
| **Clinical Decision Support (CDS)** | Muse-EEG sleep staging + alertness curve as an objective report for a clinician | EnsoData (sleep-scoring AI), Beacon Biosignals (few-channel EEG analysis) | Middle — predicates exist; needs PSG-validation study on our montage |
| **Digital Therapeutic (DTx)** | CBT-I-style insomnia or shift-work-disorder behavioral program | Somryst (CBT-I, De Novo, Rx); EndeavorRx (pure-software, De Novo) | Heaviest — prescription + reimbursement-dependent (see §6 risk) |

### Why biofeedback is the lead path
Paced-breathing / HRV biofeedback is one of the most well-trodden, lowest-risk
device categories that exists — a mature **Class II 510(k)** space with textbook
predicates (Resperate is a cleared paced-breathing device for the same
mechanism). The `BreathingPacer` we already ship *is* that mechanism. This is a
far gentler door than a novel EEG-staging clearance, and unlike the DTx route it
is **over-the-counter / consumer-distributable** with no prescription or
reimbursement dependency — the clearance is a credibility + capability unlock,
not our revenue model.

### Predetermined Change Control Plan (PCCP) — the modern enabler
FDA now lets us pre-authorize a plan to keep **updating our ML model** post-
clearance without re-filing each time. Because SleepBank's thesis is *calibrate,
don't copy; the path is ML (YASA/U-Sleep)*, a PCCP is the difference between a
frozen model and a living one — it removes the historical reason ML apps avoided
clearance. Bake a PCCP into any staging/biofeedback submission.

---

## 3. Evidence base — what a clearance lives or dies on

A clearance for any of the above stands on **clinical validation**, and for sleep
that means the gold standard:

- **PSG (polysomnography) ground truth.** The one thing we cannot retrofit. The
  highest-leverage near-term move is recording even a small cohort with
  *simultaneous Muse + PSG* so our staging/onset output has a labeled comparator.
  Our `NapSessionRecorder` + raw-EEG + CreateML export pipeline is already the
  right substrate; what it lacks is the PSG label.
- **Validated self-report instruments** (§4) for symptom/outcome endpoints.
- **ResearchKit scaffold** (lift wholesale from SexKit's planned use): informed-
  consent flows, IRB-compliant audit trails, standardized export.
- **Controlled outcome studies** for any efficacy claim — e.g., biofeedback-paced
  wind-down vs unguided on sleep-onset latency; nap-timing vs ad-lib on daytime
  alertness (Karolinska/Epworth endpoints).

---

## 4. Questionnaires & Apple Health (HealthKit) reality — verified through iOS 27

**What HealthKit gives us natively.** Since **iOS 18 (WWDC24)** HealthKit exposes
*scored assessments* as first-class types our app can **read and write**:

- **PHQ-9** (depression, 9-item, Pfizer) — `HKScoredAssessment` / PHQ-9 type
- **GAD-7** (anxiety, 7-item, Pfizer) — `HKScoredAssessment` / GAD-7 type
- **State of Mind** (`HKStateOfMind`) — momentary/daily mood logging

Apple stores the per-question answers plus the computed risk band, and requires
administration "in accordance with Pfizer's standards." Available to ages 13+,
labeled informational (not a diagnosis), validated only in certain
countries/languages.

**The gap that matters for us:** through **iOS 26** (whose headline HealthKit
addition was the Medications API) and **iOS 27** (workout zones), Apple has added
**no sleep-specific scored assessment** — there is **no native Epworth, PSQI,
ISI, or Karolinska type** in HealthKit. Only PHQ-9 and GAD-7 exist as built-in
questionnaires.

**Therefore our questionnaire plan:**

| Instrument | Measures | Source | How we handle it |
|---|---|---|---|
| **Epworth Sleepiness Scale (ESS)** | Daytime sleepiness — *the* most on-thesis instrument for a nap/alertness app | Self-administer (ResearchKit survey or SwiftUI form); store in our own model | No native HK type — keep in-app |
| **Pittsburgh Sleep Quality Index (PSQI)** | Sleep quality (last month) | Self-administer; store in-app | No native HK type |
| **Insomnia Severity Index (ISI)** | Insomnia severity / DTx endpoint | Self-administer; store in-app | No native HK type |
| **Karolinska Sleepiness Scale (KSS)** | Momentary sleepiness (pre/post nap) | Self-administer; store in-app | No native HK type — pairs with the alertness curve |
| **PHQ-9 / GAD-7** | Depression / anxiety comorbidity (huge sleep confounders) | **HealthKit read** (if user took them in Health), and **write** if we administer | Native HK type — use the API |

Net: administer the sleep instruments ourselves (Epworth first — it literally
measures the daytime sleepiness our product targets), and use the HealthKit
PHQ-9/GAD-7 API to pull mood comorbidity context and to write back any we
administer. Watch future WWDC releases for a native sleep-assessment type; adopt
it if/when Apple ships one.

---

## 5. Claims guardrails — do / don't (keeps the wellness exemption intact)

**Do** (wellness-safe):
- "Helps you fall asleep faster," "feel more rested and alert," "wind down,"
  "paced breathing to relax," "track how your naps affect your alertness."
- Frame questionnaires as "track your own sleep quality over time."

**Don't** (triggers device status without a matching clearance):
- "Diagnoses / screens for / detects insomnia, apnea, or any sleep disorder."
- "Clinical-grade sleep staging," "medical sleep analysis."
- "Treats insomnia," "therapy for a sleep disorder."
- Presenting an Epworth/PSQI score with an interpretive disease cutoff
  ("your score indicates a sleep disorder") — report the score, not a diagnosis.

---

## 6. The real risk isn't FDA — it's reimbursement

The cautionary precedent: **Pear Therapeutics** (maker of Somryst, the cleared
CBT-I insomnia app, and reSET) **went bankrupt in 2023** — not because it
couldn't get cleared, but because **prescription-digital-therapeutic
reimbursement never materialized**. Payers wouldn't pay; prescribing was clunky.

Implication for SleepBank: the **DTx/prescription** route is the Pear trap and
should be avoided unless we have a payer or health-system go-to-market. The
**biofeedback (OTC) + CDS** routes are revenue-independent of reimbursement and
are the right bet for an independent app.

---

## 7. Recommendation & phased roadmap

1. **Now — ship general wellness.** Keep claims clean (§5). This is the current
   product and the lowest-friction path.
2. **Now — engineer for optionality.** Add the validated questionnaires (Epworth
   first) via a ResearchKit/SwiftUI survey; wire the HealthKit PHQ-9/GAD-7
   read/write API; keep banking `NapSessionRecorder` traces. None of this changes
   our wellness posture; all of it is future-clearance substrate.
3. **If/when pursuing clearance — lead with biofeedback.** 510(k) on the
   `BreathingPacer` against a paced-breathing predicate (Resperate-class), with a
   **PCCP** for the ML, and a small controlled wind-down study. Bounded claim,
   OTC distribution, low risk class.
4. **Later — CDS staging add-on.** Only after a Muse-vs-PSG validation set
   exists; ride an EnsoData/Beacon-class predicate.
5. **Avoid** the prescription-DTx route unless a reimbursement/health-system
   partner is in hand (Pear lesson, §6).

> Bottom line: the clearable *app* in SleepBank is the **biofeedback breathing
> engine**, not the staging model — predicate-backed, low-risk, OTC, no
> reimbursement dependency. Ship wellness now; the clearance becomes a feature of
> a product that already stands on its own.
