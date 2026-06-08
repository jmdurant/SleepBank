//
//  CoreMLOnsetDetector.swift
//  SleepBank Watch App
//
//  The inference seam for a trained onset model. Conforms to SleepBankCore's
//  SleepOnsetDetector so it drops into NapEngine in place of the heuristic.
//
//  Until a model is trained and bundled it transparently falls back to
//  HeartRateImmobilityOnsetDetector, so the app behaves identically today and
//  upgrades the moment a model ships. To enable the model:
//    1. Export training data from the Validation screen → CreateML on a Mac.
//    2. Train a Tabular Classifier on the 6 numeric features
//       (hr, hrv, movement, stillSeconds, eegOnset, eegDeep), target "label".
//    3. Drag the resulting NapOnsetClassifier.mlmodel into the watch target.
//  Inference inputs here match those training columns exactly.
//
//  The immobility gate is kept even with the model — movement corrupts every
//  signal, so we never declare onset while moving regardless of model output.
//

import Foundation
import CoreML
import SleepBankCore

final class CoreMLOnsetDetector: SleepOnsetDetector {

    private let fallback = HeartRateImmobilityOnsetDetector()
    private let model: MLModel?

    private var candidateSince: Date?
    private(set) var onsetTime: Date?
    private(set) var onsetTrigger: OnsetTrigger?

    // Inference thresholds (mirror the heuristic's gates).
    private let asleepThreshold = 0.6
    private let requiredStillSeconds: TimeInterval = 90
    private let holdSeconds: TimeInterval = 20

    /// True when a trained model is driving detection (vs. the heuristic).
    var usingModel: Bool { model != nil }

    init() {
        if let url = Bundle.main.url(forResource: "NapOnsetClassifier", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }
    }

    func reset() {
        fallback.reset()
        candidateSince = nil
        onsetTime = nil
        onsetTrigger = nil
    }

    func update(signal: OnsetSignal, at time: Date) -> Bool {
        // No model yet → behave exactly like the heuristic.
        guard let model else {
            let fired = fallback.update(signal: signal, at: time)
            if fired {
                onsetTime = fallback.onsetTime
                onsetTrigger = fallback.onsetTrigger
            }
            return fired
        }

        guard onsetTime == nil else { return false }

        let input: [String: Any] = [
            "hr": Double(signal.heartRate ?? 0),
            "hrv": signal.hrvRMSSD ?? 0,
            "movement": signal.movementIntensity,
            "stillSeconds": signal.stillSeconds,
            "eegOnset": signal.eegOnsetConfidence ?? 0,
            "eegDeep": signal.eegDeepApproaching ? 1.0 : 0.0,
        ]
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: input),
              let output = try? model.prediction(from: provider) else { return false }

        let prob = output.featureValue(for: "labelProbability")?
            .dictionaryValue["asleep"]?.doubleValue ?? 0
        let asleepLikely = prob >= asleepThreshold
        let stillEnough = signal.stillSeconds >= requiredStillSeconds

        if asleepLikely && stillEnough {
            if candidateSince == nil { candidateSince = time }
            if let since = candidateSince, time.timeIntervalSince(since) >= holdSeconds {
                onsetTime = time
                onsetTrigger = OnsetTrigger(heartRate: false, hrv: false, eeg: false, model: true)
                return true
            }
        } else {
            candidateSince = nil
        }
        return false
    }
}
