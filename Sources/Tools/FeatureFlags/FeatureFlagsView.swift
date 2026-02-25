//
//  FeatureFlagsView.swift
//  EnsWilde
//
//  UI for configuring iOS Feature Flags
//

import SwiftUI

struct FeatureFlagsView: View {
    @ObservedObject var store: FeatureFlagsStore
    @Environment(\.dismiss) private var dismiss
    
    // Localization
    @ObservedObject private var localizationManager = LocalizationManager.shared

    /// True on iOS 18.2+ and iOS 26+ where the FeatureFlags folder must be pre-created
    private var needsFolderCreation: Bool {
        Utils.os.majorVersion > 18 || (Utils.os.majorVersion == 18 && Utils.os.minorVersion >= 2)
    }
    
    var body: some View {
        Form {
            // Feature Flags Section
            Section(header: Text(L("ff_section_header"))) {
                Toggle(L("ff_enable"), isOn: $store.featureFlagsEnabled)
            }

            // iOS 18.2+ Warning and Folder Creation
            if needsFolderCreation {
                Section(header: Text(L("ff_ios182_header"))) {
                    Toggle(isOn: $store.folderCreated) {
                        Text(L("ff_create_folder"))
                    }
                }
            }

            // Liquid Glass Section (all-in-one toggle, no icon)
            Section(header: Text(L("ff_liquid_glass_header"))) {
                Toggle(isOn: Binding(
                    get: { store.areAllLiquidGlassEnabled() },
                    set: { _ in store.toggleAllLiquidGlass() }
                )) {
                    Text(L("ff_disable_all_liquid_glass"))
                }
            }

            // Other Feature Flags Groups (clock_anim is always-on and hidden from UI)
            ForEach(["Basic", "Lockscreen", "Photos", "AI"], id: \.self) { groupName in
                if let flags = FeatureFlagPresets.groupedFlags[groupName] {
                    let visible = flags.filter { $0.id != FeatureFlagPresets.clockAnimFlagID }
                    if !visible.isEmpty {
                        featureFlagGroupSection(groupName: groupName, flags: visible)
                    }
                }
            }

            // Reset Button
            if !store.enabledFlags.isEmpty {
                Section(header: Text(L("section_actions"))) {
                    Button(role: .destructive, action: {
                        store.resetAll()
                    }) {
                        Label(L("ff_reset_all"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_feature_flags"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto-enable folder creation if already enabled on a device that needs it
            if store.featureFlagsEnabled && needsFolderCreation {
                store.folderCreated = true
            }
        }
        .onChange(of: store.featureFlagsEnabled) { enabled in
            // When Feature Flags are turned on, automatically enable folder creation on iOS 18.2+/26+
            if enabled && needsFolderCreation {
                store.folderCreated = true
            }
        }
    }
    
    // MARK: - Feature Flag Group Section
    
    @ViewBuilder
    private func featureFlagGroupSection(groupName: String, flags: [FeatureFlag]) -> some View {
        let localizedGroupName: String = {
            switch groupName {
            case "Basic": return L("ff_group_basic")
            case "Lockscreen": return L("ff_group_lockscreen")
            case "Photos": return L("ff_group_photos")
            case "AI": return L("ff_group_ai")
            default: return groupName
            }
        }()
        Section(header: Text(localizedGroupName)) {
            ForEach(flags) { flag in
                Toggle(isOn: Binding(
                    get: { store.isFlagEnabled(flag.id) },
                    set: { _ in store.toggleFlag(flag.id) }
                )) {
                    Text(flag.localizedDisplayName)
                }
            }
        }
    }
}

// MARK: - Preview

struct FeatureFlagsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeatureFlagsView(store: FeatureFlagsStore())
        }
    }
}
