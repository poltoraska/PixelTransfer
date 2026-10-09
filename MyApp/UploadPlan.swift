import Foundation

struct UploadNode: Sendable {
    let url: URL
    let components: [String]
    let folder: Bool
    let size: UInt64
    var weight: Double { folder ? 1 : max(1, Double(size)) }
    var relativePath: String { components.joined(separator: "/") }
}
struct UploadPlan: Sendable {
    let nodes: [UploadNode]
    let excludedItems: Int
    var fileCount: Int { nodes.filter { !$0.folder }.count }
    var totalBytes: UInt64 {
        nodes.reduce(0) { total, node in
            let (sum, overflow) = total.addingReportingOverflow(node.size)
            return overflow ? UInt64.max : sum
        }
    }
    var totalWeight: Double { max(1, nodes.reduce(0) { $0 + $1.weight }) }

    // Iterative traversal avoids recursion limits. Never follow links outside the selected tree.
    static func make(root: URL, cancelled: () -> Bool = { false }) throws -> UploadPlan {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var stack: [(URL, [String])] = [(root, [root.lastPathComponent])]
        var nodes: [UploadNode] = []
        var excluded = 0
        while let (url, components) = stack.popLast() {
            if cancelled() { throw CocoaError(.userCancelled) }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true || (values.isDirectory != true && values.isRegularFile != true) {
                    if components.count == 1 {
                        throw NSError(domain: "PixelTransfer.Plan", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Выберите обычный файл или папку. Символические ссылки не копируются.")])
                    }
                    excluded += 1; continue
                }
                let isFolder = values.isDirectory == true
                nodes.append(UploadNode(url: url, components: components, folder: isFolder,
                                        size: isFolder ? 0 : UInt64(max(0, values.fileSize ?? 0))))
                if isFolder {
                    let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    for child in children.reversed() {
                        // Finder metadata does not belong in a music library.
                        if child.lastPathComponent == ".DS_Store" || child.lastPathComponent.hasPrefix("._") {
                            excluded += 1; continue
                        }
                        stack.append((child, components + [child.lastPathComponent]))
                    }
                }
            } catch {
                let relativePath = components.joined(separator: "/")
                throw NSError(domain: "PixelTransfer.Plan", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "Не удалось подготовить «\(relativePath)»: \(error.localizedDescription)")])
            }
        }
        return UploadPlan(nodes: nodes, excludedItems: excluded)
    }
}
struct UploadSummary: Sendable {
    var totalBytes: UInt64 = 0
    var copiedFiles = 0
    var skippedFiles = 0
    var folders = 0
    var excludedItems = 0
    var detail: String {
        var value = String(localized: "Скопировано файлов: \(copiedFiles), пропущено совпадений: \(skippedFiles). Папок: \(folders).")
        if excludedItems > 0 { value += String(localized: " Исключено ссылок и служебных объектов: \(excludedItems).") }
        return value
    }
}
struct UploadUpdate: Sendable {
    let fraction: Double
    let path: String
    let totalBytes: UInt64
    let summary: UploadSummary
}
