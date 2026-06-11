//
//  ResearchExporter.swift
//  SleepBank
//
//  Builds a *de-identified* export of the validated-instrument data we collect
//  (Epworth, Pre-Sleep Arousal, Karolinska sleepiness) plus the chronotype/sleep-need
//  covariates — keyed only by the pseudonymous participant ID. No name, no contact, no
//  device identifiers. Gated on research consent.
//
//  This produces the JSON a study backend would ingest. The seam: today it's a share
//  sheet (hand-off to the user / a partner); swap in a REDCap/MyDataHelps upload here
//  once an IRB protocol + backend exist. See docs/REGULATORY/DATA_ARCHITECTURE.md.
//

import Foundation

struct ResearchExport: Codable {
    let participantID: String
    let exportedAt: Date
    let schemaVersion: Int
    let consentVersion: String

    let profile: ProfileData?
    let epworth: [EpworthResult]
    let preSleepArousal: [PSASSession]
    let napSleepiness: [KSSSession]

    struct ProfileData: Codable {
        let bedtimeMinutes: Int
        let wakeMinutes: Int
        let needHours: Double
        let circadianShiftHours: Double
    }
}

enum ResearchExporter {

    static let schemaVersion = 1

    /// Build the de-identified bundle. Returns nil if consent isn't current.
    static func build(consent: ResearchConsentStore = .shared) -> ResearchExport? {
        guard consent.isCurrent else { return nil }
        let p = SleepProfile.shared
        let profile = p.isSet ? ResearchExport.ProfileData(
            bedtimeMinutes: p.bedtimeMinutes, wakeMinutes: p.wakeMinutes,
            needHours: p.needHours, circadianShiftHours: p.circadianShiftHours) : nil

        return ResearchExport(
            participantID: consent.participantID,
            exportedAt: Date(),
            schemaVersion: schemaVersion,
            consentVersion: consent.consentedVersion ?? ResearchConsentStore.consentVersion,
            profile: profile,
            epworth: EpworthStore.shared.results,
            preSleepArousal: PSASStore.shared.sessions,
            napSleepiness: KSSStore.shared.sessions
        )
    }

    /// Write the bundle to a temporary JSON file for sharing. Nil if not consented.
    static func writeJSON() -> URL? {
        guard let export = build() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return nil }
        let stamp = export.participantID.prefix(8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepbank-research-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("[ResearchExporter] write failed: \(error)")
            return nil
        }
    }

    /// A quick count of records the export would contain (for the UI).
    static func recordCount() -> Int {
        EpworthStore.shared.results.count
            + PSASStore.shared.sessions.count
            + KSSStore.shared.sessions.count
    }
}
