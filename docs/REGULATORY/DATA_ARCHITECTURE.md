# SleepBank — Data Architecture & Research Governance

> **Purpose.** How user data is stored and how it (optionally, with consent) becomes
> research-usable. The short version: **on-device-first; nothing leaves the phone
> without explicit consent; research data flows to a backend the study team controls
> — not to CloudKit.** Companion to `FDA_PATH.md` and `PILOT_PROTOCOL_SYNOPSIS.md`.
>
> **Not legal advice.** IRB, HIPAA, and consent specifics must be set with regulatory
> counsel and the academic partner. Items marked **[SEAM]** are integration points
> deliberately left as stubs until an IRB protocol + backend exist.

---

## 1. The layers (they are not either/or)

| Layer | Tech | Role |
|---|---|---|
| **Local store** | UserDefaults / files (current) | Source of truth; everything works offline, private by default |
| **Collection + consent** | ResearchKit-shaped flow (native today) | *How* we legally collect for research |
| **Per-user sync** *(optional, product)* | **CloudKit private DB** | Sync the user's *own* history across *their* devices |
| **Research backend** | Partner REDCap / MyDataHelps **[SEAM]** | Where consented, de-identified data lands for analysis |

**CloudKit is not the research store.** The CloudKit *private* database is the user's
own iCloud container — the developer cannot read it server-side, so you can't pull a
cohort out of it. The *public* database is shared across all users and is
inappropriate for health data. CloudKit's only legitimate role here is a product
convenience (a user's data following their devices), never the research pipeline.

## 2. What actually makes data research-usable
Not the storage brand — governance, in order:
1. **Informed consent** (the legal gate) — `ResearchConsentStore` + `ResearchView`
   today; a ResearchKit `ORKConsentDocument` at study time. **[SEAM]**
2. **IRB approval** — rides on the academic partner (Duke/UNC/Queens).
3. **A controlled backend** the study team can analyze — REDCap (partner-hosted, under
   their HIPAA coverage) or MyDataHelps/CareEvolution. **[SEAM]**
4. **De-identification** — exports carry only a random `participantID`; name/identity
   never leave the device. Any re-identification key is held separately by the study.
5. **Structured, timestamped, exportable records** — already true (the questionnaire
   stores + `NapSessionRecorder`/`NapFiles` traces).

## 3. What's scaffolded now (this commit)
- **`ResearchConsentStore`** — consent state + versioning; mints a pseudonymous
  `participantID` (UUID) on consent; supports withdrawal.
- **`ResearchView`** — a ResearchKit-shaped consent flow (overview → data → privacy →
  voluntary/withdrawal → agreement) and, once consented, a status + export panel.
  Reached via Settings → "Research participation."
- **`ResearchExporter`** — builds a **de-identified JSON** of the validated-instrument
  data (Epworth, PSAS, KSS) + chronotype/sleep-need covariates, keyed by
  `participantID`. **Gated on current consent.** Output goes to a share sheet today.

## 4. The seams to wire at study time
- Replace the native consent flow with **ResearchKit `ORKConsentDocument` +
  `ORKTaskViewController`** (the questionnaires become `ORKFormStep`s). **[SEAM]**
- Replace the share-sheet hand-off in `ResearchView`/`ResearchExporter` with a
  **direct upload to the partner backend** (REDCap API / MyDataHelps SDK), under the
  IRB-approved data-use agreement. **[SEAM]**
- Add the nap feature/EEG traces (`NapFiles`) to the export bundle (already structured
  and timestamped for joining).
- Optional product nicety: **CloudKit private DB** to sync the user's own history —
  independent of, and never substituting for, the research backend.

## 5. Principles
- **On-device-first.** Default to local; transmit only on explicit consent.
- **De-identified by construction.** The export schema has no name/contact/device id.
- **Consent is reversible and versioned.** Withdrawal stops future sharing; a material
  consent-text change requires re-consent.
- **Governance rides on the partnership.** A solo developer can't shoulder HIPAA for
  identifiable data; the covered-entity partner's IRB + systems carry it.
