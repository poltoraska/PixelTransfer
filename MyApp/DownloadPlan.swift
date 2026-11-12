import Foundation
import Darwin

struct PhoneEntry: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
    var modifiedAt: Date? = nil
}

struct DownloadNode: Sendable {
    let entry: PhoneEntry
    let components: [String]
    var relativePath: String { components.joined(separator: "/") }
    var weight: Double { entry.folder ? 1 : max(1, Double(entry.size)) }
}

struct DownloadPlan: Sendable {
    let nodes: [DownloadNode]
    var totalBytes: UInt64 {
        nodes.reduce(0) { total, node in
            let (sum, overflow) = total.addingReportingOverflow(node.entry.folder ? 0 : node.entry.size)
            return overflow ? UInt64.max : sum
        }
    }
    var totalWeight: Double { max(1, nodes.reduce(0) { $0 + $1.weight }) }

    // Snapshot the remote tree on the MTP queue before writing any local files.
    static func make(root: PhoneEntry, cancelled: () -> Bool,
                     contents: (UInt32) throws -> [PhoneEntry]) throws -> DownloadPlan {
        var stack = [(root, [root.name])]
        var seen = Set<UInt32>()
        var nodes: [DownloadNode] = []
        while let (entry, components) = stack.popLast() {
            if cancelled() { throw CocoaError(.userCancelled) }
            try LocalDownloadDirectory.validate(entry.name)
            guard seen.insert(entry.id).inserted else {
                throw NSError(domain: "PixelTransfer.Download", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "В дереве телефона обнаружен повторяющийся объект. Обновите папку и попробуйте снова.")])
            }
            nodes.append(DownloadNode(entry: entry, components: components))
            if entry.folder {
                let children = try contents(entry.id).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                guard Set(children.map(\.name)).count == children.count else {
                    throw NSError(domain: "PixelTransfer.Download", code: 2, userInfo: [NSLocalizedDescriptionKey:
                        String(localized: "В папке телефона есть объекты с одинаковыми именами. Переименуйте их перед копированием.")])
                }
                for child in children.reversed() { stack.append((child, components + [child.name])) }
            }
        }
        return DownloadPlan(nodes: nodes)
    }
}

// Relative descriptors keep all traversal inside the folder the user selected.
// Never follow pre-existing local symlinks, including links to other directories.
final class LocalDownloadDirectory {
    let descriptor: Int32
    init(url: URL) throws {
        descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.fileError(url.lastPathComponent) }
    }
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw NSError(domain: "PixelTransfer.Download", code: 3, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Недопустимое имя объекта на телефоне: «\(name)».")])
        }
    }
    func folder(_ name: String) throws -> LocalDownloadDirectory {
        try Self.validate(name)
        if mkdirat(descriptor, name, 0o755) != 0, errno != EEXIST { throw Self.fileError(name) }
        let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw Self.fileError(name) }
        return LocalDownloadDirectory(descriptor: child)
    }
    func parent(for components: [String]) throws -> LocalDownloadDirectory {
        var directory = self
        for component in components { directory = try directory.folder(component) }
        return directory
    }
    private static func fileError(_ name: String) -> NSError {
        let reason = String(cString: strerror(errno))
        return NSError(domain: "PixelTransfer.Local", code: Int(errno), userInfo: [NSLocalizedDescriptionKey:
            String(localized: "Не удалось открыть папку на Mac «\(name)»: \(reason). Проверьте права доступа и совпадения имён. Символические ссылки не используются.")])
    }
}
