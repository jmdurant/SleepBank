//
//  RawEEGRecorder.swift
//  SleepBank
//
//  Captures the full raw 4-channel Muse EEG for a nap and writes it to a CSV the
//  YASA training/labeling pipeline can read (one column per channel at 256 Hz).
//  This is the missing input for the ML path: export a nap's raw EEG → stage it
//  offline with YASA on a Mac → use those per-epoch labels to train an on-device
//  model. Recording is gated to nap sessions (phone-hosted, where the Muse pairs).
//
//  Python/YASA: df = pandas.read_csv(file); af7 = df["af7"].values; sf = 256
//               raw = mne.io.RawArray(af7[None]*1e-6, mne.create_info(["AF7"], sf, "eeg"))
//               yasa.SleepStaging(raw, eeg_name="AF7").predict()
//

import Foundation

@Observable
final class RawEEGRecorder {

    static let shared = RawEEGRecorder()

    private(set) var isRecording = false
    private(set) var sampleCount = 0          // AF7 samples captured (≈ seconds * 256)
    private(set) var lastFileURL: URL?

    let sampleRate = 256
    private let columns = ["tp9", "af7", "af8", "tp10"]
    private let maxSamples = 256 * 60 * 110     // ~110 min ceiling, memory guard
    @ObservationIgnored private var channels: [[Float]] = [[], [], [], []]

    func begin() {
        channels = [[], [], [], []]
        sampleCount = 0
        isRecording = true
    }

    /// Append a packet's worth of samples for one channel (called from MuseService).
    func record(channel: Int, samples: [Float]) {
        guard isRecording, channel < 4, channels[channel].count < maxSamples else { return }
        channels[channel].append(contentsOf: samples)
        if channel == 1 { sampleCount = channels[1].count }   // AF7 = our reference
    }

    /// Stop and write the CSV (off the main thread). Returns immediately; the file
    /// URL lands in `lastFileURL` when the write completes.
    func finish() {
        guard isRecording else { return }
        isRecording = false
        let snapshot = channels
        channels = [[], [], [], []]
        let rows = snapshot.map(\.count).min() ?? 0
        guard rows > 0 else { return }

        let stamp = Self.stampFormatter.string(from: Date())

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let url = Self.outputDirectory().appendingPathComponent("eeg-\(stamp).csv")
            var text = self.columns.joined(separator: ",") + "\n"
            text.reserveCapacity(rows * 28)
            for i in 0..<rows {
                text += "\(snapshot[0][i]),\(snapshot[1][i]),\(snapshot[2][i]),\(snapshot[3][i])\n"
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { self.lastFileURL = url }
        }
    }

    /// The iCloud Documents container (syncs to the Mac automatically) when
    /// available, else the local Documents directory. Called off the main thread —
    /// resolving the ubiquity container can block on first access.
    private static func outputDirectory() -> URL {
        let fm = FileManager.default
        if let container = fm.url(forUbiquityContainerIdentifier: "iCloud.com.doctordurant.sleepbank") {
            let docs = container.appendingPathComponent("Documents")
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    @ObservationIgnored private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
