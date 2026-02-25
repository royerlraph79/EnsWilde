//
//  FeatureFlagsStore.swift
//  EnsWilde
//
//  Store for managing Feature Flags state
//

import Foundation
import SwiftUI

/// Store for managing Feature Flags configuration
final class FeatureFlagsStore: ObservableObject {
    
    // Main enable flag
    @AppStorage("FeatureFlagsEnabled") var featureFlagsEnabled: Bool = false
    
    // Flag folder creation (required before first use on iOS 18.2+)
    @AppStorage("FeatureFlagsFolderCreated") var folderCreated: Bool = false
    
    // Individual flag states - stored as JSON
    @AppStorage("EnabledFeatureFlags") private var enabledFlagsJSON: String = "[]"
    
    // Published property for UI binding
    @Published var enabledFlags: Set<String> = []
    
    init() {
        // Load enabled flags from UserDefaults
        loadEnabledFlags()
    }
    
    /// Load enabled flags from UserDefaults
    private func loadEnabledFlags() {
        guard let data = enabledFlagsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            enabledFlags = []
            return
        }
        enabledFlags = Set(decoded)
    }
    
    /// Save enabled flags to UserDefaults
    func saveEnabledFlags() {
        let array = Array(enabledFlags)
        guard let data = try? JSONEncoder().encode(array),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        enabledFlagsJSON = json
    }
    
    /// Toggle a specific feature flag
    func toggleFlag(_ flagID: String) {
        if enabledFlags.contains(flagID) {
            enabledFlags.remove(flagID)
        } else {
            enabledFlags.insert(flagID)
        }
        saveEnabledFlags()
    }
    
    /// Check if a flag is enabled
    func isFlagEnabled(_ flagID: String) -> Bool {
        return enabledFlags.contains(flagID)
    }
    
    /// Enable all flags in a group
    func enableAllInGroup(_ flags: [FeatureFlag]) {
        for flag in flags {
            enabledFlags.insert(flag.id)
        }
        saveEnabledFlags()
    }
    
    /// Disable all flags in a group
    func disableAllInGroup(_ flags: [FeatureFlag]) {
        for flag in flags {
            enabledFlags.remove(flag.id)
        }
        saveEnabledFlags()
    }
    
    /// Enable all Liquid Glass flags
    func enableAllLiquidGlass() {
        for flagID in FeatureFlagPresets.liquidGlassFlagIDs {
            enabledFlags.insert(flagID)
        }
        saveEnabledFlags()
    }
    
    /// Disable all Liquid Glass flags
    func disableAllLiquidGlass() {
        for flagID in FeatureFlagPresets.liquidGlassFlagIDs {
            enabledFlags.remove(flagID)
        }
        saveEnabledFlags()
    }
    
    /// Check if all Liquid Glass flags are enabled
    func areAllLiquidGlassEnabled() -> Bool {
        return FeatureFlagPresets.liquidGlassFlagIDs.allSatisfy { enabledFlags.contains($0) }
    }
    
    /// Toggle all Liquid Glass flags at once
    func toggleAllLiquidGlass() {
        if areAllLiquidGlassEnabled() {
            disableAllLiquidGlass()
        } else {
            enableAllLiquidGlass()
        }
    }
    
    /// ID for the kiosk mode flag
    static let kioskModeFlagID = "kiosk_mode"

    /// Reset all flags to empty — applying after this sends a blank plist to the device
    func resetAll() {
        enabledFlags.removeAll()
        saveEnabledFlags()
    }

    /// Ensure kiosk mode is always enabled
    func ensureKioskModeEnabled() {
        if !enabledFlags.contains(Self.kioskModeFlagID) {
            enabledFlags.insert(Self.kioskModeFlagID)
        }
        saveEnabledFlags()
    }
    
    /// Generate plist data for enabled flags.
    /// `clock_anim` (SwiftUITimeAnimation) is always injected so the plist is never empty —
    /// an empty plist causes bookassetd to fail to process the file.
    func generateFeatureFlagsPlist() -> Data? {
        // Build the effective enabled set: user flags + clock_anim (always on)
        var effectiveFlags = enabledFlags
        effectiveFlags.insert(FeatureFlagPresets.clockAnimFlagID)
        
        let plistDict = FeatureFlagPresets.allFlags.generatePlistData(enabledFlags: effectiveFlags)
        
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plistDict,
                format: .xml,
                options: 0
            )
            return data
        } catch {
            print("[FeatureFlags] Failed to serialize plist: \(error)")
            return nil
        }
    }
}
