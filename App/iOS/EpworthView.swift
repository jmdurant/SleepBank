//
//  EpworthView.swift
//  SleepBank
//
//  The Epworth Sleepiness Scale as a self-tracking check-in: rate 8 situations,
//  see your score and how it's trending. Non-diagnostic by design (see EpworthStore).
//

import SwiftUI

struct EpworthView: View {
    @State private var store = EpworthStore.shared
    /// nil = not started; once taking, an answer per situation (-1 = unanswered).
    @State private var answers: [Int]?

    var body: some View {
        Group {
            if let answers {
                survey(answers)
            } else {
                overview
            }
        }
        .navigationTitle("Daytime Sleepiness")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overview (latest + history + start button)

    private var overview: some View {
        Form {
            Section {
                if let latest = store.latest {
                    scoreRow(latest.score, date: latest.date)
                } else {
                    Text("How likely are you to doze off during the day? Take the 8-question check-in to get your score.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    answers = Array(repeating: -1, count: EpworthStore.situations.count)
                } label: {
                    Label(store.latest == nil ? "Take the check-in" : "Take it again",
                          systemImage: "checklist")
                }
            } header: {
                Text("Epworth Sleepiness Scale")
            } footer: {
                Text("Measures how sleepy you tend to be during the day — the thing SleepBank is built to help with. A self-tracking score, not a diagnosis.")
            }

            if store.results.count > 1 {
                Section("History") {
                    ForEach(store.results) { r in
                        HStack {
                            Text(r.date, format: .dateTime.month().day().year())
                            Spacer()
                            Text("\(r.score)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(color(for: r.score))
                            Text(EpworthStore.band(for: r.score))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in offsets.map { store.results[$0] }.forEach(store.delete) }
                }
            }
        }
    }

    private func scoreRow(_ score: Int, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color(for: score))
                Text("/ 24").foregroundStyle(.secondary)
                Spacer()
                Text(EpworthStore.band(for: score))
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
            }
            Text("Last taken \(date, format: .relative(presentation: .named))")
                .font(.caption).foregroundStyle(.secondary)
            if let note = EpworthStore.note(for: score) {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Survey

    private func survey(_ current: [Int]) -> some View {
        Form {
            Section {
                Text("How likely are you to doze off or fall asleep in each situation — not just feel tired? Pick what's been usual for you lately.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ForEach(Array(EpworthStore.situations.enumerated()), id: \.offset) { i, situation in
                Section {
                    Picker(selection: bindingFor(i)) {
                        ForEach(EpworthStore.choices, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    } label: {
                        Text(situation)
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                Button {
                    store.record(answers: current)
                    answers = nil
                } label: {
                    Text("See my score").frame(maxWidth: .infinity)
                }
                .disabled(current.contains(-1))
                Button(role: .cancel) { answers = nil } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
            } footer: {
                if current.contains(-1) {
                    Text("Answer all 8 to see your score.")
                }
            }
        }
    }

    private func bindingFor(_ index: Int) -> Binding<Int> {
        Binding(
            get: { answers?[index] ?? -1 },
            set: { answers?[index] = $0 }
        )
    }

    private func color(for score: Int) -> Color {
        switch score {
        case ..<6:    return .green
        case 6...10:  return .mint
        case 11...15: return .orange
        default:      return .red
        }
    }
}
