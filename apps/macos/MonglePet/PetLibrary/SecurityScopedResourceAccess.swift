import Foundation

nonisolated protocol SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

nonisolated struct SystemSecurityScopedResourceAccess: SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

nonisolated struct SecurityScopedResourceAccess {
    private let accessor: any SecurityScopedResourceAccessing

    init(accessor: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()) {
        self.accessor = accessor
    }

    func withAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let didStartAccess = accessor.startAccessing(url)
        defer {
            if didStartAccess {
                accessor.stopAccessing(url)
            }
        }
        return try operation()
    }
}
