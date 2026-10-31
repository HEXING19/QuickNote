import AppKit
import CryptoKit
import QuickNoteCore

private struct GitHubRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

final class UpdateController {
    weak var app: AppDelegate?
    private var busy = false
    init(app: AppDelegate) { self.app = app }

    func check(automatic: Bool = false) {
        guard !busy else { if !automatic { app?.alert("正在检查或下载更新", "请稍候。") }; return }
        busy = true
        Task { @MainActor in
            var interactive = !automatic
            defer { busy = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/HEXING19/QuickNote/releases/latest")!)
                request.timeoutInterval = 30
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("QuickNote-Updater", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Self.checkResponse(response)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease,
                      let latest = ReleaseVersion(release.tag_name),
                      let current = ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2") else { throw failure("发布版本格式不受支持。") }
                guard latest > current else { if !automatic { app?.alert("已是最新版本", "当前没有可用的 QuickNote 更新。") }; return }
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard let asset = release.assets.first(where: { $0.name == "QuickNote-\(version)-universal.zip" }),
                      asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
                      asset.browser_download_url.path.hasPrefix("/HEXING19/QuickNote/releases/download/"),
                      let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71 else { throw failure("发布缺少 Universal ZIP 或 SHA-256 校验信息。") }
                guard confirm("发现 QuickNote \(version)", String((release.body ?? "新版本已发布。").prefix(1800)), button: "下载更新") else { return }
                interactive = true
                let (file, downloadResponse) = try await URLSession.shared.download(from: asset.browser_download_url)
                defer { try? FileManager.default.removeItem(at: file) }
                try Self.checkResponse(downloadResponse)
                let hash = try await Task.detached { SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined() }.value
                guard "sha256:" + hash == digest.lowercased() else { throw failure("下载文件校验失败，请重新下载。") }
                let destination = Bundle.main.bundleURL
                guard destination.pathExtension == "app", !destination.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else { throw failure("请先将 QuickNote 放入可写的应用程序文件夹，再更新。") }
                let stage = destination.deletingLastPathComponent().appendingPathComponent(".QuickNote-update-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: stage) }
                try await Self.run("/usr/bin/ditto", ["-x", "-k", file.path, stage.path])
                let candidate = stage.appendingPathComponent("QuickNote.app")
                guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else { throw failure("更新包的应用标识或版本不匹配。") }
                try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
                guard confirm("更新已下载", "安装后将重新启动 QuickNote。笔记会先保存。", button: "安装并重启") else { return }
                guard let app, !app.dirty || app.persist() else { throw failure("笔记尚未保存，请先重试保存或导出文字。") }
                let backup = "QuickNote-previous-" + UUID().uuidString + ".app"
                // Launch helper before committing; the gate prevents relaunch on replacement failure.
                let gate = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let helper = Process()
                helper.executableURL = URL(fileURLWithPath: "/bin/sh")
                helper.arguments = ["-c", "for i in $(seq 1 120); do if ! kill -0 \"$1\" 2>/dev/null; then if [ -f \"$3\" ]; then rm -f \"$3\"; /usr/bin/open \"$2\"; fi; exit; fi; sleep 1; done", "quicknote-relaunch", String(ProcessInfo.processInfo.processIdentifier), destination.path, gate.path]
                try helper.run()
                do {
                    try Data().write(to: gate, options: .atomic)
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: candidate, backupItemName: backup, options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
                } catch { helper.terminate(); try? FileManager.default.removeItem(at: gate); throw error }
                NSApp.terminate(nil)
            } catch {
                if interactive { app?.alert("更新失败", error.localizedDescription) }
            }
        }
    }
    private func confirm(_ title: String, _ detail: String, button: String) -> Bool {
        let old = app?.inDialog ?? false; app?.inDialog = true
        defer { app?.inDialog = old }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: button); alert.addButton(withTitle: "稍后")
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func failure(_ text: String) -> Error { NSError(domain: "QuickNote.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private static func checkResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw NSError(domain: "QuickNote.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取 GitHub 发布信息或下载文件，请稍后重试。可能是网络不可用、请求限流或尚未发布版本。"]) }
    }
    private static func run(_ executable: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: "QuickNote.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "更新包解压或签名校验失败。原应用未更改。"]) }
        }.value
    }
}
