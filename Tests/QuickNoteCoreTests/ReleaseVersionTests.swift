import XCTest
@testable import QuickNoteCore
final class ReleaseVersionTests: XCTestCase {
    func testNumericOrderingAndNormalization() {
        XCTAssertGreaterThan(ReleaseVersion("v1.10.0")!, ReleaseVersion("1.9.9")!)
        XCTAssertEqual(ReleaseVersion("1.2"), ReleaseVersion("1.2.0"))
        XCTAssertLessThan(ReleaseVersion("1.0.2")!, ReleaseVersion("2.0.0")!)
    }
    func testRejectsPrereleaseAndInvalidTags() {
        for value in ["1.2.3-beta", "", "1..2", "1", "1.2.3.4", "-1.2", "latest"] { XCTAssertNil(ReleaseVersion(value), value) }
    }
}
