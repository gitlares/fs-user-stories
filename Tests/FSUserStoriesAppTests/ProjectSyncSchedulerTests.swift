import Foundation
import XCTest
@testable import FSUserStoriesApp

@MainActor
final class ProjectSyncSchedulerTests: XCTestCase {
    private var fastPolicy: ProjectSyncScheduler.Policy {
        ProjectSyncScheduler.Policy(
            localChangeDebounce: .milliseconds(20),
            maximumLocalChangeDelay: 0.1,
            activeProjectActivationDebounce: .milliseconds(20),
            activeProjectRefresh: 0.05,
            inactiveProjectRefresh: 60,
            maintenanceInterval: .milliseconds(20),
            retryDelays: [.milliseconds(20)]
        )
    }

    func testLocalChangeAutomaticallyQueuesSynchronization() async {
        let projectID = UUID()
        let synchronized = expectation(description: "Local change synchronized")
        let scheduler = ProjectSyncScheduler(policy: fastPolicy) { receivedProjectID in
            XCTAssertEqual(receivedProjectID, projectID)
            synchronized.fulfill()
            return .succeeded
        }

        scheduler.recordLocalChange(for: projectID)

        await fulfillment(of: [synchronized], timeout: 1)
    }

    func testDueActiveProjectAutomaticallyQueuesRefresh() async {
        let projectID = UUID()
        let synchronized = expectation(description: "Active project refreshed")
        let scheduler = ProjectSyncScheduler(policy: fastPolicy) { receivedProjectID in
            XCTAssertEqual(receivedProjectID, projectID)
            synchronized.fulfill()
            return .succeeded
        }
        let project = FSProject(
            id: projectID,
            name: "Shared project",
            prefix: "SHA",
            gitRepository: GitRepositoryLink(
                localPath: "/tmp/shared-project",
                remoteURL: "https://example.com/shared-project.git",
                lastSyncedAt: Date.now.addingTimeInterval(-1)
            )
        )

        scheduler.scheduleMaintenance(activeProject: project, inactiveProjects: [])

        await fulfillment(of: [synchronized], timeout: 1)
    }
}
