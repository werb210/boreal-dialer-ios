import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "DialerModel", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("CoreData store failed: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [CallEntity.entityDescription(), MessageEntity.entityDescription()]
        return model
    }
}
