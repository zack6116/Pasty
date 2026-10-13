import Foundation

public struct InstallReport: Codable, Equatable {
    public let product: String
    public let installId: String
    public let appVersion: String
    public let osVersion: String
    public let model: String
    public let arch: String
    public let locale: String

    public init(
        product: String,
        installId: String,
        appVersion: String,
        osVersion: String,
        model: String,
        arch: String,
        locale: String
    ) {
        self.product = product
        self.installId = installId
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.model = model
        self.arch = arch
        self.locale = locale
    }
}

public enum InstallIdentity {
    public static let defaultsKey = "installID"

    public static func installID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), UUID(uuidString: existing) != nil {
            return existing.lowercased()
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
