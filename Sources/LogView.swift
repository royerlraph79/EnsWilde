import SwiftUI
import UIKit

// MARK: - Log model

final class LogModel: ObservableObject {
    @Published var text = ""

    func append(_ msg: String) {
        // Ensure chunks end with newline so output is readable
        if msg.hasSuffix("\n") {
            text += msg
        } else {
            text += msg + "\n"
        }
    }

    func clear() {
        text = ""
    }

    /// Save current log to Documents as a .txt file and return its URL.
    func exportToDocuments(fileName: String = "EnsWilde-Log.txt") throws -> URL {
        let url = URL.documentsDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Globals (keep same style as your current code)

let logPipe = Pipe()
let GLOBAL_LOG = LogModel()

// MARK: - Log view

struct LogView: View {
    @StateObject private var log = GLOBAL_LOG
    @State private var ran = false

    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(GLOBAL_LOG.text)
                    .font(.system(size: 12).monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Spacer().id(0)
            }
            .onAppear {
                guard !ran else { return }
                ran = true

                logPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty, var logString = String(data: data, encoding: .utf8) else { return }

                    DispatchQueue.main.async {
                        // Redact udid if present
                        if !Utils.udid.isEmpty, logString.contains(Utils.udid) {
                            logString = logString.replacingOccurrences(of: Utils.udid, with: "<redacted>")
                        }

                        log.append(logString)
                        proxy.scrollTo(0)
                    }
                }
            }
        }
        .navigationTitle("Log output")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        GLOBAL_LOG.clear()
                    }

                    Button("Export .txt") {
                        do {
                            let url = try GLOBAL_LOG.exportToDocuments()
                            exportURL = url
                            exportError = nil
                            showShareSheet = true
                        } catch {
                            exportError = "\(error)"
                        }
                    }
                }
            }
            .alert("Export failed", isPresented: Binding(
                get: { exportError != nil },
                set: { _ in exportError = nil }
            )) {
                Button("OK") {}
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ShareSheet(activityItems: [exportURL])
                } else {
                    Text("No file")
                        .padding()
                }
            }
    }

    init() {
        // Make stdout/stderr more predictable
        setvbuf(stdout, nil, _IOLBF, 0) // stdout line-buffered
        setvbuf(stderr, nil, _IONBF, 0) // stderr unbuffered

        // Redirect stdout and stderr to the pipe
        dup2(logPipe.fileHandleForWriting.fileDescriptor, fileno(stdout))
        dup2(logPipe.fileHandleForWriting.fileDescriptor, fileno(stderr))
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
