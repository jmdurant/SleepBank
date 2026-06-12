//
//  DaylightView.swift
//  SleepBank
//
//  Daylight detail — today's Time in Daylight split by window (morning is the
//  circadian-critical one), the morning-light streak and morning movement, and an
//  honest explainer of *why* it matters (anchors your rhythm + helps tonight's
//  sleep, not a big acute jolt). Reached from the curve card's daylight row and the
//  sleepbank://daylight deep link.
//

import SwiftUI
import SleepBankCore

/// Home-stack navigation routes used by deep links and in-app links.
enum HomeRoute: Hashable {
    case plan
    case daylight
    case alertness
    case history
    case windDown
    case nap
    case settings
    case epworth
    case psas
    case kss
    case research
}

struct DaylightView: View {
    @State private var health = HealthKitService.shared

    private var d: DaylightDay { health.daylightToday }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                breakdownCard
                whyCard
            }
            .padding()
        }
        .navigationTitle("Daylight")
        .task { if await health.requestAuthorization() { await health.refreshAll() } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.sand)
            Text("\(Int(d.total.rounded())) min").font(.system(.largeTitle, design: .rounded).bold())
            Text("daylight today").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if health.morningLightStreak > 0 {
                    stat("🌅 \(health.morningLightStreak)", health.morningLightStreak == 1 ? "day" : "day streak")
                }
                if health.morningActivityMinutes >= 1 {
                    stat("🚶 \(Int(health.morningActivityMinutes.rounded()))", "min AM move")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When it landed").font(.headline)
            Text("Morning light counts most — it anchors your body clock.")
                .font(.caption).foregroundStyle(.secondary)
            let maxMin = max(d.morning, d.afternoon, d.evening, 1)
            bar("Morning", d.morning, maxMin, .sand, emphasized: true)
            bar("Afternoon", d.afternoon, maxMin, .sand)
            bar("Evening", d.evening, maxMin, .ocean)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func bar(_ label: String, _ minutes: Double, _ maxMin: Double, _ color: Color, emphasized: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label).font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .frame(width: 78, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 12)
                    Capsule().fill(color)
                        .frame(width: max(6, geo.size.width * (minutes / maxMin)), height: 12)
                }
            }
            .frame(height: 12)
            Text("\(Int(minutes.rounded()))m").font(.caption).monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Why

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why morning light").font(.headline)
            point("sunrise.fill", "Anchors your rhythm",
                  "Morning light sets your body clock — the natural counterpart to a nap. It's the reliable benefit.")
            point("bolt.fill", "Helps you wake",
                  "It lifts your morning cortisol (the wake-up hormone) — a gentler, real boost, not a jolt.")
            point("bed.double.fill", "Better sleep tonight",
                  "More daylight by day makes evening light less disruptive, so you sleep better that night.")
            Text("Aim to get outside in the morning. It's about daylight, not a magic number of minutes.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.sand).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
