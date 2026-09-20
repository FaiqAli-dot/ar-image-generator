import Foundation
import UIKit
import Combine

@MainActor
final class ObjectLibraryStore: ObservableObject {
    static let shared = ObjectLibraryStore()

    @Published private(set) var objects: [FoodObject] = []

    private let fileManager = FileManager.default
    private let indexFileName = "library_index.json"
    private var cancellables = Set<AnyCancellable>()

    private var rootURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARFoodCapture", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var indexURL: URL { rootURL.appendingPathComponent(indexFileName) }

    private init() {
        load()
        ensureDemoObjectInstalled()
    }

    func directory(for objectID: String) -> URL {
        rootURL.appendingPathComponent(objectID, isDirectory: true)
    }

    func imagesDirectory(for objectID: String) -> URL {
        directory(for: objectID).appendingPathComponent("images", isDirectory: true)
    }

    func thumbnailURL(for objectID: String) -> URL {
        directory(for: objectID).appendingPathComponent("thumbnail/thumb.png")
    }

    func imageURL(for object: FoodObject, view: CapturedView) -> URL {
        imagesDirectory(for: object.id).appendingPathComponent(view.image)
    }

    func loadThumbnail(for object: FoodObject) -> UIImage? {
        let url = thumbnailURL(for: object.id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func loadImage(for object: FoodObject, view: CapturedView) -> UIImage? {
        let url = imageURL(for: object, view: view)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func save(_ object: FoodObject, images: [String: Data], thumbnail: Data?) throws {
        let dir = directory(for: object.id)
        let imagesDir = imagesDirectory(for: object.id)
        let thumbDir = dir.appendingPathComponent("thumbnail", isDirectory: true)
        try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        for (name, data) in images {
            try data.write(to: imagesDir.appendingPathComponent(name), options: .atomic)
        }
        if let thumbnail {
            try thumbnail.write(to: thumbDir.appendingPathComponent("thumb.png"), options: .atomic)
        }

        var mutable = object
        mutable.viewCount = object.views.count
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(mutable)
        try metaData.write(to: dir.appendingPathComponent("object.json"), options: .atomic)

        if let idx = objects.firstIndex(where: { $0.id == mutable.id }) {
            objects[idx] = mutable
        } else {
            objects.insert(mutable, at: 0)
        }
        try persistIndex()
    }

    func delete(_ object: FoodObject) throws {
        if object.isDemo { return }
        let dir = directory(for: object.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        objects.removeAll { $0.id == object.id }
        try persistIndex()
    }

    func object(id: String) -> FoodObject? {
        objects.first { $0.id == id }
    }

    func reloadObject(id: String) -> FoodObject? {
        let url = directory(for: id).appendingPathComponent("object.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FoodObject.self, from: data)
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else {
            objects = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let ids = try? decoder.decode([String].self, from: data) {
            objects = ids.compactMap { reloadObject(id: $0) }
        }
    }

    private func persistIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let ids = objects.map(\.id)
        let data = try encoder.encode(ids)
        try data.write(to: indexURL, options: .atomic)
    }

    private func ensureDemoObjectInstalled() {
        let demoID = "demo-burger"
        let dest = directory(for: demoID)

        let candidates: [URL?] = [
            Bundle.main.url(forResource: "DemoBurger", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("DemoBurger"),
            Bundle.main.bundleURL.appendingPathComponent("DemoBurger"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/DemoBurger")
        ]
        let bundleURL = candidates.compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }

        if let bundleURL {
            if fileManager.fileExists(atPath: dest.path) {
                try? fileManager.removeItem(at: dest)
            }
            try? fileManager.copyItem(at: bundleURL, to: dest)
        }

        if let demo = reloadObject(id: demoID) {
            if !objects.contains(where: { $0.id == demoID }) {
                objects.insert(demo, at: 0)
                try? persistIndex()
            } else if let idx = objects.firstIndex(where: { $0.id == demoID }) {
                objects[idx] = demo
            }
        }
    }
}
