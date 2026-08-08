import XCTest
@testable import ZhuZhiLiao

final class AboutViewTests: XCTestCase {
    func testPublicLinksUseDedicatedHTTPSPages() {
        let links = [
            AppLinks.website,
            AppLinks.support,
            AppLinks.privacyPolicy,
            AppLinks.privacyChoices
        ]

        for link in links {
            XCTAssertEqual(link.scheme, "https")
            XCTAssertEqual(link.host, "andforce.github.io")
            XCTAssertFalse(link.path.contains("/issues"))
            XCTAssertFalse(link.path.contains("/blob/"))
        }

        XCTAssertEqual(AppLinks.support.path, "/ZhuZhiLiao/support")
        XCTAssertEqual(AppLinks.privacyPolicy.path, "/ZhuZhiLiao/privacy")
    }

    func testPrivacyChoicesLinksToDataControlSection() {
        XCTAssertEqual(AppLinks.privacyChoices.path, AppLinks.privacyPolicy.path)
        XCTAssertEqual(AppLinks.privacyChoices.fragment, "data-control")
    }
}
