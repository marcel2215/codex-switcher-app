//
//  Tests.swift
//  Codex Switcher Mac UI Tests
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import XCTest

final class Tests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUnlinkedStateShowsLinkBanner() throws {
        let app = launchApp(for: "unlinked")

        XCTAssertTrue(app.staticTexts["Link Codex Folder"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Choose the Codex folder that contains auth.json."].exists)
        XCTAssertEqual(app.buttons["auth-link-button"].label, "Link Codex Folder")
    }

    @MainActor
    func testMissingAuthFileStateDoesNotShowBanner() throws {
        let app = launchApp(for: "missing-auth-file")

        XCTAssertFalse(app.staticTexts["Link Codex Folder"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["Unsupported Credential Store"].exists)
    }

    @MainActor
    func testUnsupportedCredentialStoreStateShowsModeExplanation() throws {
        let app = launchApp(for: "unsupported-credential-store")

        XCTAssertTrue(app.staticTexts["Unsupported Credential Store"].waitForExistence(timeout: 4))

        let explanation = app.staticTexts["auth-status-message"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["auth-link-button"].label, "Relink Codex Folder")
        XCTAssertTrue(app.buttons["auth-refresh-button"].exists)
    }

    @MainActor
    private func launchApp(for scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_SWITCHER_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }
}
