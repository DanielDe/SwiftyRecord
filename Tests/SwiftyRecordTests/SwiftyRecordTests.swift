import XCTest
@testable import SwiftyRecord

final class SwiftyRecordTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(SwiftyRecord().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}