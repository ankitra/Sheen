import Foundation
import Combine

final class VaultMonitor {
    private var source: DispatchSourceFileSystemObject?
    private let changeSubject = PassthroughSubject<[FileChange], Never>()
    private var snapshot: [String: Date] = [:]
    private var fileDescriptor: Int32 = -1

    var changePublisher: AnyPublisher<[FileChange], Never> {
        changeSubject.eraseToAnyPublisher()
    }

    func startMonitoring(url: URL) throws {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { throw MonitorError.cannotOpenDirectory }
        fileDescriptor = fd

        snapshot = buildSnapshot(directory: url)

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let current = self.buildSnapshot(directory: url)
            let changes = self.detectChanges(old: self.snapshot, new: current)
            if !changes.isEmpty {
                self.changeSubject.send(changes)
            }
            self.snapshot = current
        }

        source?.setCancelHandler { [fd] in
            close(fd)
        }

        source?.resume()
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
        snapshot = [:]
    }

    var isMonitoring: Bool {
        source != nil && !(source?.isCancelled ?? true)
    }

    // MARK: - Snapshot

    private func buildSnapshot(directory: URL) -> [String: Date] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var snapshot: [String: Date] = [:]
        for case let fileURL as URL in enumerator {
            guard let resources = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = resources.isDirectory,
                  !isDirectory else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: directory.path, with: "")
            guard !relativePath.hasPrefix("/.obsidian") else { continue }

            if let modDate = resources.contentModificationDate {
                snapshot[relativePath] = modDate
            }
        }
        return snapshot
    }

    private func detectChanges(old: [String: Date], new: [String: Date]) -> [FileChange] {
        var changes: [FileChange] = []

        for (path, newDate) in new {
            if let oldDate = old[path] {
                if newDate != oldDate {
                    changes.append(FileChange(path: path, type: .modified))
                }
            } else {
                changes.append(FileChange(path: path, type: .created))
            }
        }

        for path in old.keys where new[path] == nil {
            changes.append(FileChange(path: path, type: .deleted))
        }

        return changes
    }

    deinit {
        stopMonitoring()
    }
}

enum MonitorError: Error {
    case cannotOpenDirectory
}
