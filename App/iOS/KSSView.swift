//
//  KSSView.swift
//  SleepBank
//
//  Karolinska Sleepiness Scale UI: a one-tap 1–9 picker (used before a nap and at
//  the recap) and a Settings-linked history of before→after changes.
//

import SwiftUI

/// The 9-level KSS picker. Calls `onPick` with the chosen value.
struct KSSPickerView: View {
    let title: String
    let prompt: String
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(prompt).font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(KSSStore.levels, id: \.0) { value, label in
                        Button { onPick(value) } label: {
                            HStack {
                                Text("\(value)")
                                    .font(.headline.monospacedDigit())
                                    .frame(width: 28)
                                    .foregroundStyle(color(for: value))
                                Text(label).foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
            }
        }
    }

    private func color(for value: Int) -> Color {
        switch value {
        case ...3: return .green
        case 4...6: return .mint
        case 7: return .sand
        default: return .red
        }
    }
}

struct KSSHistoryView: View {
    @State private var store = KSSStore.shared

    var body: some View {
        Form {
            Section {
                Text("How sleepy do you feel right now? SleepBank asks this before a nap and again when you wake, so you can see the nap working (the number should drop).")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Karolinska Sleepiness Scale")
            } footer: {
                Text("A self-tracking score, not a diagnosis.")
            }

            if !store.sessions.isEmpty {
                Section("History") {
                    ForEach(store.sessions) { s in
                        HStack {
                            Text(s.date, format: .dateTime.month().day().hour().minute())
                            Spacer()
                            if let post = s.post, let delta = s.delta {
                                Text("\(s.pre)").foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text("\(post)").font(.headline.monospacedDigit())
                                Text(delta == 0 ? "±0" : (delta < 0 ? "\(delta)" : "+\(delta)"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .sand : .secondary))
                            } else {
                                Text("\(s.pre)").font(.headline.monospacedDigit())
                                Text("before only").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { store.sessions[$0] }.forEach(store.delete) }
                }
            }
        }
        .navigationTitle("Sleepiness")
        .navigationBarTitleDisplayMode(.inline)
    }
}
