//
//  BookRestoreFile.swift
//  EnsWilde
//
//  Created by YangJiii on 2/1/26.
//

//
//  BookRestoreFile.swift
//  EnsWilde
//
//  Unified model for files to be applied via BookRestore method
//

import Foundation

/// Represents a single file to be applied via the BookRestore (Books app) exploit
struct BookRestoreFile {
    /// The target path where this file should be written on the device
    let targetPath: String
    
    /// The type of file being applied
    let fileType: FileType
    
    /// Optional: The local file name in Documents directory (for serving via HTTP)
    /// If nil, content will be pushed directly via AFC
    let localFileName: String?
    
    /// File contents (if not served via HTTP)
    let contents: Data?
    
    enum FileType {
        /// Sound file for DisableSound feature (uses audio URL in ZBLDOWNLOADINFO)
        case sound
        
        /// MobileGestalt plist (uses .zassetpath approach in ZBLDOWNLOADINFO)
        case mobileGestalt
        
        /// Custom file for zPatch Custom feature (uses .zassetpath approach)
        case custom
        
        /// Apple Wallet image (uses media approach in ZBLDOWNLOADINFO)
        case walletImage
        
        /// Feature Flags plist (uses .zassetpath approach in ZBLDOWNLOADINFO)
        case featureFlags
        
        /// Placeholder file for folder creation (uses .zassetpath approach)
        case placeholder
    }
    
    /// Create a sound file entry
    static func sound(targetPath: String, localFileName: String) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .sound,
            localFileName: localFileName,
            contents: nil
        )
    }
    
    /// Create a MobileGestalt file entry
    static func mobileGestalt(targetPath: String, contents: Data) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .mobileGestalt,
            localFileName: nil,
            contents: contents
        )
    }
    
    /// Create a custom file entry (for zPatch Custom)
    static func custom(targetPath: String, contents: Data) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .custom,
            localFileName: nil,
            contents: contents
        )
    }
    
    /// Create a wallet image file entry (for Apple Wallet)
    static func walletImage(targetPath: String, contents: Data, mediaFileName: String) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .walletImage,
            localFileName: mediaFileName,
            contents: contents
        )
    }
    
    /// Create a Feature Flags plist file entry
    static func featureFlags(targetPath: String, contents: Data) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .featureFlags,
            localFileName: nil,
            contents: contents
        )
    }
    
    /// Create a placeholder file entry (for folder creation)
    static func placeholder(targetPath: String) -> BookRestoreFile {
        return BookRestoreFile(
            targetPath: targetPath,
            fileType: .placeholder,
            localFileName: nil,
            contents: Data() // Empty data
        )
    }
}
