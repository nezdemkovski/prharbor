import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

struct CICheckTests {
    @Test
    func doesNotReuseChecksFromAnotherPullRequest() throws {
        let firstURL = try #require(URL(string: "https://github.com/checks/first"))
        let secondURL = try #require(URL(string: "https://github.com/checks/second"))
        let first = commits(checkName: "build", conclusion: "SUCCESS", url: firstURL)
        let second = commits(checkName: "build", conclusion: "FAILURE", url: secondURL)

        #expect(CICheck.from(commits: first) == [
            CICheck(name: "build", status: "SUCCESS", url: firstURL, index: 0)
        ])
        #expect(CICheck.from(commits: second) == [
            CICheck(name: "build", status: "FAILURE", url: secondURL, index: 0)
        ])
    }

    @Test(arguments: ["FAILURE", "ERROR", "CANCELLED", "STALE", "STARTUP_FAILURE", "TIMED_OUT"])
    func recognizesFailureStates(_ status: String) {
        #expect(ciStatusKind(status) == .failure)
    }

    @Test
    func legacyDetailsCanEstablishTroubleButNeverProveSuccess() {
        let url = URL(string: "https://github.com/checks/build")!
        #expect(ciAggregateStatus(nil) == nil)
        #expect(ciAggregateStatus(commits(checkName: "build", conclusion: "SUCCESS", url: url)) == nil)
        #expect(ciAggregateStatus(commits(checkName: "build", conclusion: "IN_PROGRESS", url: url)) == .pending)
        #expect(ciAggregateStatus(commits(checkName: "build", conclusion: "FAILURE", url: url)) == .failure)
    }

    private func commits(checkName: String, conclusion: String, url: URL) -> CommitsNodes {
        CommitsNodes(nodes: [
            Commit(commit: CheckSuites(
                checkSuites: CheckSuitsNodes(nodes: [
                    CheckSuit(
                        app: nil,
                        checkRuns: CheckRun(
                            totalCount: 1,
                            nodes: [Check(name: checkName, conclusion: conclusion, detailsUrl: url)]
                        )
                    )
                ]),
                statusCheckRollup: nil
            ))
        ])
    }
}
