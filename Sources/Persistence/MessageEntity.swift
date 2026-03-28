import CoreData
import Foundation

@objc(MessageEntity)
final class MessageEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var body: String
    @NSManaged var number: String
    @NSManaged var direction: String
    @NSManaged var timestamp: Date
    @NSManaged var lineId: String
}

extension MessageEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MessageEntity> {
        NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
    }

    static func entityDescription() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "MessageEntity"
        entity.managedObjectClassName = NSStringFromClass(MessageEntity.self)
        entity.properties = [
            attr("id", .stringAttributeType, false),
            attr("body", .stringAttributeType, false),
            attr("number", .stringAttributeType, false),
            attr("direction", .stringAttributeType, false),
            attr("timestamp", .dateAttributeType, false),
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
