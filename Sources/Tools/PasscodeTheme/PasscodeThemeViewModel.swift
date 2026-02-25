import Foundation
import SwiftUI
import UIKit
import ZIPFoundation

// MARK: - Passcode Theme ViewModel
@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    // Import a .passthm file (ZIP archive)
    // FIX: Copy to temp directory first to avoid Security Scope / Sandbox access errors with ZIPFoundation
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. Access the security-scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 2. Create a temporary URL in the App's sandbox
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Clean up previous temp file if exists
        try? FileManager.default.removeItem(at: tempFileURL)
        
        // 3. COPY the file to the temp directory
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            print("[PasscodeTheme] Copy to temp failed: \(error.localizedDescription)")
            throw PasscodeThemeError.accessDenied
        }
        
        // 4. Prepare target theme folder
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        // 5. Auto-detect size from ZIP before unzipping (like Nugget does)
        let detectedSize = detectSizeFromZIP(at: tempFileURL)
        print("[PasscodeTheme] Auto-detected size: \(detectedSize)")
        
        // 6. Unzip the TEMPORARY file (This is safe)
        do {
            try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
        } catch {
            print("[PasscodeTheme] Unzip failed: \(error.localizedDescription)")
            // Clean up created folder if unzip fails
            try? FileManager.default.removeItem(at: themeFolder)
            throw PasscodeThemeError.invalidFormat
        }
        
        // 7. Extract images from Telephony-X subfolder to theme root
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        // 8. Cleanup temp file
        try? FileManager.default.removeItem(at: tempFileURL)
        
        // 9. Update theme with detected size and add to store
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // Process and prepare files for apply
    func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage? = nil) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {
        var processedFiles: [(URL, Data, String)] = []
        
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else {
            throw PasscodeThemeError.noImagesFound
        }
        
        // Use global prefix if provided, otherwise fall back to theme's prefix
        let prefix = globalPrefix ?? store.globalCustomPrefix
        
        print("[PasscodeTheme] Processing \(imageFiles.count) files with detected size: \(theme.detectedSize), target size: \(theme.keySize)")
        
        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            
            // Extract prefix and suffix from filename
            guard let firstHyphen = filename.firstIndex(of: "-") else {
                // Skip files without hyphen (not in expected format)
                print("[PasscodeTheme] Skipping \(filename) - no hyphen found")
                continue
            }
            
            let suffix = String(filename[firstHyphen...])
            let newFilename = prefix.rawValue + suffix
            
            // Load and process image
            guard let image = UIImage(contentsOfFile: sourceURL.path) else {
                print("[PasscodeTheme] Failed to load image: \(filename)")
                continue
            }
            
            print("[PasscodeTheme] Processing: \(filename) -> \(newFilename), size: \(image.size)")
            
            // Resize based on key size setting and detected size (FIXED: Now matches Python logic)
            let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
            
            // Convert to PNG data
            guard let imageData = processedImage.pngData() else {
                print("[PasscodeTheme] Failed to convert to PNG: \(filename)")
                continue
            }
            
            print("[PasscodeTheme] Successfully processed: \(newFilename), new size: \(processedImage.size)")
            processedFiles.append((sourceURL, imageData, newFilename))
        }
        
        print("[PasscodeTheme] Total processed files: \(processedFiles.count)")
        return processedFiles
    }
    
    // FIXED: Resize image based on detected size and target size (matching Python logic exactly)
    private func resizeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        // Calculate size_multiplier exactly like Python code
        var sizeMultiplier: CGFloat = 1.0
        
        if detectedSize == .small && keySize == .big {
            // Convert small to big
            sizeMultiplier = 287.0 / 202.0  // ≈ 1.42
            print("[PasscodeTheme] Scaling Small → Big (×\(sizeMultiplier))")
        } else if detectedSize == .big && keySize == .small {
            // Convert big to small
            sizeMultiplier = 202.0 / 287.0  // ≈ 0.70
            print("[PasscodeTheme] Scaling Big → Small (×\(sizeMultiplier))")
        } else {
            // No scaling needed - sizes match or unknown
            print("[PasscodeTheme] No scaling needed (detected: \(detectedSize), target: \(keySize))")
            return image
        }
        
        // Check if scaling is needed (avoid unnecessary scaling for very similar sizes)
        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold {
            print("[PasscodeTheme] Scale factor very close to 1.0, skipping resize")
            return image
        }
        
        let currentSize = image.size
        
        // Guard against invalid image dimensions
        guard currentSize.width > 0 && currentSize.height > 0 else {
            print("[PasscodeTheme] Warning: Invalid image dimensions \(currentSize), returning original")
            return image
        }
        
        // Get actual pixel dimensions by accounting for image scale
        let currentPixelWidth = currentSize.width * image.scale
        let currentPixelHeight = currentSize.height * image.scale
        
        // Calculate target size in PIXELS by multiplying both dimensions
        // This matches Python: new_width = int(width * size_multiplier)
        let targetPixelSize = CGSize(
            width: currentPixelWidth * sizeMultiplier,
            height: currentPixelHeight * sizeMultiplier
        )
        
        print("[PasscodeTheme] Resizing from \(currentPixelWidth)×\(currentPixelHeight)px to \(targetPixelSize.width)×\(targetPixelSize.height)px (multiplier: \(sizeMultiplier))")
        
        // Perform the resize using UIGraphicsImageRenderer with scale 1.0 to work in pixels
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to work in actual pixels, not points
        
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }
    
    // Auto-detect size from ZIP file (like Nugget does)
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            
            // Check if any file ends with "_small"
            for entry in archive {
                if entry.path.hasSuffix("_small") {
                    return .small
                }
            }
            
            // Check if any file ends with "_big"
            for entry in archive {
                if entry.path.hasSuffix("_big") {
                    return .big
                }
            }
            
            // No size indicator found
            return .unknown
        } catch {
            print("[PasscodeTheme] Failed to detect size from ZIP: \(error.localizedDescription)")
            return .unknown
        }
    }
    
    // Extract images from Telephony-X subfolder to theme root folder
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        
        // Look for Telephony-X subfolder (Telephony-8, Telephony-9, Telephony-10, etc.)
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else {
            print("[PasscodeTheme] Cannot read theme folder contents")
            return
        }
        
        // Find the Telephony-X subfolder
        guard let telephonyFolder = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else {
            print("[PasscodeTheme] No Telephony subfolder found, images may be at root level")
            return
        }
        
        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        print("[PasscodeTheme] Found Telephony subfolder: \(telephonyFolder)")
        
        // Get all image files from the Telephony subfolder
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else {
            print("[PasscodeTheme] Cannot read Telephony subfolder contents")
            return
        }
        
        // Move each image file to the theme root folder
        var movedCount = 0
        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let sourceURL = telephonyFolderURL.appendingPathComponent(filename)
            let destURL = themeFolder.appendingPathComponent(filename)
            
            do {
                try fm.moveItem(at: sourceURL, to: destURL)
                movedCount += 1
            } catch {
                print("[PasscodeTheme] Failed to move \(filename): \(error.localizedDescription)")
            }
        }
        
        print("[PasscodeTheme] Moved \(movedCount) images from \(telephonyFolder) to theme root")
        
        // Clean up the now-empty Telephony subfolder
        try? fm.removeItem(at: telephonyFolderURL)
    }
    
    // Import a default passcode ZIP file
    // ZIP contains Telephony-8/9/10 folder with images like "other-2-A B C--white.png"
    // Auto-detects telephony version and language code from the ZIP contents
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. Access the security-scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 2. Copy to temp
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFileURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            throw PasscodeThemeError.accessDenied
        }
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        
        // 3. Prepare target theme folder
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        // 4. Auto-detect size
        let detectedSize = detectSizeFromZIP(at: tempFileURL)
        
        // 5. Unzip
        do {
            try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
        } catch {
            try? FileManager.default.removeItem(at: themeFolder)
            throw PasscodeThemeError.invalidFormat
        }
        
        // 6. Find Telephony-X folder and auto-set global telephony version
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for folderName in contents {
                // Match Telephony-8, Telephony-9, Telephony-10 or TelephonyUI-8, etc.
                if folderName.contains("Telephony") {
                    if folderName.contains("10") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony10 }
                    } else if folderName.contains("9") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony9 }
                    } else if folderName.contains("8") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony8 }
                    }
                    break
                }
            }
        }
        
        // 7. Extract images from Telephony subfolder and detect language code
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        // 8. Detect language code from extracted image filenames
        if let extractedFiles = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for filename in extractedFiles {
                let ext = (filename as NSString).pathExtension.lowercased()
                guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
                
                // Extract language code from filename like "other-2-A B C--white.png"
                if let firstHyphen = filename.firstIndex(of: "-") {
                    let prefix = String(filename[filename.startIndex..<firstHyphen])
                    if !prefix.isEmpty {
                        // Try to match to a known PrefixLanguage
                        if let knownPrefix = PasscodeTheme.PrefixLanguage(rawValue: prefix) {
                            await MainActor.run { themeStore.globalCustomPrefix = knownPrefix }
                        } else {
                            // Use "other" for unknown language codes
                            await MainActor.run { themeStore.globalCustomPrefix = .other }
                        }
                        break
                    }
                }
            }
        }
        
        // 9. Add theme to store
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // Apply theme using BookRestore exploit
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: ((String) -> Void)? = nil) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        // Use global settings from store
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        
        // Process all image files
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        
        guard !processedFiles.isEmpty else {
            throw PasscodeThemeError.noImagesProcessed
        }
        
        // Create BookRestoreFile objects with global Telephony version
        var bookRestoreFiles: [BookRestoreFile] = []
        
        for (_, imageData, targetFilename) in processedFiles {
            // Use global Telephony version path
            let targetPath = "\(globalTelephony.cachePath)\(targetFilename)"
            
            // Use .custom file type to trigger zassetpath logic
            let file = BookRestoreFile.custom(targetPath: targetPath, contents: imageData)
            bookRestoreFiles.append(file)
        }
        
        print("[PasscodeTheme] Applying \(bookRestoreFiles.count) files to Passcode - \(globalTelephony.rawValue)")
        
        // Log to console for debugging
        if bookRestoreFiles.count > 0 {
            ApplyLogger.shared.log("[PasscodeTheme] Applying theme '\(theme.name)' with \(bookRestoreFiles.count) files to Passcode - \(globalTelephony.rawValue)")
        }
        
        // Apply using BookRestoreApplyTask
        try await BookRestoreApplyTask.applyFiles(bookRestoreFiles, store: store, onLogUpdate: onLogUpdate)
    }
}

// MARK: - Errors
enum PasscodeThemeError: LocalizedError {
    case accessDenied
    case noImagesFound
    case noImagesProcessed
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Unable to access the selected file"
        case .noImagesFound:
            return "No image files found in theme package"
        case .noImagesProcessed:
            return "No images could be processed from theme"
        case .invalidFormat:
            return "Invalid theme format"
        }
    }
}
