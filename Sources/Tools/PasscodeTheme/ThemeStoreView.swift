import SwiftUI

// MARK: - Theme Store View
struct ThemeStoreView: View {
    @StateObject private var storeManager = ThemeStoreManager()
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Use LocalizationManager directly without observing to prevent crashes
    private var localizationManager: LocalizationManager { LocalizationManager.shared }
    
    var body: some View {
        Group {
            if let selectedRepo = storeManager.selectedRepository {
                // Show themes from selected repository
                ThemesListView(
                    repository: selectedRepo,
                    themeStore: themeStore,
                    storeManager: storeManager
                )
            } else {
                // Show repository list
                RepositoriesListView(
                    storeManager: storeManager
                )
            }
        }
        .navigationTitle(L("theme_store_title"))
        .task {
            if storeManager.repositories.isEmpty {
                await storeManager.fetchRepositories()
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Repositories List View
struct RepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    
    var body: some View {
        Form {
            if storeManager.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(L("theme_store_loading"))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if let error = storeManager.errorMessage {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            Task {
                                await storeManager.fetchRepositories()
                            }
                        } label: {
                            Text(L("theme_store_retry"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else if storeManager.repositories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(L("theme_store_no_themes"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section(header: Text(L("theme_store_title"))) {
                    ForEach(storeManager.repositories) { repository in
                        RepositoryRowView(repository: repository, storeManager: storeManager)
                    }
                }
            }
            
        }
        .headerProminence(.increased)
        .refreshable {
            await storeManager.fetchRepositories()
        }
    }
}

// MARK: - Repository Row View
struct RepositoryRowView: View {
    let repository: ThemeRepository
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var themeCount: Int?
    
    var body: some View {
        Button {
            Task {
                await storeManager.fetchThemes(from: repository)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.body)
                    
                    if let count = themeCount {
                        Text("\(count) themes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            await fetchThemeCount()
        }
    }
    
    private func fetchThemeCount() async {
        guard let url = URL(string: repository.themesURL) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let themes = try JSONDecoder().decode([RemoteThemeCodable].self, from: data)
            await MainActor.run {
                themeCount = themes.count
            }
        } catch {
            // Silently fail - we'll just show "Loading..." 
        }
    }
}

// MARK: - Themes List View  
struct ThemesListView: View {
    let repository: ThemeRepository
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            if storeManager.isLoading {
                VStack {
                    Spacer(minLength: 60)
                    ProgressView(L("theme_store_loading"))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = storeManager.errorMessage {
                VStack(spacing: 12) {
                    Spacer(minLength: 60)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task {
                            await storeManager.fetchThemes(from: repository)
                        }
                    } label: {
                        Text(L("theme_store_retry"))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if storeManager.remoteThemes.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 60)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(L("theme_store_no_themes"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(storeManager.remoteThemes) { theme in
                        RemoteThemeCardView(
                            theme: theme,
                            themeStore: themeStore,
                            storeManager: storeManager
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(repository.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    storeManager.backToRepositories()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L("theme_store_title"))
                    }
                }
            }
        }
        .refreshable {
            await storeManager.fetchThemes(from: repository)
        }
    }
}

// MARK: - Theme Card View (grid item)
struct RemoteThemeCardView: View {
    let theme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var previewImage: UIImage?
    @State private var isDownloading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    private var localizationManager: LocalizationManager { LocalizationManager.shared }
    
    private var isDownloaded: Bool {
        themeStore.themes.contains { $0.name == theme.name }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Preview image
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 120)
                    .overlay(ProgressView())
            }
            
            // Title + author
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("by \(theme.authors)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action button
            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text(L("theme_store_downloaded"))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            } else {
                Button {
                    downloadTheme()
                } label: {
                    HStack(spacing: 4) {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                        }
                        Text(isDownloading ? L("theme_store_downloading") : L("theme_store_download_import"))
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
                .opacity(isDownloading ? 0.55 : 1.0)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .task {
            await loadPreviewImage()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadPreviewImage() async {
        guard let url = theme.previewURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run { previewImage = image }
            }
        } catch { }
    }
    
    private func downloadTheme() {
        isDownloading = true
        Task {
            do {
                try await storeManager.downloadAndImportTheme(theme, themeStore: themeStore)
                await MainActor.run { isDownloading = false }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
