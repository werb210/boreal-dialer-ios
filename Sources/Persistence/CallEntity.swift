import CoreData
import Foundation

@objc(CallEntity)
final class CallEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var number: String
    @NSManaged var direction: String
    @NSManaged var status: String
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    @NSManaged var lineId: String
}

extension CallEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CallEntity> {
        NSFetchRequest<CallEntity>(entityName: "CallEntity")
    }

    static func entityDescription() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CallEntity"
        entity.managedObjectClassName = NSStringFromClass(CallEntity.self)
        entity.properties = [
            attr("id", .stringAttributeType, false),
            attr("number", .stringAttributeType, false),
            attr("direction", .stringAttributeType, false),
            attr("status", .stringAttributeType, false),
            attr("startedAt", .dateAttributeType, false),
            attr("endedAt", .dateAttributeType, true),
            attr("lineId", .stringAttributeType, false)
        ]
        return entity
    }

    private static func attr(_ name: String,
                             _ type: NSAttributeType,
                             _ optional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
