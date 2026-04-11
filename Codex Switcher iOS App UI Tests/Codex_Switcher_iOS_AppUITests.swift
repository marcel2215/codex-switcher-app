//
//  Codex_Switcher_iOS_AppUITests.swift
//  Codex Switcher iOS AppUITests
//
//  Created by Codex on 2026-04-11.
//

import XCTest

final class Codex_Switcher_iOS_AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyStateCopyIsShownWhenThereAreNoAccounts() throws {
        let app = launchApp(scenario: "empty")

        XCTAssertTrue(app.staticTexts["No Accounts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Accounts captured in Codex Switcher on your Mac appear here through iCloud."].exists)
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
        XCTAssertTrue(app.staticTexts["Version"].exists)
        XCTAssertTrue(app.staticTexts["Build"].exists)
        XCTAssertTrue(app.staticTexts["Contact Us"].exists)
        XCTAssertTrue(app.staticTexts["Privacy Policy"].exists)
        XCTAssertTrue(app.staticTexts["Source Code"].exists)
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
}
