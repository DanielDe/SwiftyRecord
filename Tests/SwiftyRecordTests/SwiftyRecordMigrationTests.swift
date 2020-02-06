import XCTest
@testable import SwiftyRecord

final class SwiftyRecordMigrationTest: XCTestCase {
    private var schema: SwiftyRecordSchema!

    var usersAndMacrosMigration: SwiftyRecordMigration {
        SwiftyRecordMigration("create users and macros tables") {
            CreateTableOperation("users") {
                TableColumn("name", String.self)
                TableColumn("age", Int.self)
                Relationship(.hasMany, "macros", via: "userId")
            }

            CreateTableOperation("macros") {
                TableColumn("name", String.self)
                TableColumn("isEnabled", Bool.self)
                Relationship(.belongsTo, "user", via: "userId")
            }
        }
    }

    override func setUp() {
        super.setUp()


        self.schema = SwiftyRecordSchema.schema(fromMigrations: [self.usersAndMacrosMigration])
    }

    func testTableNames() {
        XCTAssertEqual(self.schema.tables.map { $0.name }.sorted(), ["macros", "users"])
    }

    func testUsersTable() {
        let usersTable = self.schema.table(named: "users")
        let sortedColumns = usersTable.columns.sorted(by: { c1, c2 in c1.columnName < c2.columnName })

        XCTAssertEqual(sortedColumns.map { $0.columnName }, ["age", "name"])
        XCTAssert(sortedColumns[0].columnType == Int.self)
        XCTAssert(sortedColumns[1].columnType == String.self)

        let relationship = usersTable.relationships.first!
        XCTAssertEqual(relationship.relationshipType, .hasMany)
        XCTAssertEqual(relationship.relationshipName, "macros")
        XCTAssertEqual(relationship.foreignKeyName, "userId")
    }

    func testMacrosTable() {
        let macrosTable = self.schema.table(named: "macros")
        let sortedColumns = macrosTable.columns.sorted(by: { c1, c2 in c1.columnName < c2.columnName })

        XCTAssertEqual(sortedColumns.map { $0.columnName }, ["isEnabled", "name"])
        XCTAssert(sortedColumns[0].columnType == Bool.self)
        XCTAssert(sortedColumns[1].columnType == String.self)

        let relationship = macrosTable.relationships.first!
        XCTAssertEqual(relationship.relationshipType, .belongsTo)
        XCTAssertEqual(relationship.relationshipName, "user")
        XCTAssertEqual(relationship.foreignKeyName, "userId")
    }

    // TODO: AddColumnOperation
}
