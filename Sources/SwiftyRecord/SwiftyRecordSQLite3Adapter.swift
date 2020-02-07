import Foundation
import Runtime
import SQLite

// TODO: put more stuff in here that currently just lives on SwiftyRecordSQLite3Connection.
protocol SwiftyRecordDatabaseConnection {}

// TODO: add the execute(...) function to this protocol.
protocol SwiftyRecordDatabaseAdapter {
    static func typeName(forType type: SwiftyRecordColumnType.Type) -> String
}

struct SelectQueryResult {
    let columnNames: [String]
    let results: [[Any?]]
}

struct SwiftyRecordSQLite3Adapter: SwiftyRecordDatabaseAdapter {
    static func typeName(forType type: SwiftyRecordColumnType.Type) -> String {
        switch type {
        case is String.Type:
            return "TEXT"
        case is Int.Type:
            return "INTEGER"
        case is Double.Type:
            return "DOUBLE"
        case is Bool.Type:
            return "BOOLEAN"
        default:
            fatalError("Unsupported type name")
        }
    }
}

struct WhereQueryParts {
    let whereClause: String
    let valueBindings: [Binding]
}

struct SelectQueryParts {
    let fromClause: String
    let whereClause: String
    let orderClause: String
    let limitClause: String
    let valueBindings: [Binding]

    var querySuffix: String {
        "\(self.fromClause) \(self.whereClause) \(self.orderClause) \(self.limitClause)"
    }
}

