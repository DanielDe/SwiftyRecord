import Foundation

@_functionBuilder
struct MigrationBuilder {
    static func buildBlock(_ operations: MigrationOperation...) -> [MigrationOperation] {
        operations
    }
}

struct SwiftyRecordMigration {
    let name: String
    let operations: [MigrationOperation]

    init(name: String, operations: [MigrationOperation]) {
        self.name = name
        self.operations = operations
    }

    init(_ name: String, @MigrationBuilder _ generator: () -> [MigrationOperation]) {
        self.init(name: name, operations: generator())
    }

    init(_ name: String, @MigrationBuilder _ generator: () -> MigrationOperation) {
        self.init(name: name, operations: [generator()])
    }
}

@_functionBuilder
struct CreateTableOperationBuilder {
    static func buildBlock(_ operations: TableCreationSubOperation...) -> [TableCreationSubOperation] {
        operations
    }
}

protocol MigrationOperation {
    var sql: String { get }
}

struct CreateTableOperation: MigrationOperation {
    let tableName: String
    let columns: [TableColumn]
    let relationships: [Relationship]

    init(_ tableName: String, @CreateTableOperationBuilder _ generator: () -> [TableCreationSubOperation]) {
        self.tableName = tableName

        var _columns: [TableColumn] = []
        var _relationships: [Relationship] = []

        let subOperations = generator()
        subOperations.forEach { subOperation in
            switch subOperation {
            case let subOperation as TableColumn:
                _columns.append(subOperation)
            case let subOperation as Relationship:
                _relationships.append(subOperation)
            default:
                fatalError("Unrecognized subOperation type: \(subOperation)")
            }
        }

        self.columns = _columns
        self.relationships = _relationships
    }

    init(_ tableName: String, @CreateTableOperationBuilder _ generator: () -> TableCreationSubOperation) {
        self.tableName = tableName

        let subOperation = generator()
        switch subOperation {
        case let subOperation as TableColumn:
            self.columns = [subOperation]
            self.relationships = []
        case let subOperation as Relationship:
            self.columns = []
            self.relationships = [subOperation]
        default:
            fatalError("Unrecognized subOperation type: \(subOperation)")
        }
    }

    var sql: String {
        """
          CREATE TABLE \(self.tableName) (
            id INTEGER PRIMARY KEY,
            createdAt TEXT,
            updatedAt TEXT,
            \(self.columns.map { $0.sql }.joined(separator: ",\n   "))
          )
        """
    }
}

protocol TableCreationSubOperation {}

struct TableColumn: TableCreationSubOperation {
    let columnName: String
    let columnType: SwiftyRecordColumnType.Type

    init(_ columnName: String, _ columnType: SwiftyRecordColumnType.Type) {
        self.columnName = columnName
        self.columnType = columnType
    }

    var sql: String {
        "\(self.columnName) \(SwiftyRecordSQLite3Adapter.typeName(forType: self.columnType))"
    }
}

enum RelationshipType: String {
    case hasMany
    case belongsTo
}

struct Relationship: TableCreationSubOperation {
    let relationshipType: RelationshipType
    let relationshipName: String
    let foreignKeyName: String

    init(_ relationshipType: RelationshipType, _ relationshipName: String, via foreignKeyName: String) {
        self.relationshipType = relationshipType
        self.relationshipName = relationshipName
        self.foreignKeyName = foreignKeyName
    }
}

struct AddColumnOperation: MigrationOperation {
    let tableName: String
    let columnName: String
    let columnType: SwiftyRecordColumnType.Type

    init(toTable tableName: String, named columnName: String, ofType columnType: SwiftyRecordColumnType.Type) {
        self.tableName = tableName
        self.columnName = columnName
        self.columnType = columnType
    }

    var sql: String {
        """
          ALTER TABLE \(self.tableName)
           ADD COLUMN \(self.columnName) \(SwiftyRecordSQLite3Adapter.typeName(forType: self.columnType))
        """
    }
}

class Table {
    var name: String
    var columns: [TableColumn]
    var relationships: [Relationship]

    init(name: String, columns: [TableColumn], relationships: [Relationship]) {
        self.name = name
        self.columns = columns
        self.relationships = relationships
    }
}

class SwiftyRecordSchema: CustomStringConvertible {
    var tables: [Table]

    init(tables: [Table]) {
        self.tables = tables
    }

    static func schema(fromMigrations migrations: [SwiftyRecordMigration]) -> SwiftyRecordSchema {
        var tablesMap: [String: Table] = [:]

        migrations.forEach { migration in
            migration.operations.forEach { operation in
                switch operation {
                case let operation as CreateTableOperation:
                    tablesMap[operation.tableName] = Table(
                        name: operation.tableName,
                        columns: operation.columns,
                        relationships: operation.relationships
                    )
                case let operation as AddColumnOperation:
                    let table = tablesMap[operation.tableName]!
                    table.columns += [TableColumn(operation.columnName, operation.columnType)]
                default:
                    fatalError("Unhandled migration operation type in schema generation")
                }
            }
        }

        return SwiftyRecordSchema(tables: Array(tablesMap.values))
    }

    public var description: String {
        let tableDescriptions = self.tables.map { table -> String in
            let columnDescriptions = table.columns.map { column in
                "    | \(column.columnName) \(column.columnType)"
            }
            let relationshipDescriptions = table.relationships.map { relationship in
                "    > \(relationship.relationshipType) \(relationship.relationshipName) via \(relationship.foreignKeyName)"
            }

            return """
              \(table.name)
              \(columnDescriptions.joined(separator: "\n  "))
              \(relationshipDescriptions.joined(separator: "\n  "))
            """
        }

        return """
        <SwiftyRecordSchema
          num-tables=\(self.tables.count)
          \(tableDescriptions.joined(separator: "\n  "))
          >
        """
    }

    func table(named tableName: String) -> Table {
        self.tables.first(where: { table in table.name == tableName })!
    }
}
