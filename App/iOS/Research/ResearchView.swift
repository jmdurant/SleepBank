//
//  ResearchView.swift
//  SleepBank
//
//  Optional research participation: a ResearchKit-shaped consent flow (overview →
//  what we collect → privacy → voluntary/withdrawal → agreement), then a status +
//  consent-gated de-identified export. Reached from Settings.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ResearchView: View {
    @State private var consent = ResearchConsentStore.shared
    @State private var agreed = false
    @State private var exportURL: ExportFile?

    var body: some View {
        Form {
            if consent.isCurrent {
                consentedSections
            } else {
                consentFlow
            }
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { file in ResearchShareSheet(items: [file.url]) }
    }

    // MARK: - Consent flow (not yet consented)

    private var consentFlow: some View {
        Group {
            Section {
                Text("SleepBank is an investigational wellness prototype. You can optionally let your check-in data help research into healthy, non-drug ways to manage daytime alertness. This is voluntary and separate from using the app.")
                    .font(.callout)
            } header: { Text("About this research") }

            section("What we'd collect", "tray.full.fill", [
                "Your check-in scores: daytime sleepiness (Epworth), pre-sleep arousal (PSAS), and nap sleepiness (Karolinska).",
                "Your typical schedule and sleep need (your chronotype) as study covariates.",
            ])
            section("How it's protected", "lock.shield.fill", [
                "Data is de-identified — tagged only with a random study ID, never your name, contact, or device.",
                "Nothing leaves your phone unless you tap Export. Today that's a share sheet you control; a study would receive it through an approved, consented pipeline.",
            ])
            section("Voluntary & reversible", "hand.raised.fill", [
                "Entirely optional — the app works exactly the same if you decline.",
                "You can withdraw anytime; that stops any future sharing.",
            ])
            section("Not medical care", "stethoscope", [
                "This is research/wellness, not medical advice, diagnosis, or treatment.",
            ])

            Section {
                Toggle("I've read the above and agree to participate", isOn: $agreed)
                Button {
                    consent.grant()
                    agreed = false
                } label: {
                    Text("Consent & participate").frame(maxWidth: .infinity)
                }
                .disabled(!agreed)
            } footer: {
                Text("Consent version \(ResearchConsentStore.consentVersion).")
            }
        }
    }

    // MARK: - Consented (status + export)

    private var consentedSections: some View {
        Group {
            Section {
                Label("You're participating", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                if let date = consent.consentedAt {
                    LabeledContent("Consented", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Study ID", value: String(consent.participantID.prefix(8)) + "…")
                LabeledContent("Records", value: "\(ResearchExporter.recordCount())")
            } header: {
                Text("Status")
            } footer: {
                Text("Your study ID is random and not linked to your identity in the export.")
            }

            Section {
                Button {
                    if let url = ResearchExporter.writeJSON() { exportURL = ExportFile(url: url) }
                } label: {
                    Label("Export my de-identified data", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Builds a de-identified JSON of your check-ins to share. (A real study would receive this through an approved backend — see the data-architecture plan.)")
            }

            Section {
                Button(role: .destructive) { consent.withdraw() } label: {
                    Text("Withdraw from research")
                }
            } footer: {
                Text("Stops future sharing. Data you already shared is governed by the study's terms.")
            }
        }
    }

    private func section(_ title: String, _ icon: String, _ points: [String]) -> some View {
        Section {
            ForEach(points, id: \.self) { p in
                Label { Text(p).font(.callout) } icon: { Image(systemName: icon).foregroundStyle(.indigo) }
            }
        } header: { Text(title) }
    }
}

/// Identifiable wrapper so a file URL can drive `.sheet(item:)`.
private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#if canImport(UIKit)
/// Minimal UIActivityViewController bridge — the share-sheet seam where a REDCap /
/// MyDataHelps upload would slot in for a real study.
private struct ResearchShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
