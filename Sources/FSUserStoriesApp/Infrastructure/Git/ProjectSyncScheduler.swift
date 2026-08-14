// SPDX-License-Identifier: MIT

import Foundation

/// Schedules network synchronization without coupling edits to a Git operation.
///
/// There is one serial worker for the whole application. This deliberately keeps
/// CPU, disk, and provider traffic bounded even when a user has many projects.
/// Projects without a configured remote never enter this scheduler.
@MainActor
final class ProjectSyncScheduler {
    enum Policy {
        static let localChangeDebounce: Duration = .seconds(8)
        static let maximumLocalChangeDelay: TimeInterval = 45
        static let activeProjectActivationDebounce: Duration = .seconds(1)
        static let activeProjectRefresh: TimeInterval = 2 * 60
        static let inactiveProjectRefresh: TimeInterval = 30 * 60
        static let maintenanceInterval: Duration = .seconds(60)
        static let retryDelays: [Duration] = [
            .seconds(60), .seconds(5 * 60), .seconds(15 * 60), .seconds(60 * 60)
        ]
    }

    enum AttemptOutcome: Equatable {
        case succeeded
        case retryLater
        case blocked
    }

    typealias SynchronizationOperation = @MainActor (UUID) async -> AttemptOutcome

    private let synchronizationOperation: SynchronizationOperation
    private var delayedTasks: [UUID: Task<Void, Never>] = [:]
    private var queuedProjectIDs: [UUID] = []
    private var queuedIDs = Set<UUID>()
    private var followUpIDs = Set<UUID>()
    private var runningProjectID: UUID?
    private var worker: Task<Void, Never>?
    private var inactiveCursor = 0
    private var failureCounts: [UUID: Int] = [:]
    private var firstLocalChangeAt: [UUID: Date] = [:]
    private var activeProjectTask: Task<Void, Never>?

    init(synchronizationOperation: @escaping SynchronizationOperation) {
        self.synchronizationOperation = synchronizationOperation
    }

    func recordLocalChange(for projectID: UUID) {
        let now = Date.now
        let firstChange = firstLocalChangeAt[projectID] ?? now
        firstLocalChangeAt[projectID] = firstChange

        // Keep batching rapid edits, but never postpone a publish forever for a
        // continuously edited project.
        let remaining = max(0, Policy.maximumLocalChangeDelay - now.timeIntervalSince(firstChange))
        let debounce = min(Policy.localChangeDebounce, .milliseconds(Int64(remaining * 1_000)))
        schedule(projectID, after: debounce, replacingExistingDelay: true)
    }

    func requestImmediateSync(for projectID: UUID) {
        schedule(projectID, after: .zero, replacingExistingDelay: true)
    }

    func projectBecameActive(_ project: FSProject, now: Date = .now) {
        guard project.gitRepository?.remoteURL != nil else { return }
        guard isDue(project.gitRepository?.lastSyncedAt, interval: Policy.activeProjectRefresh, now: now) else {
            return
        }
        activeProjectTask?.cancel()
        activeProjectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Policy.activeProjectActivationDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            activeProjectTask = nil
            schedule(project.id, after: .zero, replacingExistingDelay: false)
        }
    }

    /// Schedules the active project first and at most one inactive project per
    /// maintenance pass. This ensures an installation with many projects never
    /// turns a timer tick into a burst of provider requests.
    func scheduleMaintenance(
        activeProject: FSProject?,
        inactiveProjects: [FSProject],
        now: Date = .now
    ) {
        if let activeProject {
            projectBecameActive(activeProject, now: now)
        }

        let eligibleInactive = inactiveProjects.filter {
            $0.gitRepository?.remoteURL != nil && isDue(
                $0.gitRepository?.lastSyncedAt,
                interval: Policy.inactiveProjectRefresh,
                now: now
            )
        }
        guard !eligibleInactive.isEmpty else { return }

        let index = inactiveCursor % eligibleInactive.count
        inactiveCursor = (inactiveCursor + 1) % eligibleInactive.count
        schedule(eligibleInactive[index].id, after: .zero, replacingExistingDelay: false)
    }

    private func isDue(_ lastSyncedAt: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) >= interval
    }

    private func schedule(
        _ projectID: UUID,
        after delay: Duration,
        replacingExistingDelay: Bool
    ) {
        if delayedTasks[projectID] != nil, !replacingExistingDelay {
            return
        }
        if replacingExistingDelay {
            delayedTasks[projectID]?.cancel()
        }

        delayedTasks[projectID] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            delayedTasks[projectID] = nil
            firstLocalChangeAt[projectID] = nil
            enqueue(projectID)
        }
    }

    private func enqueue(_ projectID: UUID) {
        if runningProjectID == projectID {
            followUpIDs.insert(projectID)
            return
        }
        guard queuedIDs.insert(projectID).inserted else { return }
        queuedProjectIDs.append(projectID)
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, !queuedProjectIDs.isEmpty {
                let projectID = queuedProjectIDs.removeFirst()
                queuedIDs.remove(projectID)
                runningProjectID = projectID
                let outcome = await synchronizationOperation(projectID)
                runningProjectID = nil

                switch outcome {
                case .succeeded:
                    failureCounts[projectID] = nil
                case .retryLater:
                    let failureCount = failureCounts[projectID, default: 0]
                    failureCounts[projectID] = failureCount + 1
                    let delay = Policy.retryDelays[min(failureCount, Policy.retryDelays.count - 1)]
                    schedule(projectID, after: delay, replacingExistingDelay: true)
                case .blocked:
                    // A conflict requires a human decision. Do not retry it.
                    failureCounts[projectID] = nil
                }

                if outcome == .succeeded, followUpIDs.remove(projectID) != nil {
                    enqueue(projectID)
                } else {
                    followUpIDs.remove(projectID)
                }
            }
            worker = nil
        }
    }
}
