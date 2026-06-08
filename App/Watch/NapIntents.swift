//
//  NapIntents.swift
//  SleepBank Watch App
//
//  App Intents so a nap can be started/stopped from Siri, the Shortcuts app, the
//  Action button, or a complication tap — without opening the app and tapping.
//  The nap loop runs on the watch, so these live on the watch.
//

import AppIntents
import SleepBankCore

/// Siri-facing nap type. Wraps SleepBankCore.NapType so Core stays free of
/// AppIntents.
enum NapKind: String, AppEnum {
    case power
    case cycle

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Nap Type" }
    static var caseDisplayRepresentations: [NapKind: DisplayRepresentation] {
        [.power: "Power Nap", .cycle: "Cycle Nap"]
    }

    var napType: NapType { self == .power ? .power : .cycle }
}

struct StartNapIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Nap"
    static var description = IntentDescription("Start a SleepBank nap and its smart wake.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Nap type", default: .power)
    var kind: NapKind

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { NapController.shared.requestStart(kind.napType) }
        return .result(dialog: "Starting your \(kind == .power ? "power" : "cycle") nap")
    }
}

struct StopNapIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Nap"
    static var description = IntentDescription("End the current SleepBank nap.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { NapController.shared.stop() }
        return .result(dialog: "Ending your nap")
    }
}
