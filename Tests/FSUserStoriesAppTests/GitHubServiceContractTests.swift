// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import FSUserStoriesApp

final class GitHubServiceContractTests: XCTestCase {
    func testAppStoreDistributionIsReadFromDedicatedMetadata() {
        XCTAssertTrue(AppDistribution.isMacAppStore(infoDictionary: ["FSDistributionChannel": "App Store"]))
        XCTAssertFalse(AppDistribution.isMacAppStore(infoDictionary: ["FSDistributionChannel": "Direct Download"]))
        XCTAssertFalse(AppDistribution.isMacAppStore(infoDictionary: [:]))
    }

    func testOnlyRecognizesOwnedMCPExecutablesForTakeover() {
        XCTAssertTrue(
            RustMCPServer.isOwnedMCPExecutable(
                "/Applications/FS User Stories.app/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"
            )
        )
        XCTAssertFalse(RustMCPServer.isOwnedMCPExecutable("/tmp/fs-user-stories-core"))
        XCTAssertFalse(RustMCPServer.isOwnedMCPExecutable("/Applications/Another App.app/server"))
    }

    func testDecodesRustDeviceAuthorizationContract() throws {
        let data = Data(
            #"{"deviceCode":"device","userCode":"ABCD-EFGH","verificationUrl":"https://github.com/login/device","expiresAt":"2026-08-14T20:00:00Z","interval":5}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let authorization = try decoder.decode(GitHubDeviceAuthorization.self, from: data)

        XCTAssertEqual(authorization.deviceCode, "device")
        XCTAssertEqual(authorization.userCode, "ABCD-EFGH")
        XCTAssertEqual(authorization.verificationURL.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(authorization.interval, 5)
    }

    func testDecodesRustRepositoryContract() throws {
        let data = Data(
            #"{"name":"example","fullName":"owner/example","cloneUrl":"https://github.com/owner/example.git","webUrl":"https://github.com/owner/example"}"#.utf8
        )

        let repository = try JSONDecoder().decode(GitHubRepository.self, from: data)

        XCTAssertEqual(repository.cloneURL, "https://github.com/owner/example.git")
        XCTAssertEqual(repository.webURL.absoluteString, "https://github.com/owner/example")
    }

    func testDecodesJoinedProjectWithRustGitContract() throws {
        let data = Data(
            #"{"id":"E393EF83-040B-4CFD-880F-565EBFD9C023","name":"Example","prefix":"EX","actors":[],"stories":[],"gitRepository":{"localPath":"/tmp/example","remoteUrl":"https://github.com/owner/example.git","defaultBranch":"fs-user-stories","lastSyncedDigest":"digest","lastSyncedAt":"2026-08-14T19:51:25.237584+00:00"}}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let project = try decoder.decode(FSProject.self, from: data)

        XCTAssertEqual(project.gitRepository?.remoteURL, "https://github.com/owner/example.git")
        XCTAssertNotNil(project.gitRepository?.lastSyncedAt)
    }
}
