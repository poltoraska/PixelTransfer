import Foundation

@main
struct UploadPlanTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("PixelTransferPlanTests-\(UUID())")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let root = base.appendingPathComponent("Исполнитель")
        let disc = root.appendingPathComponent("Альбом 1/Disc 1")
        let second = root.appendingPathComponent("Альбом 2")
        let empty = root.appendingPathComponent("Пустой альбом")
        for folder in [disc, second, empty] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data([1, 2, 3]).write(to: disc.appendingPathComponent("01.flac"))
        try Data([4, 5]).write(to: second.appendingPathComponent("01.flac"))
        try Data().write(to: second.appendingPathComponent("Пустой.txt"))
        try Data([8]).write(to: root.appendingPathComponent(".DS_Store"))
        try Data([9]).write(to: second.appendingPathComponent("._01.flac"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("Cycle"), withDestinationURL: root)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Missing"), withDestinationURL: base.appendingPathComponent("no-such-file"))
        let plan = try UploadPlan.make(root: root)
        precondition(plan.fileCount == 3)
        precondition(plan.totalBytes == 5)
        // macOS may hide AppleDouble (._) entries from directory enumeration itself.
        precondition((3...4).contains(plan.excludedItems))
        precondition(!plan.nodes.contains { $0.url.lastPathComponent == ".DS_Store" || $0.url.lastPathComponent.hasPrefix("._") })
        let paths = Set(plan.nodes.map(\.relativePath))
        precondition(paths.contains("Исполнитель/Пустой альбом"))
        precondition(paths.contains("Исполнитель/Альбом 1/Disc 1/01.flac"))
        precondition(paths.contains("Исполнитель/Альбом 2/01.flac"))
        var parents: Set<[String]> = [[]]
        for node in plan.nodes {
            precondition(parents.contains(Array(node.components.dropLast())))
            if node.folder { parents.insert(node.components) }
        }
        let single = try UploadPlan.make(root: disc.appendingPathComponent("01.flac"))
        precondition(single.nodes.count == 1 && single.totalBytes == 3)
        let emptyPlan = try UploadPlan.make(root: empty)
        precondition(emptyPlan.nodes.count == 1 && emptyPlan.nodes[0].folder)
        do { _ = try UploadPlan.make(root: root, cancelled: { true }); fatalError("Cancellation was ignored") }
        catch { precondition((error as NSError).code == CocoaError.userCancelled.rawValue) }
        do { _ = try UploadPlan.make(root: root.appendingPathComponent("Cycle")); fatalError("Root symlink was followed") }
        catch { precondition((error as NSError).domain == "PixelTransfer.Plan") }
        print("PASS: nested artist/albums, same filenames in separate albums, empty folders/files, parent order, metadata exclusion, links/cycles, cancellation, single-file compatibility")
    }
}
