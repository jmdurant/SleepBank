//
//  ValidationView.swift
//  SleepBank
//
//  The n=1 validation surface: every nap's decision (when we called onset, which
//  signal fired, why we woke), compared against Apple's retrospective staging,
//  plus a one-tap CreateML CSV export of the accumulated training data.
//

import SwiftUI
import Charts
import SleepBankCore

struct ValidationView: View {
    @State private var store = NapDecisionStore.shared
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exporting = false

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(store.records.count) naps logged").font(.headline)
                        Text("\(store.epochCount) feature rows").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        exporting = true
                        Task {
                            exportURL = await NapTrainingExporter.exportCSV(records: store.records)
                            exporting = false
                            if exportURL != nil { showShare = true }
                        }
                    } label: {
                        if exporting { ProgressView() }
                        else { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    }
                    .disabled(store.records.isEmpty || exporting)
                }
            } footer: {
                Text("AirDrop the CSV to a Mac → CreateML → Tabular Classifier → set target to 'label' → Train. Filter labelSource to 'eeg'/'apple' for high-quality labels.")
            }

            Section {
                if let url = RawEEGRecorder.shared.lastFileURL {
                    Button {
                        exportURL = url
                        showShare = true
                    } label: {
                        Label("Export last nap's raw EEG", systemImage: "brain.head.profile")
                    }
                    Text(url.lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                } else if RawEEGRecorder.shared.isRecording {
                    Label("Recording EEG… \(RawEEGRecorder.shared.sampleCount / 256)s", systemImage: "record.circle")
                        .foregroundStyle(.red)
                } else {
                    Text("Take a nap with the Muse connected to capture raw EEG.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Raw EEG (for YASA)")
            } footer: {
                Text("AirDrop the CSV to a Mac, then stage it offline with YASA (256 Hz, use the AF7 column) to label this nap — the ground truth for training the on-device model.")
            }

            Section("Naps") {
                if store.records.isEmpty {
                    Text("Take a nap on the watch — its decision and trace sync here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(store.records) { record in
                    NavigationLink {
                        NapComparisonDetail(record: record)
                    } label: {
                        napRow(record)
                    }
                }
            }
        }
        .navigationTitle("Validation")
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
    }

    private func napRow(_ r: NapDecisionRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.type.title).font(.subheadline)
                Text(r.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.onset != nil ? "\(r.asleepMinutes) min asleep" : "no onset")
                    .font(.caption)
                if let trigger = r.onsetTrigger {
                    Text("via \(trigger.label)\(r.hasEEG ? " · EEG" : "")")
                        .font(.caption2).foregroundStyle(.ocean)
                }
            }
        }
    }
}

// MARK: - Per-nap detail

struct NapComparisonDetail: View {
    let record: NapDecisionRecord
    @State private var comparison: AppleNapComparison?

    var body: some View {
        List {
            Section("Our decision") {
                row("Onset", record.onsetLatency.map { "\(Int($0 / 60)) min in" } ?? "not detected")
                if let t = record.onsetTrigger { row("Triggered by", t.label) }
                row("Asleep", "\(record.asleepMinutes) min")
                row("Woke via", wake)
            }

            Section("Apple Health") {
                if let c = comparison {
                    if c.appleRecorded {
                        row("Apple recorded", "yes")
                        row("Apple asleep", "\(c.appleAsleepMinutes) min")
                        if let d = c.onsetDeltaSeconds {
                            row("Onset delta", String(format: "%+.0f s vs Apple", d))
                        }
                    } else {
                        Text("Apple recorded nothing for this window — it ignores naps under an hour.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack { ProgressView(); Text("Checking Apple Health…").font(.caption) }
                }
            }

            Section("Heart rate trace") {
                Chart(record.epochs, id: \.t) { e in
                    if let hr = e.heartRate {
                        LineMark(x: .value("min", e.t / 60), y: .value("bpm", hr))
                            .foregroundStyle(.red)
                    }
                }
                .frame(height: 140)
                if let lat = record.onsetLatency {
                    Text("Onset at \(Int(lat / 60)) min").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(record.type.title)
        .task { comparison = await AppleSleepComparator().compare(record) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private var wake: String {
        switch record.wakeReason {
        case .reachedTarget: return "smart alarm"
        case .deepening: return "deep sleep nearing"
        case .ceiling: return "time limit"
        case .spontaneous: return "woke naturally"
        case .manual, .none: return "manual"
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
