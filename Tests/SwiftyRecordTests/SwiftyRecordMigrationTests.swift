import XCTest
@testable import SwiftyRecord

final class SwiftyRecordMigrationTest: XCTestCase {
    private var schema: SwiftyRecordSchema!

    override func setUp() {
        super.setUp()
    }

    func setUpUsersAndMacrosSchema() {
        self.schema = SwiftyRecordSchema.schema(
          fromMigrations: [SwiftyRecordTestHelpers.usersAndMacrosMigration]
        )
    }

    func setUpActionsMigration() {
        self.schema = SwiftyRecordSchema.schema(
          fromMigrations: [
            SwiftyRecordTestHelpers.usersAndMacrosMigration,
            SwiftyRecordTestHelpers.addColumnsMigrations,
            SwiftyRecordTestHelpers.addActionsMigration
          ]
        )
    }

    func testTableNames() {
        self.setUpUsersAndMacrosSchema()

        XCTAssertEqual(self.schema.tables.map { $0.name }.sorted(), ["macros", "users"])
    }

    func testUsersTable() {
        self.setUpUsersAndMacrosSchema()

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
        self.setUpUsersAndMacrosSchema()

        let macrosTable = self.schema.table(named: "macros")
        let sortedColumns = macrosTable.columns.sorted(by: { c1, c2 in c1.columnName < c2.columnName })

        XCTAssertEqual(sortedColumns.map { $0.columnName }, ["isEnabled", "name"])
        XCTAssert(sortedColumns[0].columnType == Bool.self)
        XCTAssert(sortedColumns[1].columnType == String.self)

        XCTAssertEqual(macrosTable.relationships.count, 1)

        let relationship = macrosTable.relationships.first!
        XCTAssertEqual(relationship.relationshipType, .belongsTo)
        XCTAssertEqual(relationship.relationshipName, "user")
        XCTAssertEqual(relationship.foreignKeyName, "userId")
    }

    // TODO: AddColumnOperation

    func testAddRelationship() {
        self.setUpActionsMigration()

        let macrosTable = self.schema.table(named: "macros")

        XCTAssertEqual(macrosTable.relationships.count, 2)

        let actionsRelationship = macrosTable.relationships.first(
          where: { relationship in relationship.relationshipName == "actions" }
        )!
        XCTAssertEqual(actionsRelationship.relationshipType, .hasMany)
        XCTAssertEqual(actionsRelationship.foreignKeyName, "macroId")

        let actionsTable = self.schema.table(named: "actions")
        XCTAssertEqual(actionsTable.relationships.count, 1)

        let macroRelationship = actionsTable.relationships.first!
        XCTAssertEqual(macroRelationship.relationshipType, .belongsTo)
        XCTAssertEqual(macroRelationship.relationshipName, "macro")
        XCTAssertEqual(macroRelationship.foreignKeyName, "macroId")
    }
}
