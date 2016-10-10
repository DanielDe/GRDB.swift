#if SQLITE_ENABLE_FTS5
    public struct FTS5TokenFlags : OptionSet {
        public let rawValue: Int32
        
        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }
        
        /// FTS5_TOKEN_COLOCATED
        public static let colocated = FTS5TokenFlags(rawValue: FTS5_TOKEN_COLOCATED)
    }
    
    public typealias FTS5TokenNotifier = (_ token: String, _ flags: FTS5TokenFlags) throws -> ()
    
    public protocol FTS5WrapperTokenizer : FTS5CustomTokenizer {
        var wrappedTokenizer: FTS5Tokenizer { get }
        func customizesWrappedTokenizer(flags: FTS5TokenizeFlags) -> Bool
        func accept(token: String, flags: FTS5TokenFlags, notify: FTS5TokenNotifier) throws
    }
    
    private struct FTS5WrapperContext {
        let tokenizer: FTS5WrapperTokenizer
        let context: UnsafeMutableRawPointer?
        let tokenCallback: FTS5TokenCallback
    }
    
    extension FTS5WrapperTokenizer {
        public func tokenize(context: UnsafeMutableRawPointer?, flags: FTS5TokenizeFlags, pText: UnsafePointer<Int8>?, nText: Int32, tokenCallback: FTS5TokenCallback?) -> Int32 {
            // Let wrappedTokenizer do the job unless we customize
            guard customizesWrappedTokenizer(flags: flags) else {
                return wrappedTokenizer.tokenize(context: context, flags: flags, pText: pText, nText: nText, tokenCallback: tokenCallback)
            }
            
            // `tokenCallback` is @convention(c). This requires a little setup
            // in order to transfer context.
            var customContext = FTS5WrapperContext(tokenizer: self, context: context, tokenCallback: tokenCallback!)
            return withUnsafeMutablePointer(to: &customContext) { customContextPointer in
                // Invoke wrappedTokenizer
                return wrappedTokenizer.tokenize(context: customContextPointer, flags: flags, pText: pText, nText: nText) { (customContextPointer, flags, pToken, nToken, iStart, iEnd) in
                    
                    // Extract token produced by wrapped tokenizer
                    guard let token = pToken.flatMap({ String(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: Int(nToken), deallocator: .none), encoding: .utf8) }) else {
                        return 0 // SQLITE_OK
                    }
                    
                    // Extract context
                    let customContext = customContextPointer!.assumingMemoryBound(to: FTS5WrapperContext.self).pointee
                    let tokenizer = customContext.tokenizer
                    let context = customContext.context
                    let tokenCallback = customContext.tokenCallback
                    
                    // Process token produced by wrapped tokenizer
                    do {
                        try tokenizer.accept(token: token, flags: FTS5TokenFlags(rawValue: flags), notify: { (token, flags) in
                            // Turn token into bytes
                            return try ContiguousArray(token.utf8).withUnsafeBufferPointer { buffer in
                                guard let addr = buffer.baseAddress else {
                                    return
                                }
                                let pToken = UnsafeMutableRawPointer(mutating: addr).assumingMemoryBound(to: Int8.self)
                                let nToken = Int32(buffer.count)
                                
                                // Inject token into SQLite
                                let code = tokenCallback(context, flags.rawValue, pToken, nToken, iStart, iEnd)
                                guard code == SQLITE_OK else {
                                    throw DatabaseError(code: code, message: "token consumer failed")
                                }
                            }
                        })
                        
                        return SQLITE_OK
                    } catch let error as DatabaseError {
                        return error.code
                    } catch {
                        return SQLITE_ERROR
                    }
                }
            }
        }
    }
#endif
