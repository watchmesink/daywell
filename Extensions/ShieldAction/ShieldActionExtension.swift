import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action, targetKind: "application")
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action, targetKind: "website")
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action, targetKind: "category")
        completionHandler(.close)
    }

    private func record(_ action: ShieldAction, targetKind: String) {
        ProtectionEnvironment.record("shield.action", details: ["targetKind": targetKind,
            "action": String(action.rawValue), "response": "close"])
    }
}
