//
//  AlertnessDetailView.swift
//  SleepBank
//
//  Alertness detail — the full curve plus an honest explainer of what shapes it
//  (the two-process model). Reached from the alertness widget (sleepbank://
//  alertness) and as a richer view of the home card.
//

import SwiftUI

struct AlertnessDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AlertnessCurveView()
                explainer
            }
            .padding()
        }
        .navigationTitle("Alertness")
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What shapes this").font(.headline)
            point("bed.double.fill", "Last night's sleep",
                  "Sets how high your whole curve sits today. A short night lowers it all day.", .indigo)
            point("moon.zzz.fill", "Naps",
                  "Discharge sleep pressure — a well-timed power nap lifts the rest of the afternoon.", .indigo)
            point("sun.max.fill", "Morning light & movement",
                  "Anchor your body clock and raise your morning — the natural levers.", .orange)
            point("clock.fill", "Your body clock",
                  "The natural rhythm underneath: a late-morning peak, the post-lunch dip, an evening second wind.", .teal)
            Text("This is a predicted rhythm to guide timing — illustrative, not a measurement.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func point(_ icon: String, _ title: String, _ body: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
