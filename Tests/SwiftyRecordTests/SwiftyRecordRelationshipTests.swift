import XCTest
@testable import SwiftyRecord

final class SwiftyRecordRelationshipTests: XCTestCase {
    private var testUsers: [User] {
        [
          User(name: "Winnie Harvey", age: 5, isAdmin: false),
          User(name: "Ellie Harvey", age: 24, isAdmin: true),
          User(name: "Daniel Moreh", age: 27, isAdmin: true),
          User(name: "Mike Robbins", age: 35, isAdmin: false),
          User(name: "Eric Bakan", age: 25, isAdmin: false)
        ]
    }

    private var testMacros: [Macro] {
        [
          Macro(name: "Macro 1", isEnabled: true, userId: 1),
          Macro(name: "Macro 2", isEnabled: false, userId: 1),
          Macro(name: "Macro 3", isEnabled: true, userId: 10)
        ]
    }

    override func setUp() {
        super.setUp()

        SwiftyRecordTestHelpers.setUpConnection()
        self.testUsers.forEach { user in
            let _ = try! user.save()
        }
        self.testMacros.forEach { macro in
            let _ = try! macro.save()
        }
    }

    func testHasManyRelationship() {
        let user1 = try! User.findAll(where: ["id" === 1]).first()!
        XCTAssertEqual(try! user1.macros.count(), 2)

        let user3 = try! User.findAll(where: ["id" === 3]).first()!
        XCTAssertEqual(try! user3.macros.count(), 0)
    }

    func testBelongsToRelationship() {
        let macro1 = try! Macro.findAll(where: ["id" === 1]).first()!
        XCTAssert(macro1.user != nil)

        let macro3 = try! Macro.findAll(where: ["id" === 3]).first()!
        XCTAssert(macro3.user == nil)
    }
}
