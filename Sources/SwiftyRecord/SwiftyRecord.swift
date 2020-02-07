import Foundation
import Runtime
import SQLite

protocol SwiftyRecordColumnType: Binding {
    var bindableValue: Binding { get }
}

extension String: SwiftyRecordColumnType {}
extension Int: SwiftyRecordColumnType {}
extension Int64: SwiftyRecordColumnType {}
extension Double: SwiftyRecordColumnType {}
extension Bool: SwiftyRecordColumnType {}
extension Date: SwiftyRecordColumnType {}

extension Binding {
    var bindableValue: Binding {
        switch self {
        case let bindableDate as Date:
            let dateFormatter = ISO8601DateFormatter()
            return dateFormatter.string(from: bindableDate)
        default:
            return self
        }
    }
}

enum SwiftyRecordOrder {
    case ascending
    case descending

    var sqlString: String {
        switch self {
        case .ascending:
            return "ASC"
        case .descending:
            return "DESC"
        }
    }

    var opposite: SwiftyRecordOrder {
        switch self {
        case .ascending:
            return .descending
        case .descending:
            return .ascending
        }
    }
}

struct SwiftyRecordOrdering {
    let columnName: String
    let order: SwiftyRecordOrder

    var reversed: SwiftyRecordOrdering {
        SwiftyRecordOrdering(
            columnName: self.columnName,
            order: self.order.opposite
        )
    }
}

enum SwiftyRecordFilteringType {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqualTo
    case greaterThan
    case greaterThanOrEqualTo
}

typealias ColumnName = String

protocol SwiftyRecordFilter {}

struct RelationshipFilter: SwiftyRecordFilter {
    let id: Int64
    let tableName: String
    let relationshipName: String
}

struct NeverMatchFilter: SwiftyRecordFilter {}

struct PropertyFilter: SwiftyRecordFilter {
    let columnName: ColumnName
    let filterType: SwiftyRecordFilteringType
    let filterValue: SwiftyRecordColumnType
}

func ===(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .equal,
        filterValue: right
    )
}

func !==(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .notEqual,
        filterValue: right
    )
}

func >(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .greaterThan,
        filterValue: right
    )
}

func >=(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .greaterThanOrEqualTo,
        filterValue: right
    )
}

func <(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .lessThan,
        filterValue: right
    )
}

func <=(left: ColumnName, right: SwiftyRecordColumnType) -> PropertyFilter {
    PropertyFilter(
        columnName: left,
        filterType: .lessThanOrEqualTo,
        filterValue: right
    )
}

// TODO: figure out what goes in here.
protocol SwiftyRecordRelationship: AnyObject {
    var relationshipName: String? { get set }
    var enclosingRecord: SwiftyRecord? { get set }
    var connection: SwiftyRecordSQLite3Connection? { get set }
}

@propertyWrapper
class BelongsTo<RecordType: SwiftyRecord>: SwiftyRecordRelationship {
    var relationshipName: String?
    var enclosingRecord: SwiftyRecord?
    var connection: SwiftyRecordSQLite3Connection?

    var relationship: Relationship {
        guard let relationshipName = self.relationshipName else { fatalError("relationshipName is nil") }
        guard let enclosingRecord = self.enclosingRecord else { fatalError("enclosingRecord is nil") }
        guard let connection = self.connection else { fatalError("connection is nil") }

        return connection.relationship(
            inTable: type(of: enclosingRecord).tableName,
            named: relationshipName
        )
    }

    var property: PropertyInfo {
        guard let enclosingRecord = self.enclosingRecord else { fatalError("enclosingRecord is nil") }

        let runtimeTypeInfo = try! typeInfo(of: type(of: enclosingRecord))
        return try! runtimeTypeInfo.property(named: self.relationship.foreignKeyName)
    }

    var wrappedValue: RecordType? {
        get {
            guard let enclosingRecord = self.enclosingRecord else {
                return nil
            }

            let foreignKeyValue = try! self.property.get(from: enclosingRecord) as Int64

            return try? RecordType.findAll(
                where: ["id" === foreignKeyValue]
            ).first()
        }
        set {
            fatalError("cannot set a relationship")
        }
    }
}

