//
//  AlertnessEvidence.swift
//  SleepBank
//
//  The evidence behind the "What shapes this" explainer: each factor's directional
//  magnitude + duration, and the numbered references that back the claims (shown as
//  superscripts, with a references list the user can tap through — the f.lux move,
//  so the numbers aren't asserted, they're sourced). Magnitudes are summarized from
//  our vetted evidence docs (docs/NAP_BENEFIT_EVIDENCE.md, docs/DAYLIGHT_EVIDENCE.md);
//  they're directional, not personalized measurements.
//

import SwiftUI

enum AlertnessEvidence {

    struct Reference: Identifiable {
        let id: Int          // citation number shown as a superscript
        let text: String     // author (year), journal — the human-readable citation
        let url: URL?        // tap-through (PubMed/DOI)
    }

    struct Factor: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let magnitude: String   // e.g. "Moderate boost · lasts ~1–3 h"
        let claim: String
        let cites: [Int]
    }

    /// The numbered sources. Links point at a stable PubMed search (or DOI) for the
    /// citation so they always resolve — verify against the primary source before any
    /// external/clinical use.
    static let references: [Reference] = [
        Reference(id: 1,
                  text: "Brooks & Lack (2006), Sleep — afternoon-nap dose–response (5/10/20/30 min); a 10-min nap lifts alertness ~155 min.",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Brooks+Lack+afternoon+nap+sleep+restriction+2006")),
        Reference(id: 2,
                  text: "Rosekind et al. (1995) — NASA planned cockpit rest; a ~26-min nap improved alertness and vigilance.",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Rosekind+planned+cockpit+rest+alertness+1995")),
        Reference(id: 3,
                  text: "Garrett et al. (2024), Communications Psychology — acute-exercise meta-analysis: benefit is post-bout, small, RT-driven (a brisk walk barely moves it).",
                  url: URL(string: "https://www.nature.com/articles/s44271-024-00124-2")),
        Reference(id: 7,
                  text: "Youngstedt et al. (2019), J Physiol — human exercise phase-response curve (a circadian cue ~⅓ the strength of light).",
                  url: URL(string: "https://physoc.onlinelibrary.wiley.com/doi/full/10.1113/JP276943")),
        Reference(id: 4,
                  text: "Wright et al. (2013), Current Biology — natural light–dark exposure entrains the circadian clock.",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Wright+entrainment+natural+light+dark+2013")),
        Reference(id: 5,
                  text: "Scheer & Buijs (1999), J Clin Endocrinol Metab — 1 h of morning bright light raised the cortisol awakening response ~35%.",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Scheer+Buijs+light+cortisol+1999")),
        Reference(id: 6,
                  text: "Borbély (1982), Human Neurobiology — the two-process model: sleep pressure (S) + circadian rhythm (C).",
                  url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Borbely+two+process+model+sleep+regulation+1982")),
    ]

    static let factors: [Factor] = [
        Factor(icon: "bed.double.fill", tint: .indigo, title: "Last night's sleep",
               magnitude: "Sets the whole curve",
               claim: "How much you slept sets how high your curve sits today — a short night lowers it all day.",
               cites: [6]),
        Factor(icon: "moon.zzz.fill", tint: .indigo, title: "Naps",
               magnitude: "Moderate boost · lasts ~1–3 h",
               claim: "A 10–20 min power nap restores subjective alertness within minutes; the lift lasts roughly 1–3 hours, without erasing real sleep debt.",
               cites: [1, 2]),
        Factor(icon: "figure.walk", tint: .green, title: "Movement",
               magnitude: "Mild boost · short-lived",
               claim: "A bout of activity gives a small lift in alertness and reaction time once you finish — a harder effort more than an easy walk — and gently nudges your body clock.",
               cites: [3, 7]),
        Factor(icon: "sun.max.fill", tint: .orange, title: "Morning light",
               magnitude: "Mild now · strong all-day anchor",
               claim: "The immediate alertness bump is modest, but morning light reliably anchors your body clock and amplifies your morning cortisol rise — the durable payoff is steadier rhythm and better sleep tonight.",
               cites: [4, 5]),
        Factor(icon: "clock.fill", tint: .teal, title: "Your body clock",
               magnitude: "The rhythm underneath",
               claim: "The natural cycle beneath it all: a late-morning peak, the post-lunch dip, an evening second wind.",
               cites: [6]),
    ]
}
