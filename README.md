# SwiftyRecord

A Swift ORM heavily inspired by Rails' ActiveRecord.

Still a work in progress.

## Example:

```swift
// Migration:
let usersMigration = SwiftyRecordMigration("add users table") {
    CreateTableOperation("users") {
        TableColumn("name", String.self)
        TableColumn("age", Int.self)
    }
}
// Execute migration...

struct User: SwiftyRecord {
    static let tableName = "users"

    let id: Int64?
    var name: String
    var age: Int
}

// Insertion:
let user = try! User(name: "Winnie Harvey", age: 5).save()
assert(user.id != nil, "Serial ID generated by database upon insertion")

// Querying with operator overloading enabled DSL:
let youngUsers = try! User.findAll(where: ["age" <= 10])
print("Num young users: \(try! youngUsers.count())")

// Relationships:
let booksMigration = SwiftyRecordMigration("add books table") {
    CreateTableOperation("books") {
        TableColumn("title", String.self)
        TableColumn("authorId", Int.self)
        Relationship(.belongsTo, "user", via: "authorId")
    }
}
// Execute migration...

struct Book: SwiftyRecord {
    static let tableName = "books"

    let id: Int64?
    var title: String
    var authorId: Int64?

    @BelongsTo var author: User?
}

assert(user.id == 1, "Users's id is 1")
let book = try! Book(title: "Surely You're Joking", authorId: 1).save()
assert(book.author!.name == "Winnie Harvey", "Author is the above user")
```
