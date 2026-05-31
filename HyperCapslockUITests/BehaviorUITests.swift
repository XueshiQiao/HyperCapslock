import XCTest

/// #17 — behavioral XCUITest flows that go beyond navigation: change the UI
/// language, and create a brand-new mapping through the "+" sheet. Both drive
/// real interactions (menu pickers, a presented sheet) and assert the outcome.
final class BehaviorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
    }

    /// Open a `.menu`-style Picker by accessibility id and click the menu item
    /// whose label contains `substring` (substring match keeps us off exact,
    /// flag-prefixed labels like "🇯🇵  日本語").
    private func selectMenuItem(in app: XCUIApplication, pickerID: String, containing substring: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let picker = app.descendants(matching: .any)[pickerID]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "picker '\(pickerID)' should exist", file: file, line: line)
        picker.click()
        // SwiftUI menu-Picker items expose their text via `title` (the `label` is
        // empty) — confirmed via an XCUITest element-tree dump — so match on title.
        // NOTE: queried on `app.menuItems` (the verified-passing form). Scoping to
        // `picker.menuItems` to avoid the ~90 macOS menu-bar items is a safe
        // follow-up, but must be re-verified on an unlocked screen first.
        let item = app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", substring)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu item with title containing '\(substring)' should appear", file: file, line: line)
        item.click()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Switch the UI language English → Japanese, confirm it re-localizes, then
    /// switch back to English to leave the app as we found it.
    func testChangeLanguage() throws {
        let app = launchedApp()

        let settings = app.descendants(matching: .any)["nav.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.click()

        selectMenuItem(in: app, pickerID: "settings.language", containing: "日本語")
        XCTAssertTrue(app.staticTexts["設定"].waitForExistence(timeout: 5),
                      "the Settings sidebar row should re-localize to '設定'")
        attach(app, "language-japanese")

        // Tidy up: back to English.
        selectMenuItem(in: app, pickerID: "settings.language", containing: "English")
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5),
                      "the Settings sidebar row should revert to 'Settings'")
    }

    /// Create a new "Single-tap Caps" mapping through the + sheet. Uses a tap
    /// trigger so no custom key-capture field is needed; the default action
    /// (Move Left) is already valid, so Save enables once the trigger is chosen.
    func testCreateMapping() throws {
        let app = launchedApp()

        let addButton = app.descendants(matching: .any)["mappings.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.click()

        selectMenuItem(in: app, pickerID: "mapping.trigger", containing: "Single-tap Caps")

        let save = app.descendants(matching: .any)["mapping.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save should be enabled once a tap trigger is chosen")
        save.click()

        // The success toast text is only shown when upsertMapping actually succeeded.
        XCTAssertTrue(app.staticTexts["Action mapping saved"].waitForExistence(timeout: 5),
                      "creating the mapping should surface the success toast")
        attach(app, "mapping-created")
    }
}
