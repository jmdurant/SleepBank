//
//  ResearchConsentStore.swift
//  SleepBank
//
//  Consent state for optional research participation. Nothing leaves the device
//  unless the user explicitly consents here; on consent we mint a *pseudonymous*
//  participant ID (a random UUID) that keys any export — the user's name/identity is
//  never part of the exported data (the linking key, if a study ever needs one, is
//  held separately by the study team, not in the export).
//
//  This is the consent gate. The flow UI mirrors a ResearchKit ORKConsentDocument
//  (overview → data → privacy → withdrawal → signature); when an IRB protocol exists,
//  swap this for real ResearchKit and point ResearchExporter at the study backend
//  (REDCap / MyDataHelps). See docs/REGULATORY/DATA_ARCHITECTURE.md.
//

import Foundation

@Observable
final class ResearchConsentStore {
    static let shared = ResearchConsentStore()

    /// Bump when the consent text materially changes — re-consent is then required.
    static let consentVersion = "2026-06-11-v1"

    private(set) var hasConsented: Bool = UserDefaults.standard.bool(forKey: K.consented)
    private(set) var consentedAt: Date? = UserDefaults.standard.object(forKey: K.date) as? Date
    private(set) var consentedVersion: String? = UserDefaults.standard.string(forKey: K.version)
    /// Pseudonymous study key — the only identifier that travels with exported data.
    private(set) var participantID: String = UserDefaults.standard.string(forKey: K.pid) ?? ""

    private enum K {
        static let consented = "researchConsented"
        static let date = "researchConsentDate"
        static let version = "researchConsentVersion"
        static let pid = "researchParticipantID"
    }

    /// True when the user consented under the *current* consent version.
    var isCurrent: Bool { hasConsented && consentedVersion == Self.consentVersion }

    func grant() {
        if participantID.isEmpty {
            participantID = UUID().uuidString
            UserDefaults.standard.set(participantID, forKey: K.pid)
        }
        hasConsented = true
        consentedAt = Date()
        consentedVersion = Self.consentVersion
        UserDefaults.standard.set(true, forKey: K.consented)
        UserDefaults.standard.set(consentedAt, forKey: K.date)
        UserDefaults.standard.set(Self.consentVersion, forKey: K.version)
    }

    /// Withdraw consent. Stops future export; keeps the (now-dormant) participant ID
    /// so a re-consent reuses the same key rather than creating a duplicate record.
    func withdraw() {
        hasConsented = false
        UserDefaults.standard.set(false, forKey: K.consented)
    }
}
