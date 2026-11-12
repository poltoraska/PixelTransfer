import Foundation
import Darwin

@main
struct DownloadPlanTests {
    static func main() throws {
        let artist = PhoneEntry(id: 1, name: "Исполнитель 🎵", size: 0, folder: true)
        let album = PhoneEntry(id: 2, name: "Album", size: 0, folder: true)
        let empty = PhoneEntry(id: 3, name: "Empty", size: 0, folder: true)
        let song = PhoneEntry(id: 4, name: "01.flac", size: 3, folder: false)
        let zero = PhoneEntry(id: 5, name: "zero", size: 0, folder: false)
        let tree = [artist.id: [album, empty], album.id: [song, zero]]
        let plan = try DownloadPlan.make(root: artist, cancelled: { false }) { tree[$0] ?? [] }
        precondition(plan.totalBytes == 3 && plan.nodes.count == 5)
        precondition(plan.nodes.contains { $0.relativePath == "Исполнитель 🎵/Album/01.flac" })
        precondition(plan.nodes.contains { $0.relativePath == "Исполнитель 🎵/Empty" })
        let filePlan = try DownloadPlan.make(root: zero, cancelled: { false }) { _ in fatalError("Not a folder") }
        precondition(filePlan.totalWeight == 1 && filePlan.nodes.count == 1)
        func fails(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection") } catch { }
        }
        fails { _ = try DownloadPlan.make(root: artist, cancelled: { true }) { _ in [] } }
        fails { _ = try DownloadPlan.make(root: artist, cancelled: { false }) { _ in [artist] } }
        fails { _ = try DownloadPlan.make(root: artist, cancelled: { false }) { _ in [song, song] } }
        for name in ["", ".", "..", "../outside", "/absolute", "inside/outside", "nul\0name"] {
            fails { try LocalDownloadDirectory.validate(name) }
        }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("PixelTransferDownloadTests-\(UUID())")
        let selected = base.appendingPathComponent("selected"), outside = base.appendingPathComponent("outside")
        try fm.createDirectory(at: selected, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let root = try LocalDownloadDirectory(url: selected)
        let parent = try root.parent(for: ["Исполнитель 🎵", "Album", "Disc 1"])
        precondition(parent.descriptor >= 0)
        _ = try root.parent(for: ["Исполнитель 🎵", "Album", "Disc 1"])
        try Data([1]).write(to: selected.appendingPathComponent("file"))
        fails { _ = try root.folder("file") }
        try fm.createSymbolicLink(at: selected.appendingPathComponent("link"), withDestinationURL: outside)
        fails { _ = try root.parent(for: ["link", "escaped"]) }
        precondition(!fm.fileExists(atPath: outside.appendingPathComponent("escaped").path))
        fails { _ = try LocalDownloadDirectory(url: selected.appendingPathComponent("link")) }
        fails { _ = try root.parent(for: ["..", "escaped"]) }
        print("Download plans, nested/empty folders, cancellation, cycles, invalid names, local conflicts and symlink containment: OK")
    }
}
