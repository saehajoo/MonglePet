import Combine
import Foundation

nonisolated struct RemotePetImportRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let source: RemotePetImportSource

    init(id: UUID = UUID(), source: RemotePetImportSource) {
        self.id = id
        self.source = source
    }
}

@MainActor
final class RemotePetImportRequestCenter: ObservableObject {
    @Published private(set) var request: RemotePetImportRequest?
    @Published private(set) var errorMessage: String?

    func submit(deepLinkURL: URL) {
        do {
            let deepLink = try RemotePetImportDeepLink(url: deepLinkURL)
            errorMessage = nil
            request = RemotePetImportRequest(source: deepLink.source)
        } catch {
            request = nil
            errorMessage = error.localizedDescription
        }
    }

    func consume(_ requestID: UUID) {
        guard request?.id == requestID else {
            return
        }
        request = nil
    }

    func clearError() {
        errorMessage = nil
    }
}
