import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Cross-process storage shared by the containing app and Screen Time extensions.
/// Never replace an unreadable document with defaults: that would erase a lock.
public final class StateRepository: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
    }

    public func read() throws -> ProtectionDocument {
        try withLock("state") { try readUnlocked() }
    }

    @discardableResult
    public func update<T>(_ change: (inout ProtectionDocument) throws -> T,
                          afterSave: ((ProtectionDocument) -> Void)? = nil) throws -> T {
        try withLock("state") {
            var document = try readUnlocked()
            let result = try change(&document)
            if document.schemaVersion == 1 { document.schemaVersion = 2 }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            #if os(iOS)
            try data.write(to: documentURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: documentURL, options: .atomic)
            #endif
            // Keep applying the latest shields ordered with persistence and other processes.
            afterSave?(document)
            return result
        }
    }

    public func withOperationLock<T>(_ body: () throws -> T) throws -> T {
        // Never wait here in a monitor callback. startMonitoring may synchronously deliver
        // another callback while the containing process holds this lock.
        try withLock("operation", nonBlocking: true, body)
    }

    private var documentURL: URL { directory.appendingPathComponent("protection-v1.json") }

    private func readUnlocked() throws -> ProtectionDocument {
        guard FileManager.default.fileExists(atPath: documentURL.path) else { return ProtectionDocument() }
        let document = try JSONDecoder().decode(ProtectionDocument.self, from: Data(contentsOf: documentURL))
        guard document.schemaVersion == 1 || document.schemaVersion == 2 else { throw RuleError.unsupportedSchema }
        return document
    }

    private func withLock<T>(_ name: String, nonBlocking: Bool = false, _ body: () throws -> T) throws -> T {
        let path = directory.appendingPathComponent(name + ".lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | (nonBlocking ? LOCK_NB : 0)) == 0 else {
            if errno == EWOULDBLOCK { throw RuleError.busy }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
