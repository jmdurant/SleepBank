import Foundation
import WatchConnectivity
import WatchKit

/// Retains the system's delivery budget until both WC and our model writes drain.
final class ConnectivityBackgroundDelivery {
    static let shared = ConnectivityBackgroundDelivery()
    private let work = RelayWorkTracker()
    private var tasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var observations: [NSKeyValueObservation] = []

    private init() {
        let session = WCSession.default
        observations = [
            session.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in self?.check() },
            session.observe(\.activationState, options: [.new]) { [weak self] _, _ in self?.check() }
        ]
    }

    func receive(_ incoming: Set<WKRefreshBackgroundTask>) {
        for task in incoming {
            guard let task = task as? WKWatchConnectivityRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            tasks.append(task)
            task.expirationHandler = { [weak self, weak task] in
                DispatchQueue.main.async {
                    if let task { self?.finish(task) }
                }
            }
        }
        // Delegate callbacks follow this handler. Their tracked completion (or
        // WC activation/content observation) will release the task.
    }

    func perform(_ action: @escaping @MainActor () -> Void) {
        work.begin()
        DispatchQueue.main.async {
            defer { self.work.end(); self.check() }
            action()
        }
    }

    func performAsync(_ action: @escaping @MainActor () async -> Void) {
        work.begin()
        Task { @MainActor in
            defer { self.work.end(); self.check() }
            await action()
        }
    }

    func activationFinished(error: Error?) {
        DispatchQueue.main.async {
            if error != nil {
                for task in self.tasks { task.setTaskCompletedWithSnapshot(false) }
                self.tasks.removeAll()
            } else { self.check() }
        }
    }

    private func check() {
        DispatchQueue.main.async {
            guard WCSession.default.activationState == .activated,
                  !WCSession.default.hasContentPending, self.work.isIdle else { return }
            let completed = self.tasks
            self.tasks.removeAll()
            for task in completed { task.setTaskCompletedWithSnapshot(false) }
        }
    }

    private func finish(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        guard tasks.contains(where: { $0 === task }) else { return }
        tasks.removeAll { $0 === task }
        task.setTaskCompletedWithSnapshot(false)
    }
}
