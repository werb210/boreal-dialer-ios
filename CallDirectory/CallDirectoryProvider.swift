import CallKit

final class CallDirectoryProvider: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        // An incremental request may follow any older snapshot. Clear it before
        // replaying the complete, sorted snapshot so deletions are represented too.
        if context.isIncremental {
            context.removeAllIdentificationEntries()
        }

        for entry in CallDirectoryStore.entries() {
            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: entry.phoneNumber,
                label: entry.label
            )
        }
        context.completeRequest()
    }
}

extension CallDirectoryProvider: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // The system records the extension failure; there is no app process to notify here.
    }
}
