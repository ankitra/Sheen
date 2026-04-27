import Foundation

enum SyncState: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)
}
