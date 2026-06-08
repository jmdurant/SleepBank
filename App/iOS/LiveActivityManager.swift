//
//  LiveActivityManager.swift
//  SleepBank
//
//  Starts/updates/ends the nap Live Activity on the phone in response to nap
//  state forwarded from the watch. Sweeps orphan activities on end so a stale
//  banner from a previous crash can't linger.
//

import Foundation
import ActivityKit

@Observable
class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var activity: Activity<NapActivityAttributes>?

    func start(title: String, sessionStart: Date, state: NapActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()   // clear any existing/orphan before starting fresh
        let attributes = NapActivityAttributes(napTitle: title, sessionStart: sessionStart)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] start failed: \(error)")
        }
    }

    func update(_ state: NapActivityAttributes.ContentState) {
        Task { await activity?.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        let toEnd = activity
        activity = nil
        Task {
            await toEnd?.end(nil, dismissalPolicy: .immediate)
            for orphan in Activity<NapActivityAttributes>.activities {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
