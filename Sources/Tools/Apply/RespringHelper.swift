import Foundation

enum RespringHelper {
    static func respring() throws {
        guard let context = JITEnableContext.shared else { return }
        let processes = try getRunningProcesses()
        if let pid_backboardd = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.backboardd) == true })?.key {
            try context.killProcess(withPID: pid_backboardd, signal: SIGKILL)
        }
    }

    static func getRunningProcesses() throws -> [Int32: String?] {
        guard let context = JITEnableContext.shared,
              let processList = try? context.fetchProcessList() as? [[String: Any]] else {
            return [:]
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