extension SwiftyRecordSQLite3Adapter {
    static func whereQueryPart<RecordType: SwiftyRecord>(
        forCollection collection: SwiftyRecordCollection<RecordType>,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> WhereQueryParts {
        var whereClauseExpressions: [String] = []
        var sortedFilterValues: [Binding] = []
        collection.filters.forEach { filter in
            switch filter {
            case is NeverMatchFilter:
                whereClauseExpressions.append("1 = 0")
            case let filter as RelationshipFilter:
                let relationship = connection.relationship(
                    inTable: filter.tableName,
                    named: filter.relationshipName
                )

                whereClauseExpressions.append("\(relationship.foreignKeyName) = ?")
                sortedFilterValues.append(filter.id)
            case let filter as PropertyFilter:
                sortedFilterValues.append(filter.filterValue)

                switch filter.filterType {
                case .equal:
                    whereClauseExpressions.append("\(filter.columnName) = ?")
                case .notEqual:
                    whereClauseExpressions.append("\(filter.columnName) <> ?")
                case .lessThan:
                    whereClauseExpressions.append("\(filter.columnName) < ?")
                case .lessThanOrEqualTo:
                    whereClauseExpressions.append("\(filter.columnName) <= ?")
                case .greaterThan:
                    whereClauseExpressions.append("\(filter.columnName) > ?")
                case .greaterThanOrEqualTo:
                    whereClauseExpressions.append("\(filter.columnName) >= ?")
                }
            default:
                fatalError("Unknown filter: \(filter)")
            }
        }
        let whereClause = whereClauseExpressions.isEmpty ? "" : (
            "WHERE " + whereClauseExpressions.joined(separator: " AND ")
        )

        return WhereQueryParts(
            whereClause: whereClause,
            valueBindings: sortedFilterValues
        )
    }

    static func selectQueryParts<RecordType: SwiftyRecord>(
        forCollection collection: SwiftyRecordCollection<RecordType>,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> SelectQueryParts {
        let tableName = RecordType.tableName

        let whereQueryPart = try SwiftyRecordSQLite3Adapter.whereQueryPart(
            forCollection: collection,
            inConnection: connection
        )
        let whereClause = whereQueryPart.whereClause
        let sortedFilterValues = whereQueryPart.valueBindings

        let orderingExpressions = collection.orderings.map { ordering in
            "\(ordering.columnName) \(ordering.order.sqlString)"
        }
        let orderClause = orderingExpressions.isEmpty ?
            "ORDER BY id \(collection.defaultOrdering.sqlString)"
            : "ORDER BY " + orderingExpressions.joined(separator: ", ")

        let limitClause = collection.limit == nil ? "" : "LIMIT \(collection.limit!)"

        return SelectQueryParts(
            fromClause: "FROM \(tableName)",
            whereClause: whereClause,
            orderClause: orderClause,
            limitClause: limitClause,
            valueBindings: sortedFilterValues
        )
    }
}

extension SwiftyRecordSQLite3Adapter {
    static func executeInsertion(
        forRecord record: SwiftyRecord,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> Int64 {
        let recordType = type(of: record)

        let tableName = recordType.tableName
        let sortedColumnNames = recordType.sortedColumnNames(inConnection: connection)

        let runtimeTypeInfo = try! typeInfo(of: recordType)
        let sortedValues = try sortedColumnNames.map { columnName throws -> Binding in
            let property = try runtimeTypeInfo.property(named: columnName)
            return try property.get(from: record)
        }

        let bindingQuestionMarks = sortedValues.map { _ -> String in "?" }.joined(separator: ", ")
        let insertionStatement = """
        INSERT INTO \(tableName) (\(sortedColumnNames.joined(separator: ", ")), createdAt, updatedAt) VALUES (\(bindingQuestionMarks), ?, ?)
        """

        let statement = try connection.connection.prepare(insertionStatement)
        try statement.run(
            (sortedValues + [Date(), Date()]).map { $0.bindableValue }
        )

        return connection.connection.lastInsertRowid
    }

    static func executeUpdate(
        forRecord record: SwiftyRecord,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> Date {
        guard let recordId = record.id else { fatalError("Cannot update a record without an id") }

        let recordType = type(of: record)

        let tableName = recordType.tableName
        let sortedColumnNames = recordType.sortedColumnNames(inConnection: connection)

        let runtimeTypeInfo = try! typeInfo(of: recordType)
        let sortedValues = try sortedColumnNames.map { columnName throws -> Binding in
            let property = try runtimeTypeInfo.property(named: columnName)
            return try property.get(from: record)
        }

        let updateStatement = """
        UPDATE \(tableName)
           SET \(sortedColumnNames.map { columnName in "\(columnName) = ?" }.joined(separator: ", ")), updatedAt = ?
         WHERE id = ?
        """

        let updatedAt = Date()

        let statement = try connection.connection.prepare(updateStatement)
        try statement.run(
            (sortedValues + [updatedAt, recordId]).map { $0.bindableValue }
        )

        return updatedAt
    }

    static func execute(
        selectQuery query: String,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> SelectQueryResult {
        var results: [[Any?]] = []

        let queryResult = try connection.connection.prepare(query)
        for result in queryResult {
            results.append(result)
        }

        return SelectQueryResult(
            columnNames: queryResult.columnNames,
            results: results
        )
    }

    static func executeSelectQuery<RecordType: SwiftyRecord>(
        forCollection collection: SwiftyRecordCollection<RecordType>,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> SelectQueryResult {
        let queryParts = try SwiftyRecordSQLite3Adapter.selectQueryParts(
            forCollection: collection,
            inConnection: connection
        )
        let query = "SELECT * \(queryParts.querySuffix)".squashed.trimmed
        print(">> \(query), \(queryParts.valueBindings)")

        let statement = try connection.connection.prepare(query)
        let queryResult = try statement.run(queryParts.valueBindings.map { $0.bindableValue })

        var results: [[Any?]] = []
        for result in queryResult {
            results.append(result)
        }

        return SelectQueryResult(columnNames: queryResult.columnNames, results: results)
    }

    static func executeCountQuery<RecordType: SwiftyRecord>(
        forCollection collection: SwiftyRecordCollection<RecordType>,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> Int {
        let queryParts = try SwiftyRecordSQLite3Adapter.selectQueryParts(
            forCollection: collection,
            inConnection: connection
        )
        let query = "SELECT COUNT(*) \(queryParts.querySuffix)".squashed.trimmed
        print(">> \(query), \(queryParts.valueBindings)")

        let statement = try connection.connection.prepare(query)
        return Int(try statement.scalar(queryParts.valueBindings.map { $0.bindableValue }) as! Int64)
    }

    static func executeUpdate<RecordType: SwiftyRecord>(
        forCollection collection: SwiftyRecordCollection<RecordType>,
        withPropertyValues propertyValues: [String: SwiftyRecordColumnType],
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws {
        let whereQueryPart = try SwiftyRecordSQLite3Adapter.whereQueryPart(
            forCollection: collection,
            inConnection: connection
        )

        let sortedColumnsAndValues = propertyValues.map { key, value in
            (key, value)
        }.sorted(
            by: { pair1, pair2 in pair1.0 < pair2.0 }
        )

        let setClause = sortedColumnsAndValues.map { columnName, _ in
            "\(columnName) = ?"
        }.joined(separator: ", ")

        let bindings = sortedColumnsAndValues.map { $0.1 } + [Date()] + whereQueryPart.valueBindings
        let query = """
        UPDATE \(RecordType.tableName) SET \(setClause), updatedAt = ? \(whereQueryPart.whereClause)
        """
        print(">> \(query), \(bindings)")

        let statement = try connection.connection.prepare(query)
        try statement.run(bindings.map { $0.bindableValue })
    }

    static func executeDeleteQuery<RecordType: SwiftyRecord>(
      forCollection collection: SwiftyRecordCollection<RecordType>,
      inConnection connection: SwiftyRecordSQLite3Connection
    ) throws {
        let whereQueryPart = try SwiftyRecordSQLite3Adapter.whereQueryPart(
            forCollection: collection,
          inConnection: connection
        )

        let query = "DELETE FROM \(RecordType.tableName) \(whereQueryPart.whereClause)"
        print(">> \(query), \(whereQueryPart.valueBindings)")

        let statement = try connection.connection.prepare(query)
        try statement.run(whereQueryPart.valueBindings.map { $0.bindableValue })
    }
}

extension SwiftyRecordSQLite3Adapter {
    static func reify<RecordType: SwiftyRecord>(
        type: RecordType.Type,
        fromQueryResult queryResult: SelectQueryResult,
        inConnection connection: SwiftyRecordSQLite3Connection
    ) throws -> [RecordType] {
        return try queryResult.results.map { result -> RecordType in
            var recordInstance = try createInstance(of: type) as! RecordType

            let runtimeTypeInfo = try typeInfo(of: type)
            try zip(queryResult.columnNames, result).forEach { columnName, value in
                let property = try runtimeTypeInfo.property(named: columnName)

                if let value = value {
                    if property.type == Bool.self {
                        try property.set(value: (value as! Int64) == 1, on: &recordInstance)
                    } else if property.type == Date.self || property.type == Date?.self {
                        let dateFormatter = ISO8601DateFormatter()
                        try property.set(value: dateFormatter.date(from: value as! String) as Any, on: &recordInstance)
                    } else {
                        try property.set(value: value, on: &recordInstance)
                    }
                }
            }

            // TODO: call this on insertion too.
            try recordInstance.hydrateRelationships(withConnection: connection)

            return recordInstance
        }
    }
}

// https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#executing-arbitrary-sql
class SwiftyRecordSQLite3Connection: SwiftyRecordDatabaseConnection {
    static let shared = SwiftyRecordSQLite3Connection()

    var connection: Connection!
    var schema: SwiftyRecordSchema!

    func initialize(withPathToDatabase path: String) throws {
        self.connection = try Connection(path)
    }

    func createMigrationsTableIfNecessary() throws {
        let doesMigrationsTableExist = try connection.scalar(
            "SELECT 1 FROM sqlite_master WHERE name = 'schema_migrations'"
        ) != nil

        if !doesMigrationsTableExist {
            try self.connection.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY)")
        }
    }

    func insertMigration(version: String) throws {
        try self.connection.prepare(
            "INSERT INTO schema_migrations (version) VALUES (?)"
        ).run(version)
    }

    func prepareDatabase(withMigrations migrations: [SwiftyRecordMigration]) throws {
        try self.createMigrationsTableIfNecessary()

        // TODO: verify that all migration IDs are unique.

        let alreadyRunMigrationVersions = try SwiftyRecordSQLite3Adapter.execute(
            selectQuery: "SELECT version FROM schema_migrations",
            inConnection: self
        ).results.map { $0[0] as! String }

        try migrations.filter { migration in
            !alreadyRunMigrationVersions.contains(migration.name)
        }.forEach { migration in
            try migration.operations.compactMap { operation in
                operation.sql
            }.forEach { sql in
                try self.connection.execute(sql)
            }

            try self.insertMigration(version: migration.name)
        }

        self.schema = SwiftyRecordSchema.schema(fromMigrations: migrations)
    }

    func relationship(inTable tableName: String, named relationshipName: String) -> Relationship {
        self.schema.table(named: tableName).relationships.first(
            where: { relationship in relationship.relationshipName == relationshipName }
        )!
    }

    func sortedColumnNames(forTableNamed tableName: String) -> [String] {
        self.schema.table(named: tableName).columns.map { column in column.columnName }.sorted()
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var squashed: String {
        try! NSRegularExpression(pattern: "\\s+").stringByReplacingMatches(
            in: self,
            options: [],
            range: NSMakeRange(0, count),
            withTemplate: " "
        )
    }
}
