//
//  Tests.swift
//  Codex Switcher iOS AppUITests
//
//  Created by Codex on 2026-04-11.
//

import XCTest

final class Tests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyStateCopyIsShownWhenThereAreNoAccounts() throws {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.staticTexts["No Accounts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Accounts added in Codex Switcher on your Mac will appear here."].exists)
    }

    @MainActor
    func testSampleLaunchDoesNotExposeAddOrSwitchActions() throws {
        let app = launchApp(scenario: "sample-data")

        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Account"].exists)
        XCTAssertFalse(app.buttons["Switch"].exists)
        XCTAssertFalse(app.buttons["Log In"].exists)
    }

    @MainActor
    func testSettingsShowsVersionBuildAndLinks() throws {
        let app = launchApp(scenario: "sample-data")

        app.buttons["ios-settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            settingsViewContainsText(named: "Version", in: app),
            "Expected the About section to include the Version row."
        )

        let expectedActions = [
            "Contact Us",
            "Visit Our Website",
            "Terms of Service",
            "Privacy Policy",
            "Source Code",
            "More Settings"
        ]

        for action in expectedActions {
            XCTAssertTrue(
                settingsViewContainsText(named: action, in: app),
                "Expected settings action '\(action)' to be visible in the list."
            )
        }
    }

    @MainActor
    func testCustomOrderOnlyShowsEditButtonWhenReorderingIsAllowed() throws {
        let app = launchApp(scenario: "sample-data")

        XCTAssertFalse(app.buttons["Edit"].exists)

        app.buttons["ios-sort-button"].tap()
        app.buttons["Custom"].tap()

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))

        let searchField = app.searchFields["Search"]
        searchField.tap()
        searchField.typeText("work")

        XCTAssertFalse(app.buttons["Edit"].exists)
    }

    @MainActor
    func testSwipeDeleteRemovesAccountFromTheList() throws {
        let app = launchApp(scenario: "sample-data")
        let workRow = app.staticTexts["Work"]

        XCTAssertTrue(workRow.waitForExistence(timeout: 5))
        workRow.swipeLeft()
        app.buttons["Remove"].tap()
        app.buttons["Remove Account"].tap()

        XCTAssertFalse(workRow.waitForExistence(timeout: 2))
    }

    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CODEX_SWITCHER_IOS_LAUNCH_SCENARIO"] = scenario
        app.launch()
        return app
    }

    private func settingsViewContainsText(named name: String, in app: XCUIApplication) -> Bool {
        let target = app.staticTexts[name].firstMatch
        if target.waitForExistence(timeout: 1) {
            return true
        }

        // SwiftUI Form rows are lazily realized, so lower actions only exist after scrolling them into view.
        let scrollContainer = settingsScrollContainer(in: app)
        for _ in 0..<8 {
            scrollContainer.swipeUp()
            if target.waitForExistence(timeout: 0.5) {
                return true
            }
        }

        return target.exists
    }

    private func settingsScrollContainer(in app: XCUIApplication) -> XCUIElement {
        let collectionView = app.collectionViews.firstMatch
        if collectionView.exists {
            return collectionView
        }

        let table = app.tables.firstMatch
        if table.exists {
            return table
        }

        return app.scrollViews.firstMatch
    }
}
