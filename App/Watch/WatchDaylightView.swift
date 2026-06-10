//
//  WatchDaylightView.swift
//  SleepBank Watch App
//
//  Shown when the morning-light complication is tapped (sleepbank://daylight).
//  The watch only holds the streak (synced from the phone), so this is a compact
//  glance + the honest "why."
//

import SwiftUI

struct WatchDaylightView: View {
    private var streak: Int { SharedStore.morningLightStreak }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange)
                Text(streak > 0 ? "🌅 \(streak)-day" : "No streak yet")
                    .font(.title3.bold())
                Text("morning-light streak").font(.caption2).foregroundStyle(.secondary)
                Text("Step outside soon after waking — morning light anchors your rhythm and helps you sleep tonight.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding()
        }
    }
}
