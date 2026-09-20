import Foundation
import UIKit
import UniformTypeIdentifiers

enum ObjectExporter {
    /// Builds a shareable package: object.json + images/ + thumbnail/
    static func makeSharePackage(for object: FoodObject, store: ObjectLibraryStore) throws -> URL {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("export-\(object.id)-\(UUID().uuidString)", isDirectory: true)
        let packageName = sanitize(object.name) + ".arfood"
        let packageURL = tempRoot.appendingPathComponent(packageName, isDirectory: true)
        try fm.createDirectory(at: packageURL.appendingPathComponent("images"), withIntermediateDirectories: true)
        try fm.createDirectory(at: packageURL.appendingPathComponent("thumbnail"), withIntermediateDirectories: true)

        let source = store.directory(for: object.id)
        let objectJSON = source.appendingPathComponent("object.json")
        try fm.copyItem(at: objectJSON, to: packageURL.appendingPathComponent("object.json"))

        let imagesSrc = source.appendingPathComponent("images")
        if let files = try? fm.contentsOfDirectory(atPath: imagesSrc.path) {
            for file in files {
                try fm.copyItem(
                    at: imagesSrc.appendingPathComponent(file),
                    to: packageURL.appendingPathComponent("images/\(file)")
                )
            }
        }
        let thumbSrc = source.appendingPathComponent("thumbnail/thumb.png")
        if fm.fileExists(atPath: thumbSrc.path) {
            try fm.copyItem(at: thumbSrc, to: packageURL.appendingPathComponent("thumbnail/thumb.png"))
        }

        // Zip as a single file for share sheet
        let zipURL = tempRoot.appendingPathComponent("\(sanitize(object.name)).arfood.zip")
        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
        try zipDirectory(at: packageURL, to: zipURL)
        return zipURL
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") }
        return String(cleaned).replacingOccurrences(of: "--", with: "-")
    }

    private static func zipDirectory(at source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var resultError: Error?
        coordinator.coordinate(readingItemAt: source, options: .forUploading, error: &error) { zipTemp in
            do {
                try FileManager.default.copyItem(at: zipTemp, to: destination)
            } catch {
                resultError = error
            }
        }
        if let error { throw error }
        if let resultError { throw resultError }
    }
}
