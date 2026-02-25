import SwiftUI
import UniformTypeIdentifiers

struct zPatchCustomView: View {
    @StateObject private var patchStore = zPatchStore()
    @AppStorage("zPatchCustomEnabled") private var enabled: Bool = false
    
    @State private var showAddSheet = false
    @State private var newSourcePath: String = ""
    @State private var newDestPath: String = ""
    @State private var showFileImporter = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var editingPatch: zPatchItem? = nil
    
    var body: some View {
        Form {
            Section(header: Text(L("tool_zpatch_custom"))) {
                Toggle(L("enable_tweak"), isOn: $enabled)
            }
            
            Section(header: Text(L("section_patch_list"))) {
                Button("Add New Patch") {
                    showAddSheet = true
                }
                
                if !patchStore.patches.isEmpty {
                    ForEach(patchStore.patches) { patch in
                        patchRow(patch)
                    }
                }
            }
            
            Section(header: Text(L("section_info"))) {
                Text("Add custom file patches. Select a source file and specify a destination path. Enable patches you want to apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_zpatch_custom"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            addPatchSheet
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func patchRow(_ patch: zPatchItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { patch.isEnabled },
                set: { _ in patchStore.togglePatch(patch) }
            ))
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Source: \(patch.sourcePath.split(separator: "/").last ?? "Unknown")")
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                
                Text("→ \(patch.destinationPath)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .contextMenu {
            Button {
                editPatch(patch)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                patchStore.removePatch(patch)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var addPatchSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Source File")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Text(newSourcePath.isEmpty ? "Select File" : newSourcePath.split(separator: "/").last.map(String.init) ?? "Selected")
                                .foregroundStyle(newSourcePath.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "folder")
                        }
                    }
                }
                
                Section(header: Text("Destination Path")) {
                    TextField("e.g., /var/mobile/Media/file.txt", text: $newDestPath)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                Section(header: Text(L("section_actions"))) {
                    Button(editingPatch != nil ? "Update Patch" : "Save Patch") {
                        savePatch()
                    }
                    .disabled(newSourcePath.isEmpty || newDestPath.isEmpty)
                }
            }
            .navigationTitle(editingPatch != nil ? "Edit Patch" : "Add Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddSheet = false
                        resetForm()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data, .item],
                onCompletion: handleFileImport
            )
        }
    }
    
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Copy file to Documents directory
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = url.lastPathComponent
            let destinationURL = documentsDirectory.appendingPathComponent("zPatchCustomFiles").appendingPathComponent(fileName)
            
            do {
                // Create directory if needed
                let dirURL = documentsDirectory.appendingPathComponent("zPatchCustomFiles")
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                
                // Remove existing file if any
                try? FileManager.default.removeItem(at: destinationURL)
                
                // Start accessing security-scoped resource
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // Copy file
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                // Save the Documents path
                newSourcePath = destinationURL.path
            } catch {
                errorMessage = "Failed to import file: \(error.localizedDescription)"
                showErrorAlert = true
            }
            
        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    private func savePatch() {
        if let editing = editingPatch {
            // Update existing patch
            var updatedPatch = editing
            updatedPatch.sourcePath = newSourcePath
            updatedPatch.destinationPath = newDestPath
            patchStore.updatePatch(updatedPatch)
        } else {
            // Create new patch
            let patch = zPatchItem(
                sourcePath: newSourcePath,
                destinationPath: newDestPath,
                isEnabled: false
            )
            patchStore.addPatch(patch)
        }
        showAddSheet = false
        resetForm()
    }
    
    private func editPatch(_ patch: zPatchItem) {
        editingPatch = patch
        newSourcePath = patch.sourcePath
        newDestPath = patch.destinationPath
        showAddSheet = true
    }
    
    private func resetForm() {
        newSourcePath = ""
        newDestPath = ""
        editingPatch = nil
    }
}
