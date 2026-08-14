// SPDX-License-Identifier: MIT

import Foundation

/// Schedules network synchronization without coupling edits to a Git operation.
///
/// There is one serial worker for the whole application. This deliberately keeps
/// CPU, disk, and provider traffic bounded even when a user has many projects.
/// Projects without a configured remote never enter this scheduler.
@MainActor
final class ProjectSyncScheduler {
    struct Policy: Sendable {
        let localChangeDebounce: Duration
        let maximumLocalChangeDelay: TimeInterval
        let activeProjectActivationDebounce: Duration
        let activeProjectRefresh: TimeInterval
        let inactiveProjectRefresh: TimeInterval
        let maintenanceInterval: Duration
        let retryDelays: [Duration]

        static let production = Policy(
            localChangeDebounce: .seconds(3),
            maximumLocalChangeDelay: 15,
            activeProjectActivationDebounce: .seconds(1),
            activeProjectRefresh: 30,
            inactiveProjectRefresh: 30 * 60,
            maintenanceInterval: .seconds(10),
            retryDelays: [
                .seconds(60), .seconds(5 * 60), .seconds(15 * 60), .seconds(60 * 60)
            ]
        )
    }

    enum AttemptOutcome: Equatable {
        case succeeded
        case retryLater
        case blocked
    }

    typealias SynchronizationOperation = @MainActor (UUID) async -> AttemptOutcome

    private let policy: Policy
    private let synchronizationOperation: SynchronizationOperation
    private var delayedTasks: [UUID: Task<Void, Never>] = [:]
    private var queuedProjectIDs: [UUID] = []
    private var queuedIDs = Set<UUID>()
    private var followUpIDs = Set<UUID>()
    private var runningProjectID: UUID?
    private var worker: Task<Void, Never>?
    private let rustPlanner = RustSyncPlannerClient()
    private var rustPlannerState = RustSyncPlannerClient.State()

    init(
        policy: Policy = .production,
        synchronizationOperation: @escaping SynchronizationOperation
    ) {
        self.policy = policy
        self.synchronizationOperation = synchronizationOperation
    }

    func recordLocalChange(for projectID: UUID) {
        applyRustPlan(event: "local_change", projectID: projectID, projects: [], activeID: nil, replacingExistingDelay: true)
    }

    func requestImmediateSync(for projectID: UUID) {
        applyRustPlan(event: "immediate", projectID: projectID, projects: [], activeID: nil, replacingExistingDelay: true)
    }

    func projectBecameActive(_ project: FSProject, now: Date = .now) {
        applyRustPlan(event: "active", projectID: project.id, projects: [project], activeID: project.id, replacingExistingDelay: false, now: now)
    }

    /// Schedules the active project first and at most one inactive project per
    /// maintenance pass. This ensures an installation with many projects never
    /// turns a timer tick into a burst of provider requests.
    func scheduleMaintenance(
        activeProject: FSProject?,
        inactiveProjects: [FSProject],
        now: Date = .now
    ) {
        applyRustPlan(event: "maintenance", projectID: nil, projects: (activeProject.map { [$0] } ?? []) + inactiveProjects, activeID: activeProject?.id, replacingExistingDelay: false, now: now)
    }

    private func applyRustPlan(event: String, projectID: UUID?, projects: [FSProject], activeID: UUID?, replacingExistingDelay: Bool, now: Date = .now, succeeded: Bool? = nil, blocked: Bool? = nil) {
        let plannerPolicy = RustSyncPlannerClient.Policy(debounce: seconds(policy.localChangeDebounce), maximumDelay: policy.maximumLocalChangeDelay, activeDelay: seconds(policy.activeProjectActivationDebounce), activeRefresh: policy.activeProjectRefresh, inactiveRefresh: policy.inactiveProjectRefresh, retries: policy.retryDelays.map(seconds))
        let inputs = projects.map { RustSyncPlannerClient.Project(id: $0.id.uuidString, remote: $0.gitRepository?.remoteURL != nil, lastSynced: $0.gitRepository?.lastSyncedAt?.timeIntervalSince1970) }
        let decision: RustSyncPlannerClient.Decision
        do {
            decision = try rustPlanner.plan(.init(policy: plannerPolicy, state: rustPlannerState, projects: inputs, activeID: activeID?.uuidString, now: now.timeIntervalSince1970, event: event, projectID: projectID?.uuidString, succeeded: succeeded, blocked: blocked))
        } catch { preconditionFailure("Rust sync planner failed: \(error.localizedDescription)") }
        rustPlannerState = decision.state
        for item in decision.schedules where UUID(uuidString: item.projectID) != nil { schedule(UUID(uuidString: item.projectID)!, after: .milliseconds(Int64(item.delay * 1_000)), replacingExistingDelay: replacingExistingDelay) }
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
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

                applyRustPlan(event: "finished", projectID: projectID, projects: [], activeID: nil, replacingExistingDelay: true, succeeded: outcome == .succeeded, blocked: outcome == .blocked)

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
