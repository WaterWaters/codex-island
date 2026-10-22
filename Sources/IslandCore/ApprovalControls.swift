import Foundation

public struct ApprovalControl: Sendable {
    public let label: String
    public let enabled: Bool
    public init(label: String, enabled: Bool = true) { self.label = label; self.enabled = enabled }
}

/// Recognize a paired decision in one small UI group, never tool arguments or
/// the mere fact that a command requested elevated permissions.
public enum ApprovalControls {
    private static let allow: Set<String> = ["allow once", "allow", "approve", "approve once", "允许一次", "仅允许一次", "仅本次允许", "允许这一次", "允许", "批准", "批准一次"]
    private static let deny: Set<String> = ["deny", "decline", "reject", "拒绝", "不允许", "拒绝请求"]
    public static func isPending(_ controls: [ApprovalControl]) -> Bool {
        guard (2...12).contains(controls.count) else { return false }
        let labels = Set(controls.filter(\.enabled).map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return !labels.isDisjoint(with: allow) && !labels.isDisjoint(with: deny)
    }
}
