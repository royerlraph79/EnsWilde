import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - Apple Wallet View
struct AppleWalletView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showAddSheet = false
    @State private var showScanSheet = false
    @State private var showImportZIPSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isScanning = false
    
    var body: some View {
        Form {
            Section(header: Text(L("tool_apple_wallet"))) {
                Toggle(L("wallet_enable"), isOn: $walletStore.appleWalletEnabled)
            }

            Section(header: Text(L("section_wallet_cards"))) {
                if walletStore.cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(L("wallet_no_cards"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(Array(walletStore.cards.enumerated()), id: \.element.id) { index, card in
                        NavigationLink(destination: AppleWalletCardDetailView(card: card, walletStore: walletStore)) {
                            WalletCardPreview(card: card, index: index, total: walletStore.cards.count, walletStore: walletStore)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(header: Text(L("section_add_card"))) {
                Button(L("wallet_scan_card")) {
                    showScanSheet = true
                }

                Button(L("wallet_manual_input")) {
                    showAddSheet = true
                }
                
                Button(L("wallet_import_default_zip")) {
                    showImportZIPSheet = true
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("wallet_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            ManualAddCardSheet(walletStore: walletStore)
        }
        .sheet(isPresented: $showScanSheet) {
            ScanCardIDSheet(walletStore: walletStore, isPresented: $showScanSheet)
        }
        .sheet(isPresented: $showImportZIPSheet) {
            ImportDefaultCardSheet(walletStore: walletStore)
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Wallet Card Preview
struct WalletCardPreview: View {
    let card: AppleWalletCard
    let index: Int
    let total: Int
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        ZStack {
            if let imageData = card.backgroundImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1.586, contentMode: .fill)
                    .frame(height: 200)
                    .cornerRadius(16)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x667eea), Color(hex: 0x764ba2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 200)
            }
            
            VStack {
                HStack {
                    Spacer()
                    if card.enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(card.id.prefix(16) + "...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(height: 200)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .offset(y: CGFloat(index) * -8)
        .contextMenu {
            Button {
                showEditSheet = true
            } label: {
                Label(L("alert_edit"), systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(L("alert_delete"), systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditCardSheet(card: card, walletStore: walletStore)
        }
        .alert(L("alert_delete_card"), isPresented: $showDeleteAlert) {
            Button(L("alert_cancel"), role: .cancel) {}
            Button(L("alert_delete"), role: .destructive) {
                walletStore.deleteCard(card)
            }
        } message: {
            Text(L("alert_delete_card_confirm").replacingOccurrences(of: "{cardName}", with: "\(card.name)?"))
        }
    }
}

// MARK: - Manual Add Card Sheet
struct ManualAddCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @State private var cardID = ""
    @State private var cardName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_card_information"))) {
                    TextField(L("wallet_card_id"), text: $cardID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField(L("wallet_card_name"), text: $cardName)
                }
            }
            .navigationTitle(L("wallet_add_manually"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_add")) {
                        let card = AppleWalletCard(id: cardID.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   name: cardName.isEmpty ? "Card \(cardID.prefix(8))" : cardName)
                        walletStore.addCard(card)
                        dismiss()
                    }
                    .disabled(cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Scan Card ID Sheet
struct ScanCardIDSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @Binding var isPresented: Bool
    @State private var isScanning = false
    @State private var scanStatus = L("wallet_scan_ready")
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("wallet_scan_card"))) {
                    VStack(spacing: 20) {
                        // Scanning Animation
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                                .frame(width: 150, height: 150)

                            if isScanning {
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 150, height: 150)
                                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                            }

                            Image(systemName: isScanning ? "wave.3.right.circle.fill" : "creditcard.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(isScanning ? .blue : .secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Text(scanStatus)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        if isScanning {
                            Text(String(format: "%.0f / 300 seconds", elapsedTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if isScanning {
                            Text(L("wallet_scan_instruction"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 20)
                }

                Section(header: Text(L("section_actions"))) {
                    if isScanning {
                        Button(L("wallet_scan_cancel")) {
                            stopScanning()
                            dismiss()
                        }
                    } else {
                        Button(L("wallet_scan_start")) {
                            startScanning()
                        }
                    }
                }
            }
            .navigationTitle(L("wallet_scan_card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_close")) {
                        stopScanning()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startScanning() {
        isScanning = true
        elapsedTime = 0
        scanStatus = "Scanning... Open Apple Wallet now"
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
        
        Task {
            do {
                let cardID = try await scanOneWalletCardID(timeout: 300) // 5 minutes
                await MainActor.run {
                    stopScanning()
                    let newCard = AppleWalletCard(id: cardID, name: "Card \(cardID.prefix(8))")
                    walletStore.addCard(newCard)
                    scanStatus = "✓ Successfully scanned card ID!"
                    
                    // Auto dismiss after 1.5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    stopScanning()
                    scanStatus = "✗ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func stopScanning() {
        isScanning = false
        timer?.invalidate()
        timer = nil
        JITEnableContext.shared.stopSyslogRelay()
    }
}

// MARK: - Edit Card Sheet
struct EditCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var card: AppleWalletCard
    @ObservedObject var walletStore: AppleWalletStore
    @State private var cardName: String
    
    init(card: AppleWalletCard, walletStore: AppleWalletStore) {
        self._card = State(initialValue: card)
        self.walletStore = walletStore
        self._cardName = State(initialValue: card.name)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_card_information"))) {
                    // Card ID is read-only
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("wallet_card_id_readonly"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.id)
                            .font(.system(.body, design: .monospaced))
                    }
                    TextField(L("wallet_card_name"), text: $cardName)
                }
            }
            .navigationTitle(L("edit_card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_save")) {
                        var updatedCard = card
                        updatedCard.name = cardName.isEmpty ? "Card \(card.id.prefix(8))" : cardName
                        walletStore.updateCard(updatedCard)
                        dismiss()
                    }
                    .disabled(cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Card Detail View
struct AppleWalletCardDetailView: View {
    @State var card: AppleWalletCard
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showImagePicker = false
    @State private var selectedImageType: ImageType = .background
    @State private var showDeleteAlert = false
    @State private var showPassJSONImporter = false
    @State private var showImportErrorAlert = false
    @State private var importErrorMessage = ""
    @State private var primaryAccountSuffix: String = ""
    @State private var passJSONData: Data? = nil
    @Environment(\.dismiss) var dismiss
    
    enum ImageType {
        case background
    }
    
    /// Compute the pass.json file path for this card
    private var passJSONFileURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("WalletCards")
            .appendingPathComponent(card.id)
            .appendingPathComponent("pass.json")
    }
    
    var body: some View {
        Form {
            // Card Preview
            Section(header: Text(L("section_card_preview"))) {
                if let imageData = card.backgroundImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1.586, contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x667eea), Color(hex: 0x764ba2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(1.586, contentMode: .fit)
                        .overlay(
                            Text(L("wallet_no_image"))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
            }

            // Card Info
            Section(header: Text(L("section_card_information"))) {
                TextField(L("wallet_card_name"), text: $card.name)
                    .onChange(of: card.name) { _ in walletStore.updateCard(card) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("wallet_card_id"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.id)
                        .font(.system(.body, design: .monospaced))
                }

                Toggle(L("wallet_enable_card"), isOn: $card.enabled)
                    .onChange(of: card.enabled) { _ in walletStore.updateCard(card) }
            }

            // Image Resolution
            Section(header: Text(L("section_image_resolution"))) {
                Picker("Resolution", selection: $card.useRetina) {
                    Text(L("wallet_resolution_2x")).tag(false)
                    Text(L("wallet_resolution_3x")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: card.useRetina) { _ in walletStore.updateCard(card) }
            }

            // Images
            Section(header: Text(L("section_card_images"))) {
                ImagePickerButton(
                    title: "Background Image",
                    subtitle: card.useRetina ? "cardBackgroundCombined@3x.png" : "cardBackgroundCombined@2x.png",
                    hasImage: card.backgroundImageData != nil
                ) {
                    selectedImageType = .background
                    showImagePicker = true
                }
            }
            
            // Card Display Number Section
            Section(header: Text(L("wallet_card_display_number"))) {
                if passJSONData != nil {
                    // Show imported status
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.green)
                        Text(L("wallet_card_data_imported"))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    // primaryAccountSuffix editing
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("wallet_display_number_label"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L("wallet_display_number_placeholder"), text: $primaryAccountSuffix)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .onChange(of: primaryAccountSuffix) { newValue in
                                updatePrimaryAccountSuffixOnDisk(newValue)
                            }
                    }
                    
                    // Replace button
                    Button {
                        showPassJSONImporter = true
                    } label: {
                        Label(L("wallet_replace_card_data"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    // Delete button
                    Button(role: .destructive) {
                        deletePassJSON()
                    } label: {
                        Label(L("wallet_delete_card_data"), systemImage: "trash")
                    }
                } else {
                    // Import button
                    Button {
                        showPassJSONImporter = true
                    } label: {
                        Label(L("wallet_import_card_data"), systemImage: "doc.badge.plus")
                    }
                }
            }

            // Delete Card
            Section(header: Text(L("section_danger_zone"))) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Text(L("alert_delete_card"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPassJSONFromDisk()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(imageData: bindingForImageType(selectedImageType), useRetina: card.useRetina)
        }
        .fileImporter(
            isPresented: $showPassJSONImporter,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            handlePassJSONImport(result)
        }
        .alert(L("alert_delete_card"), isPresented: $showDeleteAlert) {
            Button(L("alert_cancel"), role: .cancel) {}
            Button(L("alert_delete"), role: .destructive) {
                walletStore.deleteCard(card)
                dismiss()
            }
        } message: {
            Text(L("alert_delete_card_confirm").replacingOccurrences(of: "{cardName}", with: "\(card.name)?"))
        }
        .alert(L("alert_error"), isPresented: $showImportErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(importErrorMessage)
        }
    }
    
    private func bindingForImageType(_ type: ImageType) -> Binding<Data?> {
        Binding(
            get: {
                switch type {
                case .background: return card.backgroundImageData
                }
            },
            set: { newValue in
                switch type {
                case .background: card.backgroundImageData = newValue
                }
                walletStore.updateCard(card)
            }
        )
    }
    
    // MARK: - pass.json Operations
    
    /// Load pass.json data from disk into @State
    private func loadPassJSONFromDisk() {
        let fileURL = passJSONFileURL
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            passJSONData = data
            // Extract primaryAccountSuffix
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                primaryAccountSuffix = json["primaryAccountSuffix"] as? String ?? ""
            }
        } else {
            passJSONData = nil
            primaryAccountSuffix = ""
        }
    }
    
    /// Save pass.json data to disk
    private func savePassJSONToDisk(_ data: Data) throws {
        let folderURL = passJSONFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try data.write(to: passJSONFileURL)
    }
    
    /// Delete pass.json from disk and clear state
    private func deletePassJSON() {
        try? FileManager.default.removeItem(at: passJSONFileURL)
        passJSONData = nil
        primaryAccountSuffix = ""
    }
    
    /// Update primaryAccountSuffix in the on-disk pass.json
    private func updatePrimaryAccountSuffixOnDisk(_ newValue: String) {
        guard let currentData = passJSONData,
              var json = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            return
        }
        json["primaryAccountSuffix"] = newValue
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: passJSONFileURL)
            passJSONData = updatedData
        }
    }
    
    /// Handle file importer result
    private func handlePassJSONImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            
            let importedData: Data
            do {
                importedData = try Data(contentsOf: url)
            } catch {
                importErrorMessage = "Failed to read file: \(error.localizedDescription)"
                showImportErrorAlert = true
                return
            }
            
            // Validate it's valid JSON
            guard let json = try? JSONSerialization.jsonObject(with: importedData) as? [String: Any] else {
                importErrorMessage = "Invalid JSON format. The file must contain a JSON object."
                showImportErrorAlert = true
                return
            }
            
            // Save to disk
            do {
                try savePassJSONToDisk(importedData)
            } catch {
                importErrorMessage = "Failed to save pass.json: \(error.localizedDescription)"
                showImportErrorAlert = true
                return
            }
            
            // Update @State — this triggers the UI to show the editing section
            passJSONData = importedData
            primaryAccountSuffix = json["primaryAccountSuffix"] as? String ?? ""
            
        case .failure(let error):
            importErrorMessage = "File import error: \(error.localizedDescription)"
            showImportErrorAlert = true
        }
    }
}

// MARK: - Image Picker Button
struct ImagePickerButton: View {
    let title: String
    let subtitle: String
    let hasImage: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasImage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 20))
                }
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    let useRetina: Bool  // true = @3x, false = @2x
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, useRetina: useRetina)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        let useRetina: Bool
        
        init(_ parent: ImagePicker, useRetina: Bool) {
            self.parent = parent
            self.useRetina = useRetina
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            
            provider.loadObject(ofClass: UIImage.self) { image, error in
                guard let image = image as? UIImage else { return }
                
                // Resize to Apple Wallet dimensions based on resolution
                // Apple Wallet card background sizes:
                // @3x (Retina): 2304x1452
                // @2x (Standard): 1536x969 (user-specified default)
                let targetSize: CGSize
                if self.useRetina {
                    targetSize = CGSize(width: 2304, height: 1452)
                } else {
                    targetSize = CGSize(width: 1536, height: 969)
                }
                
                let resizedImage = self.resizeImage(image, targetSize: targetSize)
                
                DispatchQueue.main.async {
                    self.parent.imageData = resizedImage.pngData()
                }
            }
        }
        
        private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio = targetSize.width / size.width
            let heightRatio = targetSize.height / size.height
            let ratio = min(widthRatio, heightRatio)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
}

// MARK: - Wallet Card ID Scanner
private enum WalletIDScanError: Error, LocalizedError {
    case timedOut
    case unknownError

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Hết thời gian chờ (Timeout). Vui lòng thêm thẻ vào Wallet và thử lại."
        case .unknownError:
            return "Lỗi không xác định khi quét ID thẻ."
        }
    }
}

// MARK: - 2. Hàm trích xuất ID từ dòng log (Regex Logic)

private func extractWalletCardID(from line: String) -> String? {
    // Danh sách các mẫu Regex để bắt ID thẻ trong các trường hợp khác nhau của iOS
    let patterns = [
        // Mẫu 1: Khi PDCardFileManager ghi dữ liệu thẻ
        #"PDCardFileManager: writing card\s+([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#,
        // Mẫu 2: Khi PDPassLibrary ghi nhận pass mới
        #"PDPassLibrary: wrote pass\s+([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#,
        // Mẫu 3: Khi hệ thống thực hiện VerificationCheck
        #"VerificationCheck\.([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#
    ]

    for pattern in patterns {
        // Tạo đối tượng Regex an toàn
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        
        let nsRange = NSRange(line.startIndex..., in: line)
        
        // Tìm match đầu tiên trong dòng log
        if let match = regex.firstMatch(in: line, options: [], range: nsRange) {
            // Lấy nhóm capture thứ 1 (ID thẻ)
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
    }
    return nil
}

func scanOneWalletCardID(timeout: TimeInterval = 300) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        var finished = false
        
        JITEnableContext.shared.startSyslogRelay { line in
            guard !finished else { return }
            guard let line else { return }
            
            // Filter for passd logs only
            guard line.localizedCaseInsensitiveContains("passd") else { return }
            
            if let cardID = extractWalletCardID(from: line) {
                finished = true
                JITEnableContext.shared.stopSyslogRelay()
                continuation.resume(returning: cardID)
            }
        } onError: { error in
            guard !finished else { return }
            finished = true
            JITEnableContext.shared.stopSyslogRelay()
            continuation.resume(throwing: error ?? WalletIDScanError.unknownError)
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard !finished else { return }
            finished = true
            JITEnableContext.shared.stopSyslogRelay()
            continuation.resume(throwing: WalletIDScanError.timedOut)
        }
    }
}

// MARK: - Import Default Card Sheet (ZIP)
struct ImportDefaultCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(L("wallet_select_zip")) {
                        showFilePicker = true
                    }
                }
                
                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(L("wallet_importing"))
                        }
                    }
                }
                
                if let result = importResult {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(L("wallet_import_default_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.zip, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importZIP(url: url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert(L("alert_error"), isPresented: .constant(errorMessage != nil)) {
                Button(L("alert_ok")) { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func importZIP(url: URL) {
        isImporting = true
        importResult = nil
        
        Task {
            do {
                let count = try await performZIPImport(url: url)
                await MainActor.run {
                    isImporting = false
                    importResult = "Imported \(count) card(s)"
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performZIPImport(url: URL) async throws -> Int {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Copy to temp first
        let tempZIP = tempDir.appendingPathComponent("import.zip")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: tempZIP)
        
        // Unzip
        let extractDir = tempDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: tempZIP, to: extractDir)
        
        defer { try? fm.removeItem(at: tempDir) }
        
        // Find .pkpass folders (could be at root or one level deep)
        var pkpassFolders: [(id: String, url: URL)] = []
        
        func scanForPkpass(at dirURL: URL) {
            guard let items = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return }
            for item in items {
                let itemURL = dirURL.appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
                
                if isDir.boolValue && item.hasSuffix(".pkpass") {
                    // Extract card ID: remove ".pkpass" suffix
                    let cardID = String(item.dropLast(".pkpass".count))
                    if !cardID.isEmpty {
                        pkpassFolders.append((id: cardID, url: itemURL))
                    }
                }
            }
        }
        
        // Scan root level
        scanForPkpass(at: extractDir)
        
        // If none found at root, scan one level deeper (in case ZIP has a wrapper folder)
        if pkpassFolders.isEmpty {
            if let topItems = try? fm.contentsOfDirectory(atPath: extractDir.path) {
                for item in topItems {
                    let subDir = extractDir.appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: subDir.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        scanForPkpass(at: subDir)
                    }
                }
            }
        }
        
        guard !pkpassFolders.isEmpty else {
            throw NSError(domain: "ImportDefaultCard", code: 1, userInfo: [NSLocalizedDescriptionKey: "No .pkpass folders found in ZIP"])
        }
        
        var importedCount = 0
        
        for folder in pkpassFolders {
            let cardID = folder.id
            let folderURL = folder.url
            
            // Create card in wallet store (skip if already exists)
            let cardName = "Card \(String(cardID.prefix(8)))..."
            
            await MainActor.run {
                if !walletStore.cards.contains(where: { $0.id == cardID }) {
                    let newCard = AppleWalletCard(id: cardID, name: cardName)
                    walletStore.addCard(newCard)
                }
            }
            
            // Copy files from the .pkpass folder to the card's Documents folder
            let cardFolder = URL.documentsDirectory
                .appendingPathComponent("WalletCards")
                .appendingPathComponent(cardID)
            try fm.createDirectory(at: cardFolder, withIntermediateDirectories: true)
            
            guard let files = try? fm.contentsOfDirectory(atPath: folderURL.path) else { continue }
            
            for filename in files {
                let srcFile = folderURL.appendingPathComponent(filename)
                var isFileDir: ObjCBool = false
                fm.fileExists(atPath: srcFile.path, isDirectory: &isFileDir)
                guard !isFileDir.boolValue else { continue }
                
                // Determine destination filename
                let destFile = cardFolder.appendingPathComponent(filename)
                
                // Remove existing file if needed
                try? fm.removeItem(at: destFile)
                try fm.copyItem(at: srcFile, to: destFile)
            }
            
            importedCount += 1
        }
        
        return importedCount
    }
}
