import Foundation

enum FileChangeType {
    case created, modified, deleted
}

struct FileChange {
    let path: String
    let type: FileChangeType
}
