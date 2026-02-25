import AppIntents

@available(iOS 16.0, *)
struct ApplyTweaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply EnsWilde Tweaks"
    static var description = IntentDescription("Apply all enabled EnsWilde tweaks to your device.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Post notification to trigger apply from the app's main UI
        await MainActor.run {
            NotificationCenter.default.post(name: .applyTweaksFromShortcut, object: nil)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct EnsWildeShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyTweaksIntent(),
            phrases: [
                "Apply tweaks with \(.applicationName)",
                "Run \(.applicationName)",
                "Apply \(.applicationName)"
            ],
            shortTitle: "Apply Tweaks",
            systemImageName: "checkmark.circle.fill"
        )
    }
}

extension Notification.Name {
    static let applyTweaksFromShortcut = Notification.Name("EnsWilde.applyTweaksFromShortcut")
}
