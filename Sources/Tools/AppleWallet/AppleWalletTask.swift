import Foundation

enum AppleWalletTask {
    
    /// Apply all enabled wallet cards in a single batch operation
    /// CRITICAL: Background images MUST be processed before cache files for proper rendering
    /// pass.json (if imported) is applied after card images
    static func run(store: ToolStore, walletStore: AppleWalletStore) async throws {
        // Get enabled cards
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else {
            throw ToolTaskError.generic("No enabled wallet cards to apply")
        }
        
        // Collect ALL files from all enabled cards in proper order
        var allFiles: [BookRestoreFile] = []
        
        for card in enabledCards {
            let cardBasePath = "/private/var/mobile/Library/Passes/Cards/\(card.id)"
            let cardPrefix = String(card.id.prefix(8))
            
            // CRITICAL ORDERING: Background image MUST come first!
            // Step 1: Add background image (.pkpass) first
            if let bgImageData = card.backgroundImageData {
                let bgFileName = card.cardBackgroundFileName
                let pkpassPath = "\(cardBasePath).pkpass/\(bgFileName)"
                let uniqueMediaName = "wallet_\(cardPrefix)_\(bgFileName)"
                allFiles.append(.walletImage(targetPath: pkpassPath, contents: bgImageData, mediaFileName: uniqueMediaName))
            }
            
            // Step 2: Then add cache files (FrontFace, PlaceHolder, Preview)
            if let frontFaceData = card.frontFaceImageData {
                let frontFacePath = "\(cardBasePath).cache/FrontFace"
                let uniqueMediaName = "wallet_\(cardPrefix)_FrontFace"
                allFiles.append(.walletImage(targetPath: frontFacePath, contents: frontFaceData, mediaFileName: uniqueMediaName))
            }
            
            if let placeHolderData = card.placeHolderImageData {
                let placeHolderPath = "\(cardBasePath).cache/PlaceHolder"
                let uniqueMediaName = "wallet_\(cardPrefix)_PlaceHolder"
                allFiles.append(.walletImage(targetPath: placeHolderPath, contents: placeHolderData, mediaFileName: uniqueMediaName))
            }
            
            if let previewData = card.previewImageData {
                let previewPath = "\(cardBasePath).cache/Preview"
                let uniqueMediaName = "wallet_\(cardPrefix)_Preview"
                allFiles.append(.walletImage(targetPath: previewPath, contents: previewData, mediaFileName: uniqueMediaName))
            }
            
            // Step 3: Add pass.json after card images (if imported)
            if let passJSONData = card.loadPassJSON() {
                let passJSONPath = "\(cardBasePath).pkpass/pass.json"
                let uniqueMediaName = "wallet_\(cardPrefix)_pass.json"
                allFiles.append(.walletImage(targetPath: passJSONPath, contents: passJSONData, mediaFileName: uniqueMediaName))
            }
        }
        
        guard !allFiles.isEmpty else {
            throw ToolTaskError.generic("No wallet files to apply")
        }
        
        // Apply all files in a single batch using unified BookRestore task
        print("[AppleWallet] Applying \(allFiles.count) file(s) from \(enabledCards.count) card(s) in batch mode...")
        try await BookRestoreApplyTask.applyFiles(allFiles, store: store)
        print("[AppleWallet] Files applied successfully.")
        
        // Note: BookRestoreApplyTask already opens Books app at the end.
        // User should open Wallet app to see the changes applied to cards.
    }
}
