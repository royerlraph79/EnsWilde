import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Settings View (System Status, Pairing, Language, Color)
struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showPairingFileImporter = false
    @State private var showDDIDownloadConfirm = false
    @State private var isDDIDownloading = false
    @State private var ddiDownloadProgress: Double = 0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: String = ""
    @State private var showDDIResult = false
    @State private var ddiFilesExist = false
    @State private var isMountingDDI = false
    var heartbeatRunning: Bool
    var ddiMounted: Bool

    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"),
        ("Mauve", "#ca9ee6"),
        ("Red", "#ff0000"),
        ("Green", "#a6d189"),
        ("Blue", "#8caaee"),
    ]

    @State private var copiedPath: String?
    
    var body: some View {
        Form {
            systemStatusSection
            pairingSection
            ddiSection
            languageSection
            colorSection
            tutorialSection
            appInfoSection
        }
        .headerProminence(.increased)
        .navigationTitle(L("nav_settings"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task {
                    await languageManager.fetchAvailableLanguages()
                }
            }
            checkDDIFilesExist()
        }
        .confirmationDialog(L("button_download_ddi"), isPresented: $showDDIDownloadConfirm) {
            Button(L("button_download_ddi")) {
                downloadDDIFiles()
            }
            Button(L("alert_cancel"), role: .cancel) {}
        } message: {
            Text(L("ddi_download_confirm"))
        }
        .alert(ddiResultMessage, isPresented: $showDDIResult) {
            Button("OK") {}
        }
    }

    // MARK: - System Status Section
    @ViewBuilder
    private var systemStatusSection: some View {
        Section(header: Text(L("system_status"))) {
            statusRow(
                title: L("status_pairing_file"),
                subtitle: pairingFile != nil ? L("status_pairing_loaded") : L("status_pairing_missing"),
                ok: pairingFile != nil
            )
            statusRow(
                title: L("status_heartbeat"),
                subtitle: heartbeatRunning ? L("status_heartbeat_running") : L("status_heartbeat_stopped"),
                ok: heartbeatRunning
            )
            statusRow(
                title: L("status_ddi"),
                subtitle: ddiMounted ? L("status_ddi_mounted") : L("status_ddi_unmounted"),
                ok: ddiMounted
            )
        }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - DDI Section
    @ViewBuilder
    private var ddiSection: some View {
        Section(header: Text(L("ddi_section_title"))) {
            // DDI files status
            statusRow(
                title: L("status_ddi"),
                subtitle: ddiFilesExist ? L("ddi_files_ready") : L("ddi_files_not_ready"),
                ok: ddiFilesExist
            )

            // Download DDI button
            if isDDIDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text(ddiStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: ddiDownloadProgress)
                        .progressViewStyle(.linear)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    showDDIDownloadConfirm = true
                } label: {
                    Label(L("button_download_ddi"), systemImage: "arrow.down.circle")
                }
            }

            // Mount personalized DDI button
            if ddiFilesExist && heartbeatRunning && !ddiMounted {
                Button {
                    mountPersonalizedDDI()
                } label: {
                    if isMountingDDI {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text(L("button_mount_personal_ddi"))
                        }
                    } else {
                        Label(L("button_mount_personal_ddi"), systemImage: "externaldrive.badge.plus")
                    }
                }
                .disabled(isMountingDDI)
            }
        }
    }

    // MARK: - DDI Helpers

    private static let ddiDownloadItems: [(name: String, relativePath: String, urlString: String)] = [
        (
            name: "Build Manifest",
            relativePath: "DDI/BuildManifest.plist",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist"
        ),
        (
            name: "Image",
            relativePath: "DDI/Image.dmg",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg"
        ),
        (
            name: "TrustCache",
            relativePath: "DDI/Image.dmg.trustcache",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"
        )
    ]

    private func checkDDIFilesExist() {
        let fm = FileManager.default
        ddiFilesExist = Self.ddiDownloadItems.allSatisfy { item in
            fm.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(item.relativePath).path)
        }
    }

    private func downloadDDIFiles() {
        isDDIDownloading = true
        ddiDownloadProgress = 0
        ddiStatusMessage = L("ddi_downloading")

        Task {
            do {
                let fm = FileManager.default
                let totalStages = Double(Self.ddiDownloadItems.count + 1)
                var completedStages = 0.0

                // Remove existing files
                for item in Self.ddiDownloadItems {
                    let fileURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
                    if fm.fileExists(atPath: fileURL.path) {
                        try fm.removeItem(at: fileURL)
                    }
                }
                completedStages += 1.0
                await MainActor.run {
                    ddiDownloadProgress = completedStages / totalStages
                }

                // Download each file
                for item in Self.ddiDownloadItems {
                    await MainActor.run {
                        ddiStatusMessage = "\(item.name)…"
                        ddiDownloadProgress = completedStages / totalStages
                    }
                    let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
                    guard let url = URL(string: item.urlString) else { continue }
                    let (tempLocalUrl, _) = try await URLSession.shared.download(from: url)
                    try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destinationURL.path) {
                        try fm.removeItem(at: destinationURL)
                    }
                    try fm.moveItem(at: tempLocalUrl, to: destinationURL)
                    completedStages += 1.0
                }

                await MainActor.run {
                    ddiDownloadProgress = 1.0
                    isDDIDownloading = false
                    checkDDIFilesExist()
                    ddiResultMessage = L("ddi_download_complete")
                    showDDIResult = true
                }
            } catch {
                await MainActor.run {
                    isDDIDownloading = false
                    ddiResultMessage = L("ddi_download_failed").replacingOccurrences(of: "{error}", with: error.localizedDescription)
                    showDDIResult = true
                }
            }
        }
    }

    private func mountPersonalizedDDI() {
        isMountingDDI = true

        DispatchQueue.global(qos: .userInitiated).async {
            let imagePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path
            let trustcachePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
            let manifestPath = URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path

            guard let context = JITEnableContext.shared else {
                DispatchQueue.main.async {
                    isMountingDDI = false
                    ddiResultMessage = L("ddi_mount_personal_failed").replacingOccurrences(of: "{error}", with: "Context not initialized")
                    showDDIResult = true
                }
                return
            }

            do {
                try context.mountPersonalDDI(withImagePath: imagePath, trustcachePath: trustcachePath, manifestPath: manifestPath)
                DispatchQueue.main.async {
                    isMountingDDI = false
                    ddiResultMessage = L("ddi_mount_personal_success")
                    showDDIResult = true
                }
            } catch {
                DispatchQueue.main.async {
                    isMountingDDI = false
                    ddiResultMessage = L("ddi_mount_personal_failed").replacingOccurrences(of: "{error}", with: error.localizedDescription)
                    showDDIResult = true
                }
            }
        }
    }

    // MARK: - Pairing Section
    @ViewBuilder
    private var pairingSection: some View {
        Section(header: Text(L("status_pairing_file"))) {
            if pairingFile != nil {
                Button(role: .destructive) {
                    pairingFile = nil
                    let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                    try? FileManager.default.removeItem(at: pairingPath)
                } label: {
                    Label(L("button_reset_pairing"), systemImage: "trash")
                }
            } else {
                Button {
                    showPairingFileImporter = true
                } label: {
                    Label(L("button_select_pairing"), systemImage: "doc.badge.plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [
                .propertyList,
                UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data
            ]
        ) { result in
            if case .success(let url) = result {
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    pairingFile = text
                    try? text.write(
                        to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            }
        }
    }

    // MARK: - Language Section
    @ViewBuilder
    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    // MARK: - Tutorial Section
    @ViewBuilder
    private var tutorialSection: some View {
        Section(header: Text(L("settings_tutorial"))) {
            NavigationLink {
                TutorialView()
            } label: {
                Label(L("tutorial_guide"), systemImage: "book.fill")
            }
            
            // Copy Passcode Path
            Button {
                let version = (UIDevice.current.systemVersion as NSString).floatValue
                let passcodePath = version >= 26.0
                    ? "file://a/var/mobile/Library/Caches/TelephonyUI-10/"
                    : "file://a/var/mobile/Library/Caches/TelephonyUI-9/"
                UIPasteboard.general.string = passcodePath
                copiedPath = "passcode"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedPath == "passcode" { copiedPath = nil }
                }
            } label: {
                HStack {
                    Label(L("tutorial_copy_passcode_path"), systemImage: "lock.rectangle")
                    Spacer()
                    if copiedPath == "passcode" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Copy Apple Wallet Path
            Button {
                UIPasteboard.general.string = "file://a/var/mobile/Library/Passes/Cards/"
                copiedPath = "wallet"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedPath == "wallet" { copiedPath = nil }
                }
            } label: {
                HStack {
                    Label(L("tutorial_copy_wallet_path"), systemImage: "wallet.pass")
                    Spacer()
                    if copiedPath == "wallet" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Color Section (at bottom)
    @ViewBuilder
    private var colorSection: some View {
        Section(header: Text(L("settings_accent_color"))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tintOptions, id: \.hex) { option in
                        colorOptionView(option: option)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    @ViewBuilder
    private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(isSelected ? 1 : 0)
                )
            Text(option.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: 60)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.15) : Color.clear)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                userTintColorHex = option.hex
                // Immediately update UIKit tint for tab bar icons
                let uiColor = UIColor(Color(hex: option.hex))
                UITabBar.appearance().tintColor = uiColor
                UINavigationBar.appearance().tintColor = uiColor
                for scene in UIApplication.shared.connectedScenes {
                    guard let windowScene = scene as? UIWindowScene else { continue }
                    for window in windowScene.windows {
                        window.tintColor = uiColor
                    }
                }
            }
        }
    }

    // MARK: - App Info Section
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    @ViewBuilder
    private var appInfoSection: some View {
        Section(header: Text(L("settings_app_info"))) {
            HStack {
                Label("EnsWilde", systemImage: "sparkles")
                Spacer()
                Text("v\(appVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("iOS", systemImage: "iphone")
                Spacer()
                Text(UIDevice.current.systemVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Device", systemImage: "apps.iphone")
                Spacer()
                Text(settingsDeviceModelName())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return UIDevice.current.name.isEmpty ? identifier : "\(UIDevice.current.name) (\(identifier))"
    }
}

// MARK: - About View (Feather-style)
struct AboutView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    private let contactURL = URL(string: "https://x.com/duongduong0908")!

    var body: some View {
        Form {
            donateSection
            feedbackSection
            creditsSection
            translatorsSection
        }
        .headerProminence(.increased)
        .navigationTitle(L("nav_about"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task { await languageManager.fetchAvailableLanguages() }
            }
        }
    }

    // MARK: - Donate (Feather-style)
    @ViewBuilder
    private var donateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity)

                Text("Thank you for using EnsWilde! This is a passion project dedicated to providing the best experience for you. Your support is my biggest motivation to keep improving it every day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("If you enjoy the app, please consider buying me a coffee ☕️ to fuel my late-night coding sessions. Every contribution is greatly appreciated!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: "https://ko-fi.com/yangjiii") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("settings_donate"))
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppTheme.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Feedback & Links (Feather-style)
    @ViewBuilder
    private var feedbackSection: some View {
        Section {
            Button(action: {
                if let url = URL(string: "https://github.com/YangJiiii/EnsWilde") {
                    UIApplication.shared.open(url)
                }
            }) {
                Label(L("settings_guide"), systemImage: "safari")
            }
            Button(action: { UIApplication.shared.open(contactURL) }) {
                Label(L("settings_contact"), systemImage: "paperplane.fill")
            }
        }
    }

    // MARK: - Credits (Feather-style)
    @ViewBuilder
    private var creditsSection: some View {
        Section(header: Text(L("settings_thanks_to"))) {
            creditRow(name: "Carrot1211", desc: "For cheering me on and supporting me during development.")
            creditRow(name: "@khanhduytran0", desc: "is based on SparseBox.")
            creditRow(name: "@SideStore team", desc: "idevice and C bindings from StikDebug.")
            creditRow(name: "@JJTech0130", desc: "SparseRestore and backup exploit.")
            creditRow(name: "@hanakim3945", desc: "bl_sbx exploit files and writeup.")
            creditRow(name: "@Lakr233", desc: "BBackupp.")
            creditRow(name: "@libimobiledevice", desc: L("settings_thanks_libimobile"))
            creditRow(name: "@PoomSmart", desc: "MobileGestalt dump.")
            creditRow(name: "@paragonarsi", desc: "Apple Wallet Get.")
            creditRow(name: "@iTechExpert21", desc: "Hide Dynamic Island.")
        }
    }

    // MARK: - Translators (Feather-style)
    @ViewBuilder
    private var translatorsSection: some View {
        Section(header: Text(L("settings_translators"))) {
            ForEach(languageManager.availableLanguages.filter { $0.translator != nil && !($0.translator?.isEmpty ?? true) }) { langInfo in
                creditRow(name: langInfo.translator ?? "", desc: "\(langInfo.nativeName) (\(langInfo.name)) translation")
            }
        }
    }

    // MARK: - Credit Row (Feather-style)
    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Components Helper
struct ThanksRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tutorial Onboarding View
struct TutorialView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var copiedPath: String?
    
    private var steps: [(icon: String, title: String, description: String)] {[
        ("doc.on.doc", L("tutorial_step_1_title"), L("tutorial_step_1_desc")),
        ("gear", L("tutorial_step_2_title"), L("tutorial_step_2_desc")),
        ("hand.tap", L("tutorial_step_3_title"), L("tutorial_step_3_desc")),
        ("airplayaudio", L("tutorial_step_4_title"), L("tutorial_step_4_desc")),
        ("archivebox", L("tutorial_step_5_title"), L("tutorial_step_5_desc"))
    ]}
    
    // Total pages = steps + 1 copy-path page
    private var totalPages: Int { steps.count + 1 }
    private var isLastStep: Bool { currentStep == totalPages - 1 }
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentStep) {
                // Step pages
                ForEach(0..<steps.count, id: \.self) { index in
                    stepPage(index: index)
                        .tag(index)
                }
                
                // Final copy-path page
                copyPathPage
                    .tag(steps.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Bottom controls
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(index == currentStep ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentStep)
                    }
                }
                .padding(.bottom, 4)
                
                // Buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep -= 1
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text(L("tutorial_back"))
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    
                    Button {
                        if isLastStep {
                            dismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    } label: {
                        HStack {
                            Text(isLastStep ? L("tutorial_done") : L("tutorial_next"))
                            if !isLastStep {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(L("tutorial_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Step Page
    @ViewBuilder
    private func stepPage(index: Int) -> some View {
        let step = steps[index]
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: step.icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .transition(.scale.combined(with: .opacity))
            
            // Step badge
                                Text(L("tutorial_step_of").replacingOccurrences(of: "{current}", with: "\(index + 1)").replacingOccurrences(of: "{total}", with: "\(steps.count)"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentColor, in: Capsule())
            
            // Title
            Text(step.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Description
            Text(step.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Copy Path Page
    @ViewBuilder
    private var copyPathPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.green)
            }
            
            Text(L("tutorial_copy_paths"))
                .font(.title2)
                .fontWeight(.bold)
            
            Text(L("tutorial_copy_paths_desc"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 12) {
                // Passcode Path
                let version = (UIDevice.current.systemVersion as NSString).floatValue
                let passcodePath = version >= 26.0
                    ? "file://a/var/mobile/Library/Caches/TelephonyUI-10/"
                    : "file://a/var/mobile/Library/Caches/TelephonyUI-9/"
                copyPathButton(
                    label: "Passcode Theme",
                    icon: "lock.rectangle",
                    path: passcodePath,
                    identifier: "passcode"
                )
                
                // Apple Wallet Path
                copyPathButton(
                    label: "Apple Wallet",
                    icon: "wallet.pass",
                    path: "file://a/var/mobile/Library/Passes/Cards/",
                    identifier: "wallet"
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private func copyPathButton(label: String, icon: String, path: String, identifier: String) -> some View {
        Button {
            UIPasteboard.general.string = path
            withAnimation(.spring(response: 0.3)) {
                copiedPath = identifier
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { if copiedPath == identifier { copiedPath = nil } }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 36)
                    .foregroundStyle(Color.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: copiedPath == identifier ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copiedPath == identifier ? .green : .secondary)
                    .animation(.spring(response: 0.3), value: copiedPath)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