@propertyWrapper
class HasMany<RecordType: SwiftyRecord>: SwiftyRecordRelationship {
    var relationshipName: String?
    var enclosingRecord: SwiftyRecord?
    var connection: SwiftyRecordSQLite3Connection?

    var wrappedValue: SwiftyRecordCollection<RecordType> {
        get {
            guard let relationshipName = self.relationshipName, let enclosingRecord = self.enclosingRecord else {
                return SwiftyRecordCollection<RecordType>(
                    filters: [NeverMatchFilter()],
                    orderings: []
                )
            }

            return SwiftyRecordCollection<RecordType>(
                filters: [
                    RelationshipFilter(
                        id: enclosingRecord.id!,
                        tableName: type(of: enclosingRecord).tableName,
                        relationshipName: relationshipName
                    )
                ],
                orderings: []
            )
        }
        set {
            fatalError("You can't set a relationship")
        }
    }
}

protocol SwiftyRecord {
    static var tableName: ColumnName { get }

    static func sortedColumnNames(inConnection connection: SwiftyRecordSQLite3Connection) -> [String]

    var id: Int64? { get }
    var createdAt: Date? { get }
    var updatedAt: Date? { get }
}

extension SwiftyRecord {
    static func sortedColumnNames(inConnection connection: SwiftyRecordSQLite3Connection) -> [String] {
        connection.sortedColumnNames(forTableNamed: Self.tableName)
    }
}

extension SwiftyRecord {
    // This method hooks up relationships (like HasMany and BelongsTo) so they work properly.
    //
    // The relationship property wrappers need a reference to their enclosing type to work (so
    // as to read the proper field to filter on), but unfortunately the current property
    // wrappers proposal includes no mechanism for this.
    //
    // So, this method does the job manually by using Runtime to find properties of
    // type `SwiftyRecordRelationship` and manually set their `enclosingRecord`,
    // `relationshipName`, and `connection` properties.
    //
    // This method should be called when an object is reified after querying or whenever an
    // object is saved.
    //
    // A related consideration is that property wrapper arguments don't work, since reified
    // objects are created with Runtime and aren't initialized properly. If I could eventually
    // get arguments to work I wouldn't have to specify relationships in migrations, which
    // would be pretty nice.
    func hydrateRelationships(withConnection connection: SwiftyRecordSQLite3Connection) throws {
        let runtimeTypeInfo = try typeInfo(of: type(of: self))

        try runtimeTypeInfo.properties.filter { property in
            (property.type as? SwiftyRecordRelationship.Type) != nil
        }.forEach { property in
            var relationshipName = property.name
            relationshipName.removeFirst()

            let relationship = try property.get(from: self) as SwiftyRecordRelationship
            relationship.relationshipName = relationshipName
            relationship.enclosingRecord = self
            relationship.connection = connection
        }
    }
}

extension SwiftyRecord {
    var connection: SwiftyRecordSQLite3Connection { SwiftyRecordSQLite3Connection.shared }

    func save() throws -> Self {
        if id != nil {
            let updatedAt = try SwiftyRecordSQLite3Adapter.executeUpdate(forRecord: self, inConnection: self.connection)

            var newRecord = self
            try! typeInfo(of: type(of: self)).property(named: "updatedAt").set(value: updatedAt, on: &newRecord)
            try! newRecord.hydrateRelationships(withConnection: self.connection)

            return newRecord
        } else {
            let id = try SwiftyRecordSQLite3Adapter.executeInsertion(forRecord: self, inConnection: self.connection)

            let newRecord = try! Self.findAll(where: ["id" === id]).first()!
            try! newRecord.hydrateRelationships(withConnection: self.connection)

            return newRecord
        }
    }

    func destroy() throws {
        guard let recordId = self.id else {
            fatalError("destroy() called on a record without an id")
        }
        try Self.findAll(where: ["id" === recordId]).destroyAll()
    }
}

