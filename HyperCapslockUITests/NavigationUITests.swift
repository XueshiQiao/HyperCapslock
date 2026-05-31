import XCTest

/// First XCUITest slice (#16): launch the app under `-uitest` and confirm every
/// sidebar page is reachable by its accessibility identifier, capturing a
/// screenshot of each. We target ids (`nav.*` / `page.*`) — never visible
/// (localized) text, which would break across en/zh/ja/de.
final class NavigationUITests: XCTestCase {

    /// (nav-id stem) for the five sidebar pages. `mappings` is LAST, not first:
    /// the app cold-starts on Mappings, so clicking it first would assert
    /// `page.mappings` exists when it already did — a false green. Reaching it via
    /// a click from `about` makes every assertion a real navigation transition.
    private let pages = ["settings", "actions", "input_source", "about", "mappings"]

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
