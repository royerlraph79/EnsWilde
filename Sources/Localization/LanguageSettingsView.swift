//
//  LanguageSettingsView.swift
//  EnsWilde
//

import SwiftUI

struct LanguageSettingsView: View {
    @StateObject private var languageManager = LanguageManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var downloadingLanguage: String?
    
    var body: some View {
        Form {
            // Current Language
            Section(header: Text(L("settings_language_current"))) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(getLanguageName(localizationManager.currentLanguage))
                }
            }
            
            // Refresh
            Section {
                Button(action: {
                    Task {
                        await languageManager.fetchAvailableLanguages()
                        if let error = languageManager.lastError {
                            errorMessage = error
                            showErrorAlert = true
                        }
                    }
                }) {
                    HStack {
                        Label(L("settings_language_refresh"), systemImage: "arrow.clockwise")
                        Spacer()
                        if languageManager.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(languageManager.isLoading)
            }
            
            // Available Languages
            if !languageManager.availableLanguages.isEmpty {
                Section(header: Text(L("settings_language_available"))) {
                    ForEach(languageManager.availableLanguages) { language in
                        LanguageRow(
                            language: language,
                            isSelected: localizationManager.currentLanguage == language.code,
                            isDownloaded: languageManager.isDownloaded(language.code),
                            hasUpdate: languageManager.hasUpdate(language),
                            isDownloading: downloadingLanguage == language.code,
                            onSelect: {
                                localizationManager.currentLanguage = language.code
                            },
                            onDownload: {
                                Task {
                                    downloadingLanguage = language.code
                                    let success = await languageManager.downloadLanguage(language)
                                    downloadingLanguage = nil
                                    
                                    if success {
                                        localizationManager.currentLanguage = language.code
                                    } else if let error = languageManager.lastError {
                                        errorMessage = error
                                        showErrorAlert = true
                                    }
                                }
                            },
                            onDelete: {
                                if localizationManager.currentLanguage == language.code {
                                    errorMessage = L("error_cannot_delete_current_language")
                                    showErrorAlert = true
                                    return
                                }
                                languageManager.deleteLanguage(language.code)
                            }
                        )
                    }
                }
            } else if !languageManager.isLoading {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        
                        Text(L("settings_language_no_available"))
                            .foregroundStyle(.secondary)
                        
                        Text(L("settings_language_refresh_prompt"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(L("settings_language"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task {
                    await languageManager.fetchAvailableLanguages()
                }
            }
        }
    }
    
    private func getLanguageName(_ code: String) -> String {
        if let language = languageManager.availableLanguages.first(where: { $0.code == code }) {
            return "\(language.name) (\(language.nativeName))"
        }
        return code == "en" ? "English" : code
    }
}

// MARK: - Language Row Component

struct LanguageRow: View {
    let language: LanguageInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let hasUpdate: Bool
    let isDownloading: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.name)
                Text(language.nativeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if isDownloading {
                    ProgressView()
                } else if hasUpdate {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                } else if isDownloaded {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Button(action: onSelect) {
                                Text(L("settings_language_use"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: onDelete) {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else {
                    Button(action: onDownload) {
                        Label(L("settings_language_download"), systemImage: "arrow.down.circle")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
