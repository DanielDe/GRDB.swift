#if !USING_BUILTIN_SQLITE
    #if os(OSX)
        import SQLiteMacOSX
    #elseif os(iOS)
        #if (arch(i386) || arch(x86_64))
            import SQLiteiPhoneSimulator
        #else
            import SQLiteiPhoneOS
        #endif
    #elseif os(watchOS)
        #if (arch(i386) || arch(x86_64))
            import SQLiteWatchSimulator
        #else
            import SQLiteWatchOS
        #endif
    #endif
#endif

// MARK: - SQLExpressible

/// The protocol for all types that can be turned into an SQL expression.
///
/// It is adopted by protocols like DatabaseValueConvertible, and types
/// like Column.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public protocol SQLExpressible {
    /// Returns an SQLExpression
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    var sqlExpression: SQLExpression { get }
}


// MARK: - DatabaseValueConvertible

/// Types that adopt DatabaseValueConvertible can be initialized from
/// database values.
///
/// The protocol comes with built-in methods that allow to fetch sequences,
/// arrays, or single values:
///
///     String.fetch(db, "SELECT name FROM ...", arguments:...)    // DatabaseSequence<String?>
///     String.fetchAll(db, "SELECT name FROM ...", arguments:...) // [String?]
///     String.fetchOne(db, "SELECT name FROM ...", arguments:...) // String?
///
///     let statement = db.makeSelectStatement("SELECT name FROM ...")
///     String.fetch(statement, arguments:...)           // DatabaseSequence<String?>
///     String.fetchAll(statement, arguments:...)        // [String?]
///     String.fetchOne(statement, arguments:...)        // String?
///
/// DatabaseValueConvertible is adopted by Bool, Int, String, etc.
public protocol DatabaseValueConvertible : SQLExpressible {
    /// Returns a value that can be stored in the database.
    var databaseValue: DatabaseValue { get }
    
    /// Returns a value initialized from *databaseValue*, if possible.
    static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> Self?
}


// SQLExpressible adoption
extension DatabaseValueConvertible {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    ///
    /// # Low Level Query Interface
    ///
    /// See SQLExpression.sqlExpression
    public var sqlExpression: SQLExpression {
        return databaseValue
    }
}


/// DatabaseValueConvertible comes with built-in methods that allow to fetch
/// sequences, arrays, or single values:
///
///     String.fetch(db, "SELECT name FROM ...", arguments:...)    // DatabaseSequence<String>
///     String.fetchAll(db, "SELECT name FROM ...", arguments:...) // [String]
///     String.fetchOne(db, "SELECT name FROM ...", arguments:...) // String
///
///     let statement = db.makeSelectStatement("SELECT name FROM ...")
///     String.fetch(statement, arguments:...)           // DatabaseSequence<String>
///     String.fetchAll(statement, arguments:...)        // [String]
///     String.fetchOne(statement, arguments:...)        // String
///
/// DatabaseValueConvertible is adopted by Bool, Int, String, etc.
public extension DatabaseValueConvertible {
    
    
    // MARK: Fetching From SelectStatement
    
