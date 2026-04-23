//
//  CodexSwitcherUITests.swift
//  Codex SwitcherUITests
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import XCTest

final class CodexSwitcherUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUnlinkedStateShowsLinkBanner() throws {
        let app = launchApp(for: "unlinked")

        XCTAssertTrue(app.otherElements["auth-status-banner"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["auth-status-title"].label, "Link Codex Folder")
        XCTAssertEqual(
            app.staticTexts["auth-status-message"].label,
            "Choose the Codex folder that contains auth.json."
        )
        XCTAssertEqual(app.buttons["auth-link-button"].label, "Link Codex Folder")
    }

    @MainActor
    func testMissingAuthFileStateDoesNotShowBanner() throws {
        let app = launchApp(for: "missing-auth-file")

        XCTAssertFalse(app.otherElements["auth-status-banner"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testUnsupportedCredentialStoreStateShowsModeExplanation() throws {
        let app = launchApp(for: "unsupported-credential-store")

        XCTAssertTrue(app.otherElements["auth-status-banner"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["auth-status-title"].label, "Unsupported Credential Store")
        XCTAssertTrue(app.staticTexts["auth-status-message"].label.contains("configured for auto credential storage"))
        XCTAssertTrue(app.staticTexts["auth-status-message"].label.contains("only supports file-backed auth.json switching"))
        XCTAssertEqual(app.buttons["auth-link-button"].label, "Relink Codex Folder")
        XCTAssertTrue(app.buttons["auth-refresh-button"].exists)
    }

    private func launchApp(for scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_SWITCHER_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }
}
