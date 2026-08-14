// SPDX-License-Identifier: MIT

import Foundation

struct RustSyncPlannerClient: Sendable {
    struct Policy: Codable, Sendable {
        var debounce: Double; var maximumDelay: Double; var activeDelay: Double
        var activeRefresh: Double; var inactiveRefresh: Double; var retries: [Double]
    }
    struct State: Codable, Sendable { var firstChanges: [String: Double] = [:]; var failures: [String: Int] = [:]; var cursor = 0 }
    struct Project: Codable, Sendable { var id: String; var remote: Bool; var lastSynced: Double? }
    struct Request: Codable, Sendable {
        var policy: Policy; var state: State; var projects: [Project]; var activeID: String?
        var now: Double; var event: String; var projectID: String?; var succeeded: Bool?; var blocked: Bool?
        enum CodingKeys: String, CodingKey {
            case policy, state, projects, now, event, succeeded, blocked
            case activeID = "activeId"
            case projectID = "projectId"
        }
    }
    struct Schedule: Codable, Sendable {
        var projectID: String; var delay: Double
        enum CodingKeys: String, CodingKey { case projectID = "projectId"; case delay }
    }
    struct Decision: Codable, Sendable { var state: State; var schedules: [Schedule] }

    func plan(_ request: Request) throws -> Decision {
        let encoder = JSONEncoder(); let data = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data)
        let result = try RustCoreClient().execute(["command": "plan_synchronization", "request": object])
        guard let decision = result["schedules"].map({ _ in result }) else { throw RustCoreError.invalidResponse }
        return try JSONDecoder().decode(Decision.self, from: JSONSerialization.data(withJSONObject: decision))
    }
}
