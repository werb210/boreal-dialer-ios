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
                // BOREAL_DIALER_SURVIVE_FIRST_RUN_v21 - call history and cached
                // messages are a convenience; everything else reads from the
                // server. Log and carry on rather than refusing to launch.
                print("[persistence] CoreData store failed: \(error)")
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
