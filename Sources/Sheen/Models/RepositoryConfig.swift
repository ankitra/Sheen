import Foundation

struct RepositoryConfig: Codable, Equatable {
    var vaultPath: String = ""
    var remoteURL: String = ""
    var branch: String = "main"
}
