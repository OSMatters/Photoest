import FirebaseCore
import FirebaseRemoteConfig
import Foundation

enum FirebaseBootstrap {
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil else { return }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("Firebase skipped: GoogleService-Info.plist is not bundled.")
            #endif
            return
        }

        FirebaseApp.configure()
    }
}

struct AppUpdatePrompt: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let updateURL: URL
    let version: String
    let isRequired: Bool
}

enum RemoteConfigService {
    private static let dismissedUpdateVersionKey = "photoest.dismissedUpdatePromptVersion"

    private enum Key {
        static let updateEnabled = "ios_update_enabled"
        static let latestVersion = "ios_latest_version"
        static let minimumSupportedVersion = "ios_min_supported_version"
        static let updateRequired = "ios_update_required"
        static let updateTitle = "ios_update_title"
        static let updateMessage = "ios_update_message"
        static let updateURL = "ios_update_url"
    }

    private static let defaults: [String: NSObject] = [
        Key.updateEnabled: false as NSNumber,
        Key.latestVersion: "" as NSString,
        Key.minimumSupportedVersion: "" as NSString,
        Key.updateRequired: false as NSNumber,
        Key.updateTitle: "" as NSString,
        Key.updateMessage: "" as NSString,
        Key.updateURL: "" as NSString
    ]

    static func fetchUpdatePrompt() async -> AppUpdatePrompt? {
        guard FirebaseApp.app() != nil else { return nil }

        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.fetchTimeout = 10
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 60 * 60
        #endif
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults(defaults)

        await fetchAndActivate(remoteConfig)
        return makeUpdatePrompt(from: remoteConfig)
    }

    static func markUpdatePromptDismissed(_ prompt: AppUpdatePrompt) {
        guard !prompt.isRequired else { return }
        UserDefaults.standard.set(prompt.version, forKey: dismissedUpdateVersionKey)
    }

    private static func fetchAndActivate(_ remoteConfig: RemoteConfig) async {
        await withCheckedContinuation { continuation in
            remoteConfig.fetchAndActivate { _, _ in
                continuation.resume()
            }
        }
    }

    private static func makeUpdatePrompt(from remoteConfig: RemoteConfig) -> AppUpdatePrompt? {
        guard remoteConfig[Key.updateEnabled].boolValue else { return nil }

        let currentVersion = Bundle.main.shortVersionString
        let latestVersion = remoteConfig[Key.latestVersion].trimmedStringValue
        let minimumSupportedVersion = remoteConfig[Key.minimumSupportedVersion].trimmedStringValue
        let isBelowLatest = latestVersion.isMeaningfulVersion && AppVersion(currentVersion) < AppVersion(latestVersion)
        let isBelowMinimum = minimumSupportedVersion.isMeaningfulVersion &&
            AppVersion(currentVersion) < AppVersion(minimumSupportedVersion)
        let isRequired = remoteConfig[Key.updateRequired].boolValue || isBelowMinimum
        let targetVersion = latestVersion.isMeaningfulVersion ? latestVersion : minimumSupportedVersion

        guard targetVersion.isMeaningfulVersion, isBelowLatest || isBelowMinimum else { return nil }

        if !isRequired,
           UserDefaults.standard.string(forKey: dismissedUpdateVersionKey) == targetVersion {
            return nil
        }

        let urlString = remoteConfig[Key.updateURL].trimmedStringValue
        guard let updateURL = URL(string: urlString), updateURL.scheme != nil else { return nil }

        let title = remoteConfig[Key.updateTitle].trimmedStringValue
        let message = remoteConfig[Key.updateMessage].trimmedStringValue

        return AppUpdatePrompt(
            id: targetVersion,
            title: title.isEmpty ? L10n.string("updatePrompt.title") : title,
            message: message.isEmpty ? L10n.string("updatePrompt.message") : message,
            updateURL: updateURL,
            version: targetVersion,
            isRequired: isRequired
        )
    }
}

private struct AppVersion: Comparable {
    private let components: [Int]

    init(_ string: String) {
        components = string
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)

        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}

private extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

private extension RemoteConfigValue {
    var trimmedStringValue: String {
        stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var isMeaningfulVersion: Bool {
        contains { $0.isNumber }
    }
}
