//
//  NapSessionRecorder.swift
//  SleepBank Watch App
//
//  Captures the per-second fused-signal trace during a nap so each session
//  becomes a labeled training example. On completion it assembles a
//  NapDecisionRecord (our decision + the trace) that's synced to the phone for
//  Apple-comparison and CreateML export.
//

import Foundation
import SleepBankCore

final class NapSessionRecorder {
    private var epochs: [NapEpochFeatures] = []
    private var start: Date?

    func begin(at time: Date) {
        start = time
        epochs = []
    }

    func record(now: Date, signal: OnsetSignal, phase: NapPhase) {
        guard let start else { return }
        epochs.append(NapEpochFeatures(
            t: now.timeIntervalSince(start),
            heartRate: signal.heartRate,
            hrv: signal.hrvRMSSD,
            movement: signal.movementIntensity,
            stillSeconds: signal.stillSeconds,
            eegOnset: signal.eegOnsetConfidence,
            eegDeep: signal.eegDeepApproaching,
            breathing: signal.breathing,
            phase: phase.rawValue
        ))
    }

    func build(record: NapRecord, trigger: OnsetTrigger?) -> NapDecisionRecord {
        NapDecisionRecord(
            id: record.id,
            type: record.type,
            start: record.start,
            end: record.end,
            onset: record.onset,
            onsetTrigger: trigger,
            wakeReason: record.wakeReason,
            epochs: epochs
        )
    }
}
