import XCTest

/// First XCUITest slice (#16): launch the app under `-uitest` and confirm every
/// sidebar page is reachable by its accessibility identifier, capturing a
/// screenshot of each. We target ids (`nav.*` / `page.*`) — never visible
/// (localized) text, which would break across en/zh/ja/de.
final class NavigationUITests: XCTestCase {

    /// (nav-id stem) for the five sidebar pages, in sidebar order.
    private let pages = ["mappings", "settings", "actions", "input_source", "about"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNavigatesEveryPageAndCaptures() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()

        for page in pages {
            let row = app.descendants(matching: .any)["nav.\(page)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10),
                          "sidebar row 'nav.\(page)' should exist")
            row.click()

            // The detail root carries `page.<id>` — its appearance proves the
            // click actually drove List selection (not just registered a hit).
            let root = app.descendants(matching: .any)["page.\(page)"]
            XCTAssertTrue(root.waitForExistence(timeout: 10),
                          "detail root 'page.\(page)' should appear after selecting 'nav.\(page)'")

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "page-\(page)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