    /// TODO
    public static func fetchCursor(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseCursor<Self> {
        // Metal rows can be reused. And reusing them yields better performance.
        let row = try Row(statement: statement).adaptedRow(adapter: adapter, statement: statement)
        return try statement.fetchCursor(arguments: arguments) { () -> Self in
            let dbv: DatabaseValue = row.value(atIndex: 0)
            if let value = Self.fromDatabaseValue(dbv) {
                return value
            } else {
                throw DatabaseError(code: SQLITE_ERROR, message: "could not convert database value \(dbv) to \(Self.self)", sql: statement.sql, arguments: arguments)
            }
        }
    }
    
    /// Returns a sequence of values fetched from a prepared statement.
    ///
    ///     let statement = db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = String.fetch(statement) // DatabaseSequence<String>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = String.fetch(statement)
    ///     Array(names) // Arthur, Barbara
    ///     db.execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence.
    public static func fetch(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Self> {
        return DatabaseSequence { try fetchCursor(statement, arguments: arguments, adapter: adapter) }
    }
    
    /// Returns an array of values fetched from a prepared statement.
    ///
    ///     let statement = db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = String.fetchAll(statement)  // [String]
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array.
    public static func fetchAll(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Self] {
        return try! Array(fetchCursor(statement, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a single value fetched from a prepared statement.
    ///
    /// The result is nil if the query returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let statement = db.makeSelectStatement("SELECT name FROM ...")
    ///     let name = String.fetchOne(statement)   // String?
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional value.
    public static func fetchOne(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> Self? {
        let cursor = try! DatabaseValue.fetchCursor(statement, arguments: arguments, adapter: adapter)
        return try! cursor.next().flatMap { Self.fromDatabaseValue($0) }
    }
}


extension DatabaseValueConvertible {
    
    // MARK: Fetching From FetchRequest
    
    /// TODO
    public static func fetchCursor(_ db: Database, _ request: FetchRequest) throws -> DatabaseCursor<Self> {
        let (statement, adapter) = try request.prepare(db)
        return try fetchCursor(statement, adapter: adapter)
    }
    
    /// Returns a sequence of values fetched from a fetch request.
    ///
    ///     let nameColumn = Column("name")
    ///     let request = Person.select(nameColumn)
    ///     let names = String.fetch(db, request) // DatabaseSequence<String>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = String.fetch(db, request)
    ///     Array(names) // Arthur, Barbara
    ///     db.execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    public static func fetch(_ db: Database, _ request: FetchRequest) -> DatabaseSequence<Self> {
        let (statement, adapter) = try! request.prepare(db)
        return fetch(statement, adapter: adapter)
    }
    
    /// Returns an array of values fetched from a fetch request.
    ///
    ///     let nameColumn = Column("name")
    ///     let request = Person.select(nameColumn)
    ///     let names = String.fetchAll(db, request)  // [String]
    ///
    /// - parameter db: A database connection.
    public static func fetchAll(_ db: Database, _ request: FetchRequest) -> [Self] {
        let (statement, adapter) = try! request.prepare(db)
        return fetchAll(statement, adapter: adapter)
    }
    
    /// Returns a single value fetched from a fetch request.
    ///
    /// The result is nil if the query returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let nameColumn = Column("name")
    ///     let request = Person.select(nameColumn)
    ///     let name = String.fetchOne(db, request)   // String?
    ///
    /// - parameter db: A database connection.
    public static func fetchOne(_ db: Database, _ request: FetchRequest) -> Self? {
        let (statement, adapter) = try! request.prepare(db)
        return fetchOne(statement, adapter: adapter)
    }
}


extension DatabaseValueConvertible {

    // MARK: Fetching From SQL
    
    /// TODO
    public static func fetchCursor(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseCursor<Self> {
        return try fetchCursor(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a sequence of values fetched from an SQL query.
    ///
    ///     let names = String.fetch(db, "SELECT name FROM ...") // DatabaseSequence<String>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = String.fetch(db, "SELECT name FROM ...")
    ///     Array(names) // Arthur, Barbara
    ///     execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameters:
    ///     - db: A Database.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence.
    public static func fetch(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Self> {
        return fetch(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
    
    /// Returns an array of values fetched from an SQL query.
    ///
    ///     let names = String.fetchAll(db, "SELECT name FROM ...") // [String]
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array.
    public static func fetchAll(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Self] {
        return fetchAll(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a single value fetched from an SQL query.
    ///
    /// The result is nil if the query returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let name = String.fetchOne(db, "SELECT name FROM ...") // String?
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional value.
    public static func fetchOne(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> Self? {
        return fetchOne(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
}


/// Swift's Optional comes with built-in methods that allow to fetch sequences
/// and arrays of optional DatabaseValueConvertible:
///
///     Optional<String>.fetch(db, "SELECT name FROM ...", arguments:...)    // DatabaseSequence<String?>
///     Optional<String>.fetchAll(db, "SELECT name FROM ...", arguments:...) // [String?]
///
///     let statement = db.makeSelectStatement("SELECT name FROM ...")
///     Optional<String>.fetch(statement, arguments:...)           // DatabaseSequence<String?>
///     Optional<String>.fetchAll(statement, arguments:...)        // [String?]
///
/// DatabaseValueConvertible is adopted by Bool, Int, String, etc.
public extension Optional where Wrapped: DatabaseValueConvertible {
    
    // MARK: Fetching From SelectStatement
    
    /// TODO
    public static func fetchCursor(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseCursor<Wrapped?> {
        let row = try Row(statement: statement).adaptedRow(adapter: adapter, statement: statement)
        return try statement.fetchCursor(arguments: arguments) { () -> Wrapped? in
            let dbv: DatabaseValue = row.value(atIndex: 0)
            if let value = Wrapped.fromDatabaseValue(dbv) {
                return value
            } else if dbv.isNull {
                return nil
            } else {
                throw DatabaseError(code: SQLITE_ERROR, message: "could not convert database value \(dbv) to \(Wrapped.self)", sql: statement.sql, arguments: arguments)
            }
        }
    }
    
    /// Returns a sequence of optional values fetched from a prepared statement.
    ///
    ///     let statement = db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = Optional<String>.fetch(statement) // DatabaseSequence<String?>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = Optional<String>.fetch(statement)
    ///     Array(names) // Arthur, Barbara
    ///     db.execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence of optional values.
    public static func fetch(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Wrapped?> {
        return DatabaseSequence { try fetchCursor(statement, arguments: arguments, adapter: adapter) }
    }
    
    /// Returns an array of optional values fetched from a prepared statement.
    ///
    ///     let statement = db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = Optional<String>.fetchAll(statement)  // [String?]
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of optional values.
    public static func fetchAll(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Wrapped?] {
        return try! Array(fetchCursor(statement, arguments: arguments, adapter: adapter))
    }
}


extension Optional where Wrapped: DatabaseValueConvertible {
    
    // MARK: Fetching From FetchRequest
    
    /// TODO
    public static func fetchCursor(_ db: Database, _ request: FetchRequest) throws -> DatabaseCursor<Wrapped?> {
        let (statement, adapter) = try request.prepare(db)
        return try fetchCursor(statement, adapter: adapter)
    }
    
    /// Returns a sequence of optional values fetched from a fetch request.
    ///
    ///     let nameColumn = Column("name")
    ///     let request = Person.select(nameColumn)
    ///     let names = Optional<String>.fetch(db, request) // DatabaseSequence<String?>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = Optional<String>.fetch(db, request)
    ///     Array(names) // Arthur, Barbara
    ///     db.execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    public static func fetch(_ db: Database, _ request: FetchRequest) -> DatabaseSequence<Wrapped?> {
        let (statement, adapter) = try! request.prepare(db)
        return fetch(statement, adapter: adapter)
    }
    
    /// Returns an array of optional values fetched from a fetch request.
    ///
    ///     let nameColumn = Column("name")
    ///     let request = Person.select(nameColumn)
    ///     let names = Optional<String>.fetchAll(db, request)  // [String?]
    ///
    /// - parameter db: A database connection.
    public static func fetchAll(_ db: Database, _ request: FetchRequest) -> [Wrapped?] {
        let (statement, adapter) = try! request.prepare(db)
        return fetchAll(statement, adapter: adapter)
    }
}


extension Optional where Wrapped: DatabaseValueConvertible {
    
    // MARK: Fetching From SQL
    
    /// TODO
    public static func fetchCursor(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseCursor<Wrapped?> {
        return try fetchCursor(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a sequence of optional values fetched from an SQL query.
    ///
    ///     let names = Optional<String>.fetch(db, "SELECT name FROM ...") // DatabaseSequence<String?>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let names = Optional<String>.fetch(db, "SELECT name FROM ...")
    ///     Array(names) // Arthur, Barbara
    ///     db.execute("DELETE ...")
    ///     Array(names) // Arthur
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameters:
    ///     - db: A Database.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence of optional values.
    public static func fetch(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Wrapped?> {
        return fetch(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
    
    /// Returns an array of optional values fetched from an SQL query.
    ///
    ///     let names = String.fetchAll(db, "SELECT name FROM ...") // [String?]
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - parameter arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of optional values.
    public static func fetchAll(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Wrapped?] {
        return fetchAll(db, SQLFetchRequest(sql: sql, arguments: arguments, adapter: adapter))
    }
}
