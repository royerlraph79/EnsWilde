import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType Extension for .passthm files
extension UTType {
    static var passthm: UTType {
        UTType(importedAs: "com.enswilde.passthm")
    }
}

// MARK: - Passcode Theme Model
struct PasscodeTheme: Identifiable, Codable {
    let id: UUID
    var name: String
    var isSelected: Bool
    var customPrefix: PrefixLanguage
    var keySize: KeySize
    var telephonyVersion: TelephonyVersion
    
    enum PrefixLanguage: String, Codable, CaseIterable {
        case af = "af"
        case ar = "ar"
        case az = "az"
        case bg = "bg"
        case bn = "bn"
        case ca = "ca"
        case cs = "cs"
        case da = "da"
        case de = "de"
        case el = "el"
        case en = "en"
        case es = "es"
        case et = "et"
        case eu = "eu"
        case fa = "fa"
        case fi = "fi"
        case fil = "fil"
        case fr = "fr"
        case gl = "gl"
        case he = "he"
        case hi = "hi"
        case hr = "hr"
        case hu = "hu"
        case hy = "hy"
        case id = "id"
        case `is` = "is"
        case it = "it"
        case ja = "ja"
        case ka = "ka"
        case kk = "kk"
        case ko = "ko"
        case lt = "lt"
        case lv = "lv"
        case mk = "mk"
        case ml = "ml"
        case mr = "mr"
        case ms = "ms"
        case nb = "nb"
        case nl = "nl"
        case nn = "nn"
        case no = "no"
        case pl = "pl"
        case pt = "pt"
        case ro = "ro"
        case ru = "ru"
        case sk = "sk"
        case sl = "sl"
        case sq = "sq"
        case sr = "sr"
        case sv = "sv"
        case sw = "sw"
        case ta = "ta"
        case te = "te"
        case th = "th"
        case tr = "tr"
        case uk = "uk"
        case ur = "ur"
        case vi = "vi"
        case zh = "zh"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .af: return "Afrikaans"
            case .ar: return "Arabic"
            case .az: return "Azerbaijani"
            case .bg: return "Bulgarian"
            case .bn: return "Bengali"
            case .ca: return "Catalan"
            case .cs: return "Czech"
            case .da: return "Danish"
            case .de: return "German"
            case .el: return "Greek"
            case .en: return "English"
            case .es: return "Spanish"
            case .et: return "Estonian"
            case .eu: return "Basque"
            case .fa: return "Persian"
            case .fi: return "Finnish"
            case .fil: return "Filipino"
            case .fr: return "French"
            case .gl: return "Galician"
            case .he: return "Hebrew"
            case .hi: return "Hindi"
            case .hr: return "Croatian"
            case .hu: return "Hungarian"
            case .hy: return "Armenian"
            case .id: return "Indonesian"
            case .`is`: return "Icelandic"
            case .it: return "Italian"
            case .ja: return "Japanese"
            case .ka: return "Georgian"
            case .kk: return "Kazakh"
            case .ko: return "Korean"
            case .lt: return "Lithuanian"
            case .lv: return "Latvian"
            case .mk: return "Macedonian"
            case .ml: return "Malayalam"
            case .mr: return "Marathi"
            case .ms: return "Malay"
            case .nb: return "Norwegian Bokmål"
            case .nl: return "Dutch"
            case .nn: return "Norwegian Nynorsk"
            case .no: return "Norwegian"
            case .pl: return "Polish"
            case .pt: return "Portuguese"
            case .ro: return "Romanian"
            case .ru: return "Russian"
            case .sk: return "Slovak"
            case .sl: return "Slovenian"
            case .sq: return "Albanian"
            case .sr: return "Serbian"
            case .sv: return "Swedish"
            case .sw: return "Swahili"
            case .ta: return "Tamil"
            case .te: return "Telugu"
            case .th: return "Thai"
            case .tr: return "Turkish"
            case .uk: return "Ukrainian"
            case .ur: return "Urdu"
            case .vi: return "Vietnamese"
            case .zh: return "Chinese"
            case .other: return "Other Languages"
            }
        }
        
        var description: String {
            return "Use '\(self.rawValue)' prefix for passcode theme files"
        }
    }
    
    enum KeySize: String, Codable, CaseIterable {
        case small = "Small Keys"
        case big = "Big Keys"
        
        /// Reference dimension for small passcode keys in pixels (from Nugget Python implementation)
        /// Used as the base for calculating scale factors when converting between small and big sizes.
        /// Value: 202 pixels
        static let smallTargetSize: CGFloat = 202.0
        
        /// Reference dimension for big passcode keys in pixels (from Nugget Python implementation)
        /// Used as the base for calculating scale factors when converting between small and big sizes.
        /// Value: 287 pixels
        static let bigTargetSize: CGFloat = 287.0
        
        /// Threshold for determining if scaling is needed (1% difference)
        /// If the scale factor differs from 1.0 by less than this threshold, no resize is performed
        static let resizeThreshold: CGFloat = 0.01
        
        /// Get the reference dimension for this key size
        var targetSize: CGFloat {
            switch self {
            case .small: return Self.smallTargetSize
            case .big: return Self.bigTargetSize
            }
        }
        
        var scaleFactor: CGFloat {
            switch self {
            case .small: return Self.smallTargetSize / Self.bigTargetSize  // Big to Small
            case .big: return Self.bigTargetSize / Self.smallTargetSize    // Small to Big
            }
        }
    }
    
    enum TelephonyVersion: String, Codable, CaseIterable {
        case telephony8 = "TelephonyUI-8"
        case telephony9 = "TelephonyUI-9"
        case telephony10 = "TelephonyUI-10"
        
        var displayName: String {
            switch self {
            case .telephony8: return "Telephony 8"
            case .telephony9: return "Telephony 9"
            case .telephony10: return "Telephony 10"
            }
        }
        
        var cachePath: String {
            return "/var/mobile/Library/Caches/\(self.rawValue)/"
        }
    }
    
    enum DetectedSize: Int, Codable {
        case unknown = 0
        case small = 1
        case big = 2
    }
    
    // Auto-detected size from ZIP file (before extraction)
    var detectedSize: DetectedSize = .unknown
    
    // Get the theme's folder path in Documents
    var themeFolderURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("PasscodeThemes")
            .appendingPathComponent(id.uuidString)
    }
    
    init(id: UUID = UUID(), name: String, customPrefix: PrefixLanguage = .en, keySize: KeySize = .small, detectedSize: DetectedSize = .unknown, telephonyVersion: TelephonyVersion = .telephony10) {
        self.id = id
        self.name = name
        self.isSelected = false
        self.customPrefix = customPrefix
        self.keySize = keySize
        self.detectedSize = detectedSize
        self.telephonyVersion = telephonyVersion
    }
    
    // Get preview image (the "0" key image)
    func getPreviewImage() -> UIImage? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: themeFolderURL.path) else { return nil }
        
        // Look for file containing "-0-" or "-0@" for the 0 key
        if let zeroFile = files.first(where: { $0.contains("-0-") || $0.contains("-0@") }) {
            let imageURL = themeFolderURL.appendingPathComponent(zeroFile)
            return UIImage(contentsOfFile: imageURL.path)
        }
        
        return nil
    }
    
    // Get all image files in the theme folder
    func getImageFiles() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: themeFolderURL.path) else { return [] }
        
        // Filter for image files
        return files.filter { file in
            let ext = (file as NSString).pathExtension.lowercased()
            return ext == "png" || ext == "jpg" || ext == "jpeg"
        }
    }
}

