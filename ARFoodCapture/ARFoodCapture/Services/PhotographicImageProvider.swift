import Foundation
import UIKit

/// Common image source for local library objects and remote downloads.
protocol PhotographicImageProviding: AnyObject {
    func loadUIImage(named name: String) -> UIImage?
}

/// Loads transparent views from ObjectLibraryStore (local Application Support).
@MainActor
final class LocalPhotographicImageProvider: PhotographicImageProviding {
    let object: FoodObject
    let store: ObjectLibraryStore

    init(object: FoodObject, store: ObjectLibraryStore) {
        self.object = object
        self.store = store
    }

    func loadUIImage(named name: String) -> UIImage? {
        guard let view = object.views.first(where: { $0.image == name }) else {
            let url = store.imagesDirectory(for: object.id).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        return store.loadImage(for: object, view: view)
    }
}

/// Loads views that were already downloaded into a memory/disk cache map.
final class CachedPhotographicImageProvider: PhotographicImageProviding {
    private var images: [String: UIImage]

    init(images: [String: UIImage] = [:]) {
        self.images = images
    }

    func setImage(_ image: UIImage, named name: String) {
        images[name] = image
    }

    func loadUIImage(named name: String) -> UIImage? {
        images[name]
    }
}
