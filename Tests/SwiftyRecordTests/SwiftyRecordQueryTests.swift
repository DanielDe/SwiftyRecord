import XCTest
@testable import SwiftyRecord

final class SwiftyRecordQueryTests: XCTestCase {
    private var testUsers: [User] {
        [
          User(name: "Winnie Harvey", age: 5, isAdmin: false),
          User(name: "Ellie Harvey", age: 24, isAdmin: true),
          User(name: "Daniel Moreh", age: 27, isAdmin: true),
          User(name: "Mike Robbins", age: 35, isAdmin: false),
          User(name: "Eric Bakan", age: 25, isAdmin: false)
        ]
    }

    override func setUp() {
        super.setUp()

        SwiftyRecordTestHelpers.setUpConnection()
        self.testUsers.forEach { user in
            let _ = try! user.save()
        }
    }

    func testQueryAll() {
        XCTAssertEqual(try! User.findAll().count(), 5)
    }

    func testSingleFilter() {
        XCTAssertEqual(try! User.findAll(where: ["age" > 10]).count(), 4)
        XCTAssertEqual(try! User.findAll(where: ["age" <= 25]).count(), 3)
    }

    func testMultipleFilters() {
        XCTAssertEqual(try! User.findAll(where: ["age" > 10, "isAdmin" === true]).count(), 2)
    }

    func testOrdering() {
        XCTAssertEqual(try! User.findAll().order(by: "age").first()!.name, "Winnie Harvey")
        XCTAssertEqual(try! User.findAll().order(by: "age", .descending).first()!.name, "Mike Robbins")
    }

    func testLimit() {
        XCTAssertEqual(try! User.findAll().execute().count, 5)
        XCTAssertEqual(try! User.findAll().limit(2).execute().count, 2)
        XCTAssertEqual(try! User.findAll().limit(1).execute().count, 1)
    }
}