// MARK: - Passcode Theme Store
class PasscodeThemeStore: ObservableObject {
    @Published var themes: [PasscodeTheme] = []
    @AppStorage("PasscodeThemeEnabled") var passcodeThemeEnabled: Bool = false
    @AppStorage("GlobalPasscodeLanguage") var globalCustomPrefixRaw: String = "en"
    @AppStorage("GlobalTelephonyVersion") var globalTelephonyVersionRaw: String = "TelephonyUI-10"
    
    var globalCustomPrefix: PasscodeTheme.PrefixLanguage {
        get { PasscodeTheme.PrefixLanguage(rawValue: globalCustomPrefixRaw) ?? .en }
        set { globalCustomPrefixRaw = newValue.rawValue }
    }
    
    var globalTelephonyVersion: PasscodeTheme.TelephonyVersion {
        get { PasscodeTheme.TelephonyVersion(rawValue: globalTelephonyVersionRaw) ?? .telephony10 }
        set { globalTelephonyVersionRaw = newValue.rawValue }
    }
    
    private let themesFileURL: URL
    
    init() {
        themesFileURL = URL.documentsDirectory.appendingPathComponent("PasscodeThemes.json")
        loadThemes()
    }
    
    func loadThemes() {
        guard FileManager.default.fileExists(atPath: themesFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: themesFileURL)
            themes = try JSONDecoder().decode([PasscodeTheme].self, from: data)
        } catch {
            print("Failed to load passcode themes: \(error)")
        }
    }
    
    func saveThemes() {
        do {
            let data = try JSONEncoder().encode(themes)
            try data.write(to: themesFileURL, options: .atomic)
        } catch {
            print("Failed to save passcode themes: \(error)")
        }
    }
    
    func addTheme(_ theme: PasscodeTheme) {
        themes.append(theme)
        saveThemes()
    }
    
    func updateTheme(_ theme: PasscodeTheme) {
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
            saveThemes()
        }
    }
    
    func deleteTheme(_ theme: PasscodeTheme) {
        themes.removeAll { $0.id == theme.id }
        saveThemes()
        
        // Delete the theme's folder from Documents
        try? FileManager.default.removeItem(at: theme.themeFolderURL)
    }
    
    func selectTheme(_ theme: PasscodeTheme) {
        // Deselect all themes first
        for i in 0..<themes.count {
            themes[i].isSelected = false
        }
        
        // Select the chosen theme
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index].isSelected = true
        }
        
        saveThemes()
    }
    
    func getSelectedTheme() -> PasscodeTheme? {
        themes.first { $0.isSelected }
    }
}
