//
//  EnergyRingView.swift
//  SleepBank
//
//  The home-screen hero: a live "energy ring" showing how much alertness boost
//  your last nap is still giving you. It fills the moment you wake and quietly
//  empties over the nap's benefit window (~2 h for a power nap) — which is the
//  honest physiology, not a gimmick (NAP_BENEFIT_EVIDENCE.md §2: nap alertness is
//  transient). Beneath it sits the *descriptive* bank: naps today and your
//  current streak. No sleep-debt math anywhere — a nap is a top-up, not a ledger.
//

import SwiftUI
import SleepBankCore

struct EnergyRingView: View {
    var store = NapDecisionStore.shared

    var body: some View {
        // Re-evaluate every 30 s so the ring visibly drains while the app is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let charge = AlertnessCharge.current(now: context.date, lastNap: lastNap)
            VStack(spacing: 16) {
                ring(for: charge)
                alertnessNow(at: context.date)
                bankFooter
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Ring

    private func ring(for charge: AlertnessCharge) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 18)
            Circle()
                .trim(from: 0, to: max(0.001, charge.level))
                .stroke(
                    AngularGradient(colors: tint(for: charge.level),
                                    center: .center, startAngle: .degrees(-90),
                                    endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: charge.level)
            VStack(spacing: 2) {
                Text("\(Int((charge.level * 100).rounded()))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(descriptor(for: charge.level))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 180)
        .overlay(alignment: .bottom) {
            Text(caption(for: charge))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .offset(y: 30)
        }
        .padding(.bottom, 24)
    }

    private func tint(for level: Double) -> [Color] {
        switch level {
        case 0.55...:        return [.mint, .teal]      // charged
        case 0.25..<0.55:    return [.indigo, .blue]    // holding
        case 0.01..<0.25:    return [.orange, .pink]    // fading
        default:             return [.gray, .gray]
        }
    }

    private func descriptor(for level: Double) -> String {
        switch level {
        case 0.66...:     return "Charged"
        case 0.33..<0.66: return "Holding"
        case 0.05..<0.33: return "Fading"
        default:          return "Ready to nap"
        }
    }

    private func caption(for charge: AlertnessCharge) -> String {
        guard let source = charge.source, charge.level > 0 else {
            return "A nap tops you up for an hour or two"
        }
        let m = charge.minutesRemaining
        let left = m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
        return "\(source.title) · fades in \(left)"
    }

    // MARK: - Alertness now (glance — full picture lives in the curve card)

    /// The ring shows the *nap* charge; this line shows your *overall* predicted
    /// alertness right now (sleep + naps + light + movement) and where you sit in the
    /// day — the "you are here" number, glanceable without opening the curve.
    private func alertnessNow(at now: Date) -> some View {
        let rhythm = AlertnessProvider.rhythm(now: now)
        let level = rhythm.level(at: now)
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow)
            Text("\(AlertnessProvider.pct(level))% alert")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
            Text("· \(AlertnessProvider.phaseLabel(now))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Descriptive bank

    private var bankFooter: some View {
        HStack(spacing: 14) {
            stat(value: "\(napsToday)", label: napsToday == 1 ? "nap today" : "naps today")
            if streak > 0 {
                Divider().frame(height: 28)
                stat(value: "🔥 \(streak)", label: streak == 1 ? "day" : "day streak")
            }
            Divider().frame(height: 28)
            stat(value: "\(minutesThisWeek)", label: "min this week")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    /// The most recent completed nap, mapped from the decision store.
    private var lastNap: NapRecord? {
        guard let r = store.records.max(by: { $0.end < $1.end }) else { return nil }
        return NapRecord(id: r.id, start: r.start, end: r.end, type: r.type,
                         onset: r.onset, wakeReason: r.wakeReason)
    }

    private var napRecords: [NapRecord] {
        store.records.map {
            NapRecord(id: $0.id, start: $0.start, end: $0.end, type: $0.type,
                      onset: $0.onset, wakeReason: $0.wakeReason)
        }
    }

    private var napsToday: Int { NapBank.count(on: Date(), in: napRecords) }
    private var streak: Int { NapBank.currentStreak(asOf: Date(), in: napRecords) }
    private var minutesThisWeek: Int { NapBank.minutesAsleepLast7Days(endingAt: Date(), in: napRecords) }
}
