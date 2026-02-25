//
//  FeatureFlagsModel.swift
//  EnsWilde
//
//  Feature Flags models based on Nugget implementation
//

import Foundation

/// Represents a single feature flag entry
struct FeatureFlag: Identifiable, Codable {
    let id: String
    let category: String
    let flagNames: [String]
    let displayName: String
    let description: String
    let isList: Bool
    let inverted: Bool
    
    init(
        id: String,
        category: String,
        flagNames: [String],
        displayName: String,
        description: String,
        isList: Bool = true,
        inverted: Bool = false
    ) {
        self.id = id
        self.category = category
        self.flagNames = flagNames
        self.displayName = displayName
        self.description = description
        self.isList = isList
        self.inverted = inverted
    }
    
    /// Localized display name using the L() system, falling back to the raw displayName
    var localizedDisplayName: String {
        let key = "ff_flag_\(id)"
        let localized = L(key)
        // If the key exists in the localization system it returns a real string;
        // if it falls back to the key itself, use the hardcoded displayName instead.
        return localized == key ? displayName : localized
    }
}

/// Available feature flags based on Nugget's implementation
enum FeatureFlagPresets {
    /// ID for the clock animation flag — always enabled in the plist, hidden from UI
    static let clockAnimFlagID = "clock_anim"

    static let allFlags: [FeatureFlag] = [
        // Clock Animation
        FeatureFlag(
            id: "clock_anim",
            category: "SpringBoard",
            flagNames: ["SwiftUITimeAnimation"],
            displayName: "Clock Animation",
            description: "Enable animated clock on lock screen"
        ),
        
        // Lockscreen Features
        FeatureFlag(
            id: "lockscreen",
            category: "SpringBoard",
            flagNames: ["AutobahnQuickSwitchTransition", "SlipSwitch", "PosterEditorKashida"],
            displayName: "Lockscreen Features",
            description: "Enable advanced lockscreen transitions and editor features"
        ),
        
        // Photos UI (Inverted - enable to disable new UI)
        FeatureFlag(
            id: "photos_ui",
            category: "Photos",
            flagNames: ["Lemonade"],
            displayName: "Disable New Photos UI",
            description: "Revert to old Photos UI (iOS 18 beta only)",
            isList: false,
            inverted: true
        ),
        
        // AI Features
        FeatureFlag(
            id: "ai",
            category: "SpringBoard",
            flagNames: ["Domino", "SuperDomino"],
            displayName: "AI Features",
            description: "Enable AI-related features (Domino & SuperDomino)"
        ),
        
        // Kiosk Mode
        FeatureFlag(
            id: "kiosk_mode",
            category: "PreferencesFramework",
            flagNames: ["ForcedRetailKioskMode"],
            displayName: "Kiosk Mode",
            description: "Enable forced retail kiosk mode"
        ),
        
        // Liquid Glass/Solarium - SwiftUI
        FeatureFlag(
            id: "solarium_swiftui",
            category: "SwiftUI",
            flagNames: ["Solarium"],
            displayName: "Disable Solarium (SwiftUI)",
            description: "Disable Liquid Glass in SwiftUI",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - SpringBoard
        FeatureFlag(
            id: "solarium_springboard",
            category: "SpringBoard",
            flagNames: ["SolariumElasticHUD"],
            displayName: "Disable Solarium (SpringBoard)",
            description: "Disable Liquid Glass elastic HUD",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - IconServices
        FeatureFlag(
            id: "solarium_iconservices",
            category: "IconServices",
            flagNames: ["EnhancedGlass", "SolariumCornerRadius"],
            displayName: "Disable Solarium (Icons)",
            description: "Disable Liquid Glass icon enhancements",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - Photos Group
        FeatureFlag(
            id: "solarium_photos",
            category: "Photos",
            flagNames: ["SolariumGridMagicPocket"],
            displayName: "Disable Solarium (Photos)",
            description: "Disable Liquid Glass in Photos",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - DocumentCamera
        FeatureFlag(
            id: "solarium_documentcamera",
            category: "DocumentCamera",
            flagNames: ["CaptureLiquidGlass"],
            displayName: "Disable Solarium (Camera)",
            description: "Disable Liquid Glass in document camera",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - AppleMediaServices
        FeatureFlag(
            id: "solarium_ams",
            category: "AppleMediaServices",
            flagNames: ["Solarium"],
            displayName: "Disable Solarium (Media)",
            description: "Disable Liquid Glass in Apple Media Services",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - Sharing
        FeatureFlag(
            id: "solarium_sharing",
            category: "Sharing",
            flagNames: ["ShareSheetSolarium"],
            displayName: "Disable Solarium (Sharing)",
            description: "Disable Liquid Glass in share sheet",
            inverted: true
        ),
        
        // Liquid Glass/Solarium - Mail
        FeatureFlag(
            id: "solarium_mail",
            category: "Mail",
            flagNames: ["SolariumSearch"],
            displayName: "Disable Solarium (Mail)",
            description: "Disable Liquid Glass in Mail search",
            inverted: true
        )
    ]
    
    /// Get all Liquid Glass flag IDs
    static var liquidGlassFlagIDs: [String] {
        return [
            "solarium_swiftui",
            "solarium_springboard",
            "solarium_iconservices",
            "solarium_photos",
            "solarium_documentcamera",
            "solarium_ams",
            "solarium_sharing",
            "solarium_mail"
        ]
    }
    
    /// Get flags grouped by category for UI display
    static var groupedFlags: [String: [FeatureFlag]] {
        var groups: [String: [FeatureFlag]] = [:]
        
        // Define display order for groups
        let groupOrder = ["Basic", "Lockscreen", "Photos", "AI", "Liquid Glass"]
        
        for flag in allFlags {
            let groupName: String
            if flag.id.hasPrefix("solarium_") {
                groupName = "Liquid Glass"
            } else if flag.id == "clock_anim" || flag.id == "kiosk_mode" {
                groupName = "Basic"
            } else if flag.id == "lockscreen" {
                groupName = "Lockscreen"
            } else if flag.id == "photos_ui" {
                groupName = "Photos"
            } else if flag.id == "ai" {
                groupName = "AI"
            } else {
                groupName = "Other"
            }
            
            if groups[groupName] == nil {
                groups[groupName] = []
            }
            groups[groupName]?.append(flag)
        }
        
        return groups
    }
}

/// Extension to generate plist data from enabled flags
extension Array where Element == FeatureFlag {
    /// Generate the plist dictionary for enabled flags
    func generatePlistData(enabledFlags: Set<String>) -> [String: Any] {
        var plist: [String: Any] = [:]
        
        for flag in self where enabledFlags.contains(flag.id) {
            // Determine if this flag should be enabled or disabled
            let shouldEnable = !flag.inverted
            
            // Create category if it doesn't exist
            if plist[flag.category] == nil {
                plist[flag.category] = [String: Any]()
            }
            
            guard var categoryDict = plist[flag.category] as? [String: Any] else {
                continue
            }
            
            // Add each flag name to the category
            for flagName in flag.flagNames {
                if flag.isList {
                    // Format: {"FlagName": {"Enabled": true/false}}
                    categoryDict[flagName] = ["Enabled": shouldEnable]
                } else {
                    // Format: {"FlagName": true/false}
                    categoryDict[flagName] = shouldEnable
                }
            }
            
            plist[flag.category] = categoryDict
        }
        
        return plist
    }
}
