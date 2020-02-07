import XCTest
@testable import SwiftyRecord

struct SwiftyRecordTestHelpers {
    static var usersAndMacrosMigration: SwiftyRecordMigration = {
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
    }()

    static var addIsAdminColumnMigration: SwiftyRecordMigration = {
        SwiftyRecordMigration("Add isAdmin column to users") {
            AddColumnOperation(toTable: "users", named: "isAdmin", ofType: Bool.self)
        }
    }()

    static func setUpConnection() {
        let databasePath = "/tmp/db.sqlite3"
        try? FileManager.default.removeItem(atPath: databasePath)

        let connection = SwiftyRecordSQLite3Connection.shared
        try! connection.initialize(withPathToDatabase: databasePath)
        try! connection.prepareDatabase(
          withMigrations: [
            SwiftyRecordTestHelpers.usersAndMacrosMigration,
            SwiftyRecordTestHelpers.addIsAdminColumnMigration
          ]
        )
    }
}

struct User: SwiftyRecord {
    static let tableName = "users"

    let id: Int64? = nil
    var name: String
    var age: Int64
    var isAdmin: Bool
    var createdAt: Date?
    var updatedAt: Date?

    @HasMany var macros: SwiftyRecordCollection<Macro>
}

struct Macro: SwiftyRecord {
    static let tableName = "macros"

    let id: Int64? = nil
    var name: String
    var isEnabled: Bool
    var userId: Int64
    var createdAt: Date?
    var updatedAt: Date?

    @BelongsTo var user: User?
}