extension SwiftyRecord {
    static func findAll(where filters: [SwiftyRecordFilter] = []) -> SwiftyRecordCollection<Self> {
        // TODO: check the type names for properties that exist on Self.

        return SwiftyRecordCollection<Self>(filters: filters, orderings: [])
    }

    static func order(by columnName: String, _ order: SwiftyRecordOrder = .ascending) -> SwiftyRecordCollection<Self> {
        // TODO: check that the type name exists on Self.

        return SwiftyRecordCollection<Self>(
            filters: [],
            orderings: [SwiftyRecordOrdering(columnName: columnName, order: order)]
        )
    }

    static func count() throws -> Int {
        try Self.findAll().count()
    }

    static func first() throws -> Self? {
        try Self.findAll().first()
    }

    static func first(_ numRecords: Int = 1) throws -> [Self] {
        try Self.findAll().first(numRecords)
    }

    static func last() throws -> Self? {
        try Self.findAll().last()
    }

    static func last(_ numRecords: Int = 1) throws -> [Self] {
        try Self.findAll().last(numRecords)
    }

    static func destroyAll() throws {
        try Self.findAll().destroyAll()
    }
}

struct SwiftyRecordCollection<ElementType: SwiftyRecord> {
    var filters: [SwiftyRecordFilter]
    var orderings: [SwiftyRecordOrdering]
    var limit: Int?
    var defaultOrdering: SwiftyRecordOrder = .ascending

    var connection: SwiftyRecordSQLite3Connection { SwiftyRecordSQLite3Connection.shared }

    func findAll(where filters: [SwiftyRecordFilter]) -> SwiftyRecordCollection<ElementType> {
        SwiftyRecordCollection<ElementType>(
            filters: self.filters + filters,
            orderings: self.orderings,
            limit: self.limit,
            defaultOrdering: self.defaultOrdering
        )
    }

    func order(by columnName: String, _ order: SwiftyRecordOrder = .ascending) -> SwiftyRecordCollection<ElementType> {
        SwiftyRecordCollection<ElementType>(
            filters: self.filters,
            orderings: self.orderings + [SwiftyRecordOrdering(columnName: columnName, order: order)],
            limit: self.limit,
            defaultOrdering: self.defaultOrdering
        )
    }

    func limit(_ limit: Int?) -> SwiftyRecordCollection<ElementType> {
        SwiftyRecordCollection<ElementType>(
            filters: self.filters,
            orderings: self.orderings,
            limit: limit,
            defaultOrdering: self.defaultOrdering
        )
    }

    func reversed() -> SwiftyRecordCollection<ElementType> {
        SwiftyRecordCollection<ElementType>(
            filters: self.filters,
            orderings: self.orderings.map { $0.reversed },
            limit: self.limit,
            defaultOrdering: self.defaultOrdering.opposite
        )
    }

    func count() throws -> Int {
        try SwiftyRecordSQLite3Adapter.executeCountQuery(forCollection: self, inConnection: self.connection)
    }

    func first() throws -> ElementType? {
        try self.limit(1).execute().first
    }

    func first(_ numRecords: Int = 1) throws -> [ElementType] {
        try self.limit(numRecords).execute()
    }

    func last() throws -> ElementType? {
        try self.reversed().limit(1).execute().first
    }

    func last(_ numRecords: Int = 1) throws -> [ElementType] {
        try self.reversed().limit(numRecords).execute()
    }

    func destroyAll() throws {
        try SwiftyRecordSQLite3Adapter.executeDeleteQuery(forCollection: self, inConnection: self.connection)
    }

    func execute() throws -> [ElementType] {
        let queryResult = try SwiftyRecordSQLite3Adapter.executeSelectQuery(forCollection: self, inConnection: self.connection)
        return try SwiftyRecordSQLite3Adapter.reify(type: ElementType.self, fromQueryResult: queryResult, inConnection: self.connection)
    }
}

extension SwiftyRecordCollection {
    func updateAll(_ propertyValues: [String: SwiftyRecordColumnType]) throws {
        try SwiftyRecordSQLite3Adapter.executeUpdate(
            forCollection: self,
            withPropertyValues: propertyValues,
            inConnection: self.connection
        )
    }
}
