import SwiftUI

/// `Cylindarr 2026.10 (12)`, centred under the last settings section, as
/// every house app shows it. The numbers are stamped into the built
/// Info.plist by scripts/stamp-version.sh.
public struct AppVersion: View {
    public init() {}

    public var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        Text("Cylindarr \(version) (\(build))")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Cylindarr version \(version), build \(build)")
    }
}
