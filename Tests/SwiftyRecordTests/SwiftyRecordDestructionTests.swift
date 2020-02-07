import XCTest
@testable import SwiftyRecord

final class SwiftyRecordDestructionTests: XCTestCase {
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

    func testDestroyOne() {
        XCTAssertEqual(try! User.count(), 5)

        let dan = try! User.findAll(where: ["name" === "Daniel Moreh"]).first()!
        try! dan.destroy() // Sorry, Dan.

        XCTAssertEqual(try! User.count(), 4)
    }

    func testDestroyCollection() {
        XCTAssertEqual(try! User.count(), 5)

        try! User.findAll(where: ["age" > 25]).destroyAll()

        XCTAssertEqual(try! User.count(), 3)
    }

    func testDestroyAll() {
        XCTAssertEqual(try! User.count(), 5)

        try! User.destroyAll()

        XCTAssertEqual(try! User.count(), 0)
    }
}
