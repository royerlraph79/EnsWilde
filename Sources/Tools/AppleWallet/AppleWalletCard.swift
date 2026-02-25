import Foundation
import SwiftUI

// MARK: - Apple Wallet Card Model
struct AppleWalletCard: Identifiable, Codable {
    let id: String  // Card ID from passd
    var name: String
    var enabled: Bool
    var useRetina: Bool  // true = @3x, false = @2x
    
    // Images are now stored in Documents/WalletCards/{cardID}/ folder
    // We don't store Data directly in the struct anymore
    var backgroundImageData: Data? {
        get { loadImageFromDocuments(fileName: cardBackgroundFileName) }
        set { saveImageToDocuments(data: newValue, fileName: cardBackgroundFileName) }
    }
    
    var frontFaceImageData: Data? {
        get { loadImageFromDocuments(fileName: "FrontFace") }
        set { saveImageToDocuments(data: newValue, fileName: "FrontFace") }
    }
    
    var placeHolderImageData: Data? {
        get { loadImageFromDocuments(fileName: "PlaceHolder") }
        set { saveImageToDocuments(data: newValue, fileName: "PlaceHolder") }
    }
    
    var previewImageData: Data? {
        get { loadImageFromDocuments(fileName: "Preview") }
        set { saveImageToDocuments(data: newValue, fileName: "Preview") }
    }
    
    var cardBackgroundFileName: String {
        useRetina ? "cardBackgroundCombined@3x.png" : "cardBackgroundCombined@2x.png"
    }
    
    // Get the card's folder path in Documents
    private var cardFolderURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("WalletCards")
            .appendingPathComponent(id)
    }
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.enabled = false
        self.useRetina = false
        
        // Create card folder in Documents
        createCardFolder()
        
        // Copy default images from Resources if not already present
        copyDefaultImagesFromResources()
    }
    
    // Create the card's folder structure in Documents
    private func createCardFolder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cardFolderURL.path) {
            try? fm.createDirectory(at: cardFolderURL, withIntermediateDirectories: true)
        }
    }
    
    // Copy default images from Resources to card folder
    private func copyDefaultImagesFromResources() {
        let defaultImages = ["FrontFace", "PlaceHolder", "Preview"]
        for imageName in defaultImages {
            let destURL = cardFolderURL.appendingPathComponent(imageName)
            // Only copy if doesn't exist
            if !FileManager.default.fileExists(atPath: destURL.path) {
                if let imageData = Self.loadResourceImage(named: imageName) {
                    try? imageData.write(to: destURL)
                }
            }
        }
    }
    
    // Load image from card's folder in Documents
    private func loadImageFromDocuments(fileName: String) -> Data? {
        let fileURL = cardFolderURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }
    
    // Save image to card's folder in Documents
    private mutating func saveImageToDocuments(data: Data?, fileName: String) {
        createCardFolder() // Ensure folder exists
        guard let data = data else {
            // If data is nil, remove the file
            let fileURL = cardFolderURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let fileURL = cardFolderURL.appendingPathComponent(fileName)
        try? data.write(to: fileURL)
    }
    
    // Load image from Resources bundle
    private static func loadResourceImage(named name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
    
    // MARK: - pass.json Support
    
    /// URL for the pass.json file stored in the card's folder
    var passJSONFileURL: URL {
        cardFolderURL.appendingPathComponent("pass.json")
    }
    
    /// Check if pass.json exists for this card
    var hasPassJSON: Bool {
        FileManager.default.fileExists(atPath: passJSONFileURL.path)
    }
    
    /// Load pass.json data from the card's folder
    func loadPassJSON() -> Data? {
        guard hasPassJSON else { return nil }
        return try? Data(contentsOf: passJSONFileURL)
    }
    
    /// Save pass.json data to the card's folder
    mutating func savePassJSON(_ data: Data?) {
        createCardFolder()
        guard let data = data else {
            try? FileManager.default.removeItem(at: passJSONFileURL)
            return
        }
        try? data.write(to: passJSONFileURL)
    }
    
    /// Read primaryAccountSuffix from pass.json
    func getPrimaryAccountSuffix() -> String? {
        guard let data = loadPassJSON(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["primaryAccountSuffix"] as? String
    }
    
    /// Update primaryAccountSuffix in pass.json and save
    mutating func setPrimaryAccountSuffix(_ value: String) {
        guard let data = loadPassJSON(),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        json["primaryAccountSuffix"] = value
        guard let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        savePassJSON(updatedData)
    }
    
    /// Delete pass.json from the card's folder
    mutating func deletePassJSON() {
        savePassJSON(nil)
    }
}

// MARK: - Apple Wallet Store
class AppleWalletStore: ObservableObject {
    @Published var cards: [AppleWalletCard] = []
    @AppStorage("AppleWalletEnabled") var appleWalletEnabled: Bool = false
    
    private let cardsFileURL: URL
    
    init() {
        cardsFileURL = URL.documentsDirectory.appendingPathComponent("AppleWalletCards.json")
        loadCards()
    }
    
    func loadCards() {
        guard FileManager.default.fileExists(atPath: cardsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: cardsFileURL)
            cards = try JSONDecoder().decode([AppleWalletCard].self, from: data)
        } catch {
            print("Failed to load wallet cards: \(error)")
        }
    }
    
    func saveCards() {
        do {
            let data = try JSONEncoder().encode(cards)
            try data.write(to: cardsFileURL, options: .atomic)
        } catch {
            print("Failed to save wallet cards: \(error)")
        }
    }
    
    func addCard(_ card: AppleWalletCard) {
        if !cards.contains(where: { $0.id == card.id }) {
            cards.append(card)
            saveCards()
        }
    }
    
    func updateCard(_ card: AppleWalletCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
            saveCards()
        }
    }
    
    func deleteCard(_ card: AppleWalletCard) {
        cards.removeAll { $0.id == card.id }
        saveCards()
        
        // Also delete the card's folder from Documents
        let cardFolderURL = URL.documentsDirectory
            .appendingPathComponent("WalletCards")
            .appendingPathComponent(card.id)
        try? FileManager.default.removeItem(at: cardFolderURL)
    }
    
    func enabledCards() -> [AppleWalletCard] {
        cards.filter { $0.enabled }
    }
}
