import Foundation

public struct CachedResponse: Sendable {
    public let etag: String
    public let data: Data

    public init(etag: String, data: Data) {
        self.etag = etag
        self.data = data
    }
}

/// Stores API responses with their ETags for conditional revalidation.
public protocol ResponseCache: Sendable {
    func entry(for path: String) -> CachedResponse?
    func store(_ entry: CachedResponse, for path: String)
}

/// Keeps cached responses as files. On tvOS point it at the Caches
/// directory: the system may purge it, which only costs a full re-download.
public final class FileResponseCache: ResponseCache, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func caches(named name: String = "OroroAPI") -> FileResponseCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return FileResponseCache(directory: base.appendingPathComponent(name, isDirectory: true))
    }

    public func entry(for path: String) -> CachedResponse? {
        lock.lock(); defer { lock.unlock() }
        let (bodyURL, etagURL) = urls(for: path)
        guard let etag = try? String(contentsOf: etagURL, encoding: .utf8),
              let data = try? Data(contentsOf: bodyURL) else { return nil }
        return CachedResponse(etag: etag, data: data)
    }

    public func store(_ entry: CachedResponse, for path: String) {
        lock.lock(); defer { lock.unlock() }
        let (bodyURL, etagURL) = urls(for: path)
        // Body first, so a crash in between leaves a stale etag with no body
        // (a cache miss) rather than a new etag with an old body.
        try? FileManager.default.removeItem(at: etagURL)
        try? entry.data.write(to: bodyURL, options: .atomic)
        try? Data(entry.etag.utf8).write(to: etagURL, options: .atomic)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func urls(for path: String) -> (body: URL, etag: URL) {
        let name = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "_")
        return (directory.appendingPathComponent(name + ".json"),
                directory.appendingPathComponent(name + ".etag"))
    }
}
