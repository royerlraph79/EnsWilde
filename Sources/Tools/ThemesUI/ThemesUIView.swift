import SwiftUI

struct ThemesUIView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    let globalPrefsURL: URL
    let springboardPrefsURL: URL
    
    // Solarium/Liquid Glass toggles
    @State private var solariumForceFallback = false          // SolariumForceFallback
    @State private var disableSolarium = false                 // com.apple.SwiftUI.DisableSolarium
    @State private var ignoreSolariumLinkedOnCheck = false     // com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck
    @State private var disallowGlassTime = false               // SBDisallowGlassTime
    @State private var disableGlassDock = false                // SBDisableGlassDock
    @State private var disableSpecularMotion = false           // SBDisableSpecularEverywhereUsingLSSAssertion
    @State private var disableOuterRefraction = false          // SolariumDisableOuterRefraction
    @State private var allowHDR = true                         // SolariumAllowHDR (include only when false)
    
    // Springboard Options
    @State private var suppressDynamicIsland = false           // SBSuppressDynamicIslandCompletely
    
    var body: some View {
        Form {
            // Enable Tool
            Section(L("themes_ui_title")) {
                Toggle(L("enable_tool"), isOn: $toolStore.themesUIEnabled)
            }

            // Liquid Glass (Solarium) Section
            Section(header: Text(L("section_liquid_glass"))) {
                Toggle(L("themes_force_fallback"), isOn: $solariumForceFallback)
                    .onChange(of: solariumForceFallback) { autoSave() }

                Toggle(L("themes_disable_swiftui"), isOn: $disableSolarium)
                    .onChange(of: disableSolarium) { autoSave() }

                Toggle(L("themes_ignore_check"), isOn: $ignoreSolariumLinkedOnCheck)
                    .onChange(of: ignoreSolariumLinkedOnCheck) { autoSave() }

                Toggle(L("themes_disable_glass_time"), isOn: $disallowGlassTime)
                    .onChange(of: disallowGlassTime) { autoSave() }

                Toggle(L("themes_disable_glass_dock"), isOn: $disableGlassDock)
                    .onChange(of: disableGlassDock) { autoSave() }

                Toggle(L("themes_disable_specular"), isOn: $disableSpecularMotion)
                    .onChange(of: disableSpecularMotion) { autoSave() }

                Toggle(L("themes_disable_refraction"), isOn: $disableOuterRefraction)
                    .onChange(of: disableOuterRefraction) { autoSave() }

                Toggle(L("themes_disable_hdr"), isOn: Binding(
                    get: { !allowHDR },
                    set: { allowHDR = !$0 }
                ))
                .onChange(of: allowHDR) { autoSave() }
            }

            // Springboard Options Section
            Section(header: Text(L("themes_springboard_section"))) {
                Toggle(L("themes_hide_dynamic_island"), isOn: $suppressDynamicIsland)
                    .onChange(of: suppressDynamicIsland) { autoSave() }
            }

            // Reset Section
            Section(header: Text(L("section_save_settings"))) {
                Button(L("themes_reset_button"), role: .destructive) {
                    resetAllSettings()
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle("Themes UI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAllPreferences()
        }
    }

    private func loadAllPreferences() {
        // Load GlobalPreferences.plist
        if FileManager.default.fileExists(atPath: globalPrefsURL.path) {
            if let dict = NSDictionary(contentsOf: globalPrefsURL) as? [String: Any] {
                solariumForceFallback = (dict["SolariumForceFallback"] as? Bool) ?? false
                disableSolarium = (dict["com.apple.SwiftUI.DisableSolarium"] as? Bool) ?? false
                ignoreSolariumLinkedOnCheck = (dict["com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"] as? Bool) ?? false
                disallowGlassTime = (dict["SBDisallowGlassTime"] as? Bool) ?? false
                disableGlassDock = (dict["SBDisableGlassDock"] as? Bool) ?? false
                disableSpecularMotion = (dict["SBDisableSpecularEverywhereUsingLSSAssertion"] as? Bool) ?? false
                disableOuterRefraction = (dict["SolariumDisableOuterRefraction"] as? Bool) ?? false
                allowHDR = (dict["SolariumAllowHDR"] as? Bool) ?? true
            }
        }

        // Load SpringboardPreferences.plist
        if FileManager.default.fileExists(atPath: springboardPrefsURL.path) {
            if let dict = NSDictionary(contentsOf: springboardPrefsURL) as? [String: Any] {
                suppressDynamicIsland = (dict["SBSuppressDynamicIslandCompletely"] as? Bool) ?? false
            }
        }
        
        // Ensure plists always exist on disk so collectThemesUIFiles() can find them
        autoSave()
    }

    /// Auto-save: only write keys that are non-default into GlobalPreferences.plist.
    /// SpringboardPreferences.plist always includes SBSuppressDynamicIslandCompletely
    /// with the explicit current value so turning it OFF sends `false` to the device.
    private func autoSave() {
        // Build GlobalPreferences.plist with only active (true) keys
        let globalDict = NSMutableDictionary()
        if solariumForceFallback { globalDict["SolariumForceFallback"] = true }
        if disableSolarium { globalDict["com.apple.SwiftUI.DisableSolarium"] = true }
        if ignoreSolariumLinkedOnCheck { globalDict["com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"] = true }
        if disallowGlassTime { globalDict["SBDisallowGlassTime"] = true }
        if disableGlassDock { globalDict["SBDisableGlassDock"] = true }
        if disableSpecularMotion { globalDict["SBDisableSpecularEverywhereUsingLSSAssertion"] = true }
        if disableOuterRefraction { globalDict["SolariumDisableOuterRefraction"] = true }
        if !allowHDR { globalDict["SolariumAllowHDR"] = false }
        try? (globalDict as NSDictionary).write(to: globalPrefsURL)

        // Build SpringboardPreferences.plist — always write the explicit current value.
        // When DI is OFF, sending `false` ensures the device removes the suppression.
        let sbDict: NSDictionary = ["SBSuppressDynamicIslandCompletely": suppressDynamicIsland]
        try? sbDict.write(to: springboardPrefsURL)

        toolStore.themesUIEnabled = true
    }

    private func resetAllSettings() {
        solariumForceFallback = false
        disableSolarium = false
        ignoreSolariumLinkedOnCheck = false
        disallowGlassTime = false
        disableGlassDock = false
        disableSpecularMotion = false
        disableOuterRefraction = false
        allowHDR = true
        suppressDynamicIsland = false
        autoSave()
    }
    
    init(toolStore: ToolStore) {
        self.toolStore = toolStore
        let documentsDirectory = URL.documentsDirectory
        globalPrefsURL = documentsDirectory.appendingPathComponent("GlobalPreferences.plist")
        springboardPrefsURL = documentsDirectory.appendingPathComponent("SpringboardPreferences.plist")
    }
}
