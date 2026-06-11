//
//  PSASView.swift
//  SleepBank
//
//  The Pre-Sleep Arousal Scale UI: a reusable 16-item survey (used for both the
//  "before" and "after" check-ins around the wind-down breathing), a before→after
//  result view, and the Settings-linked history. Non-diagnostic — it reports
//  arousal scores and how they changed, never a disorder label.
//

import SwiftUI

// MARK: - Reusable survey

/// The 16-item PSAS form. Calls `onComplete` with the answers (each 1–5).
struct PSASSurveyView: View {
    let title: String
    let subtitle: String
    let onComplete: ([Int]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var answers = Array(repeating: -1, count: PSASStore.items.count)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(PSASStore.items.enumerated()), id: \.offset) { i, item in
                    Section {
                        Picker(selection: binding(i)) {
                            ForEach(PSASStore.choices, id: \.0) { value, label in
                                Text(label).tag(value)
                            }
                        } label: {
                            Text(item)
                        }
                        .pickerStyle(.menu)
                    } header: {
                        if i == 0 { Text("Body") }
                        else if i == PSASStore.somaticCount { Text("Mind") }
                    }
                }
                Section {
                    Button {
                        onComplete(answers)
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .disabled(answers.contains(-1))
                } footer: {
                    if answers.contains(-1) { Text("Rate all 16 to continue.") }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func binding(_ i: Int) -> Binding<Int> {
        Binding(get: { answers[i] }, set: { answers[i] = $0 })
    }
}

// MARK: - Before → after result

struct PSASResultView: View {
    let session: PSASSession
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if session.post != nil {
                    Section {
                        deltaRow("Overall", pre: session.pre.total, post: session.post!.total, range: "16–80")
                        deltaRow("Body (somatic)", pre: session.pre.somatic, post: session.post!.somatic, range: "8–40")
                        deltaRow("Mind (cognitive)", pre: session.pre.cognitive, post: session.post!.cognitive, range: "8–40")
                    } header: {
                        Text("Before → after")
                    } footer: {
                        Text(summary).font(.callout)
                    }
                } else {
                    Section("Check-in") {
                        scoreRow("Overall", value: session.pre.total, range: "16–80")
                        scoreRow("Body (somatic)", value: session.pre.somatic, range: "8–40")
                        scoreRow("Mind (cognitive)", value: session.pre.cognitive, range: "8–40")
                    }
                }
            }
            .navigationTitle("Wind-down check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone?(); dismiss() }
                }
            }
        }
    }

    private var summary: String {
        guard let delta = session.totalDelta else { return "" }
        if delta < -3 { return "Your arousal came down — that's the wind-down working. Nice." }
        if delta > 3 { return "Still wound up. That's okay — some nights take longer; the breathing still helps over time." }
        return "About the same. Give it a few more minutes, or try again tomorrow night."
    }

    private func deltaRow(_ title: String, pre: Int, post: Int, range: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(pre)").foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text("\(post)").font(.headline.monospacedDigit())
            let d = post - pre
            Text(d == 0 ? "±0" : (d < 0 ? "\(d)" : "+\(d)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(d < 0 ? .green : (d > 0 ? .sand : .secondary))
        }
    }

    private func scoreRow(_ title: String, value: Int, range: String) -> some View {
        HStack {
            Text(title); Spacer()
            Text("\(value)").font(.headline.monospacedDigit())
            Text("/ \(range.split(separator: "–").last ?? "")").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings-linked history

struct PSASHistoryView: View {
    @State private var store = PSASStore.shared
    @State private var snapshot = false
    @State private var resultSession: PSASSession?
    @State private var moods: [HealthKitService.MoodAssessment] = []

    var body: some View {
        Form {
            if !moods.isEmpty {
                Section {
                    ForEach(moods) { m in
                        HStack {
                            Text(m.title)
                            Spacer()
                            Text("\(m.score)/\(m.scoreMax)").monospacedDigit().foregroundStyle(.secondary)
                            Text(m.risk).font(.caption.weight(.medium))
                        }
                    }
                } header: {
                    Text("From Apple Health")
                } footer: {
                    Text("Your latest depression/anxiety check-ins, read from Apple Health — both strongly affect sleep and pre-sleep arousal. SleepBank only reflects them; it doesn't score them.")
                }
            }

            Section {
                Text("Rate how wound-up you feel — in your body and your mind — as you try to fall asleep. Best taken as a *before & after* around the wind-down breathing, but you can take a one-off snapshot too.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { snapshot = true } label: {
                    Label("Take a check-in now", systemImage: "checklist")
                }
            } header: {
                Text("Pre-Sleep Arousal Scale")
            } footer: {
                Text("A self-tracking score, not a diagnosis.")
            }

            if !store.sessions.isEmpty {
                Section("History") {
                    ForEach(store.sessions) { s in
                        Button { resultSession = s } label: {
                            HStack {
                                Text(s.date, format: .dateTime.month().day().hour().minute())
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let delta = s.totalDelta {
                                    Text("\(s.pre.total)").foregroundStyle(.secondary).monospacedDigit()
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                    Text("\(s.post!.total)").font(.headline.monospacedDigit())
                                    Text(delta < 0 ? "\(delta)" : "+\(delta)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .sand : .secondary))
                                } else {
                                    Text("\(s.pre.total)").font(.headline.monospacedDigit())
                                    Text("check-in").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { store.sessions[$0] }.forEach(store.delete) }
                }
            }
        }
        .navigationTitle("Pre-Sleep Arousal")
        .navigationBarTitleDisplayMode(.inline)
        .task { moods = await HealthKitService.shared.latestMoodAssessments() }
        .sheet(isPresented: $snapshot) {
            PSASSurveyView(title: "Check-in", subtitle: "How wound-up are you right now?") { answers in
                store.startSession(pre: answers)
                snapshot = false
            }
        }
        .sheet(item: $resultSession) { s in
            PSASResultView(session: s)
        }
    }
}
