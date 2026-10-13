import Darwin
import Foundation
import PastyCore

enum InstallReporter {
    static let endpoint = URL(string: "https://ops.coderfather.com/v1/report")!

    static func send() {
        let report = makeReport()
        guard let body = try? JSONEncoder().encode(report) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Pasty/\(report.appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }

    static func makeReport() -> InstallReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return InstallReport(
            product: "pasty",
            installId: InstallIdentity.installID(),
            appVersion: version?.isEmpty == false ? version! : "dev",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: hardwareModel(),
            arch: architecture(),
            locale: Locale.current.identifier
        )
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        let model = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "unknown" : model
    }

    private static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
