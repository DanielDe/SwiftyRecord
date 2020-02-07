import XCTest
@testable import SwiftyRecord

final class SwiftyRecordInsertionAndUpdateTests: XCTestCase {
    private var testUser: User {
        User(
          name: "Winnie Harvey",
          age: 5,
          isAdmin: false
        )
    }

    override func setUp() {
        super.setUp()

        SwiftyRecordTestHelpers.setUpConnection()
    }

    func testSimpleCreation() {
        XCTAssertEqual(try! User.count(), 0)
        let _ = try! self.testUser.save()
        XCTAssertEqual(try! User.count(), 1)
    }

    func testReturnedId() {
        let user = self.testUser
        XCTAssert(user.id == nil)

        let savedUser = try! user.save()
        XCTAssert(savedUser.id != nil)
    }

    func testUpdate() {
        let _ = try! self.testUser.save()

        let beforeUser = try! User.last()!
        XCTAssertEqual(beforeUser.name, "Winnie Harvey")

        var afterUser = try! User.last()!
        afterUser.name = "Ellie Harvey"
        let _ = try! afterUser.save()
        XCTAssertEqual(afterUser.name, "Ellie Harvey")
    }
}
