// gen1recomp iOS native bridge: document picker + Files-app inbox sweep.
//
// liblove's wrap_System.cpp calls into this class through the Objective-C
// runtime (objc_getClass / objc_msgSend), so nothing here may be renamed
// without updating that patch (see mobile/ios/patch_love_src.py).
//
// Contract (mirrors love-android's GameActivity.showFilePicker):
//   love.system.pickFile("rom"|"mod"|"sav"|"required_import") -> copies the user's pick into
//   the LÖVE save directory as picked_rom.gb / picked_mod.zip /
//   picked_save.sav; RomImporter's pending-file scan consumes it.
//   love.system.createFile(name) -> exports save dir's pending_export.sav
//   through the system picker, then writes export_done.flag.

import UIKit
import UniformTypeIdentifiers

@objc(GRPickerBridge)
public final class GRPickerBridge: NSObject {

    // Every live picker keeps its own delegate here
    // (UIDocumentPickerViewController holds its delegate weakly). A single
    // "current delegate" slot would break under double activation: the
    // engine's touch handling can fire a button twice (touch + synthesized
    // mouse), the second present would replace the first picker's delegate,
    // and the sheet the user actually sees would then pick into nil —
    // silently doing nothing.
    private static var liveDelegates: [PickerDelegate] = []

    private static let loveIdentity = "pokemon-love2d"

    @objc(httpDownloadWithUrl:destination:userAgent:accept:)
    public static func httpDownload(url: UnsafePointer<CChar>?,
                                    destination: UnsafePointer<CChar>?,
                                    userAgent: UnsafePointer<CChar>?,
                                    accept: UnsafePointer<CChar>?) -> Bool {
        guard let url, let destination,
              let requestURL = URL(string: String(cString: url)) else { return false }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 300
        if let userAgent, userAgent.pointee != 0 {
            request.setValue(String(cString: userAgent), forHTTPHeaderField: "User-Agent")
        }
        if let accept, accept.pointee != 0 {
            request.setValue(String(cString: accept), forHTTPHeaderField: "Accept")
        }
        let target = URL(fileURLWithPath: String(cString: destination))
        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        let task = URLSession.shared.downloadTask(with: request) { temporary, response, error in
            defer { semaphore.signal() }
            guard error == nil, let temporary,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            try? FileManager.default.removeItem(at: target)
            do {
                try FileManager.default.moveItem(at: temporary, to: target)
                succeeded = true
            } catch {
                succeeded = false
            }
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 305) == .success else {
            task.cancel()
            return false
        }
        return succeeded
    }

    // MARK: - General HTTP request (love.system.httpRequest)

    private static let httpMaxResponse = 4 * 1024 * 1024

    // URLSession turns a 301/302/303 POST into a GET on its own. Save sync
    // signs a method and a body, so every hop re-sends the original request
    // against the new URL instead, and only over https.
    private final class GRRedirectKeeper: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let original = task.originalRequest,
                  let target = request.url,
                  target.scheme?.lowercased() == "https" else {
                completionHandler(nil)
                return
            }
            var next = original
            next.url = target
            completionHandler(next)
        }
    }

    private static let httpSession = URLSession(configuration: .ephemeral,
                                                delegate: GRRedirectKeeper(),
                                                delegateQueue: nil)

    private static func httpEnvelope(_ head: String, _ payload: Data?) -> NSData {
        var out = Data((head + "\n").utf8)
        if let payload { out.append(payload) }
        return out as NSData
    }

    private static func httpErrorText(_ error: Error) -> String {
        var text = error.localizedDescription
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        if text.isEmpty { text = "the request failed" }
        if text.count > 160 { text = String(text.prefix(160)) }
        return text
    }

    /// Blocking HTTPS request with a chosen method, headers and byte body, the
    /// iOS half of love.system.httpRequest (see the Android GameActivity one).
    /// Headers arrive as "name: value" lines joined by newlines. The reply is
    /// an envelope: a head line of "STATUS <code>" or "ERROR <text>", a
    /// newline, then the raw response bytes -- read for 4xx and 5xx as well,
    /// because a sync conflict answers 409 with the save that won.
    @objc(httpRequestWithUrl:method:headers:body:bodyLength:userAgent:)
    public static func httpRequest(url: UnsafePointer<CChar>?,
                                   method: UnsafePointer<CChar>?,
                                   headers: UnsafePointer<CChar>?,
                                   body: UnsafePointer<UInt8>?,
                                   bodyLength: Int32,
                                   userAgent: UnsafePointer<CChar>?) -> NSData? {
        guard let url, let requestURL = URL(string: String(cString: url)) else {
            return httpEnvelope("ERROR missing url", nil)
        }
        guard requestURL.scheme?.lowercased() == "https" else {
            return httpEnvelope("ERROR https only", nil)
        }
        let verb = (method.map { String(cString: $0) } ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "DELETE"].contains(verb) else {
            return httpEnvelope("ERROR unsupported request method", nil)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = verb
        request.timeoutInterval = 60
        request.setValue(userAgent.map { String(cString: $0) } ?? "gen1recomp",
                         forHTTPHeaderField: "User-Agent")
        if let headers, headers.pointee != 0 {
            for line in String(cString: headers).split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else {
                    return httpEnvelope("ERROR bad request header", nil)
                }
                let name = line[line.startIndex..<colon]
                    .trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    return httpEnvelope("ERROR bad request header", nil)
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if verb != "GET", let body, bodyLength > 0 {
            request.httpBody = Data(bytes: body, count: Int(bodyLength))
        }

        let semaphore = DispatchSemaphore(value: 0)
        var envelope = httpEnvelope("ERROR no response", nil)
        let task = httpSession.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                envelope = httpEnvelope("ERROR " + httpErrorText(error), nil)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                envelope = httpEnvelope("ERROR no response", nil)
                return
            }
            let payload = data ?? Data()
            if payload.count > httpMaxResponse {
                envelope = httpEnvelope("ERROR the reply was too large", nil)
                return
            }
            envelope = httpEnvelope("STATUS \(http.statusCode)", payload)
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 65) == .success else {
            task.cancel()
            return httpEnvelope("ERROR the request timed out", nil)
        }
        return envelope
    }

    // MARK: - Entry points called from liblove (C strings on purpose)

    @objc(presentPickerWithKind:saveDir:)
    public static func presentPicker(kind: UnsafePointer<CChar>?,
                                     saveDir: UnsafePointer<CChar>?) -> Bool {
        let kindStr = kind.map { String(cString: $0) } ?? "rom"
        guard let dir = resolvedSaveDir(saveDir) else { return false }

        let destName: String
        var types: [UTType] = []
        switch kindStr {
        case "mod":
            destName = "picked_mod.zip"
            types = [.zip]
        case "sav":
            destName = "picked_save.sav"
        case "required_import":
            destName = "picked_required_import.bin"
        // A Nintendo 64 cartridge, for mods that build assets out of one --
        // the voxel mod's Pokemon Stadium battle models are the caller this
        // was added for. Its own filename on purpose: an N64 ROM landing on
        // picked_rom.gb is swept up by the Game Boy importer, deleted, and
        // reported to the player as a broken cartridge.
        case "stadium":
            destName = "picked_stadium.z64"
            for ext in ["z64", "n64", "v64"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
        case "rom", "":
            destName = "picked_rom.gb"
            for ext in ["gb", "gbc"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
        // An unknown kind is REFUSED rather than treated as a Game Boy ROM.
        //
        // It used to fall through to picked_rom.gb, so a caller asking for a
        // kind this build had never heard of got its file deleted and
        // reported as a broken cartridge -- the worst possible answer to
        // "I do not know that one". Returning false lets the caller find out
        // and offer its own fallback.
        default:
            return false
        }
        // .gb/.gbc/.sav resolve to dynamic UTTypes on most devices; offering
        // .data as well keeps every real file selectable. The importer
        // validates by size + SHA-1, so a wrong pick is rejected safely.
        types.append(.data)
        if !types.contains(.item) { types.append(.item) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                    asCopy: true)
        picker.allowsMultipleSelection = false
        let delegate = PickerDelegate { urls in
            guard let src = urls.first else { return }
            copyItem(at: src, into: dir, named: destName)
        }
        return present(picker, with: delegate)
    }

    // Which kinds presentPicker understands, comma separated.
    //
    // So a CALLER can ask before it calls. A mod that wants a kind this build
    // predates cannot otherwise tell "refused" from "the picker would not
    // open", and guessing wrong used to cost the player their ROM (see the
    // default case above). Asking first turns that into a fallback the caller
    // chooses rather than a file it loses.
    //
    // Kept beside the switch it describes, because the two drifting apart is
    // the only way this can lie.
    @objc public static func supportedPickerKinds() -> NSString {
        return "rom,mod,sav,stadium,required_import" as NSString
    }

    @objc(presentExportWithName:saveDir:)
    public static func presentExport(name: UnsafePointer<CChar>?,
                                     saveDir: UnsafePointer<CChar>?) -> Bool {
        let suggested = name.map { String(cString: $0) } ?? "export.sav"
        guard let dir = resolvedSaveDir(saveDir) else { return false }
        let staged = dir.appendingPathComponent("pending_export.sav")
        guard FileManager.default.fileExists(atPath: staged.path) else { return false }

        // Stage under the suggested name so the picker's filename field is
        // prefilled; forExporting moves/copies it to the user's destination.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggested)
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: staged, to: tmp)
        } catch {
            NSLog("GRPickerBridge: staging export failed: \(error)")
            return false
        }

        let picker = UIDocumentPickerViewController(forExporting: [tmp], asCopy: true)
        let delegate = PickerDelegate { urls in
            guard !urls.isEmpty else { return }
            // Same completion signal love-android's GameActivity writes;
            // RomImporter:focus consumes it and clears pending_export.sav.
            let flag = dir.appendingPathComponent("export_done.flag")
            try? "ok".data(using: .utf8)?.write(to: flag)
        }
        return present(picker, with: delegate)
    }

    // Moves ROM/mod/save files the user dropped into the app's Documents
    // folder (Files app / Finder file sharing) into the LÖVE save directory,
    // where the importer's pending-file scan looks. Called on every
    // UIApplicationDidBecomeActive (see GRBootstrap.m).
    @objc public static func sweepInbox() {
        let fm = FileManager.default
        migrateLegacySaveDirectory()
        guard let docs = documentsDirectory(),
              let saveDir = publicSaveDirectory() else { return }
        guard docs.standardizedFileURL != saveDir.standardizedFileURL else { return }
        let wanted: Set<String> = ["gb", "gbc", "zip", "sav"]
        guard let items = try? fm.contentsOfDirectory(at: docs,
                                                      includingPropertiesForKeys: nil) else { return }
        for url in items where wanted.contains(url.pathExtension.lowercased()) {
            ensureDirectory(saveDir)
            let dest = saveDir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            do {
                try fm.moveItem(at: url, to: dest)
                NSLog("GRPickerBridge: swept %@ into save dir", url.lastPathComponent)
            } catch {
                NSLog("GRPickerBridge: sweep failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    @objc public static func preparePublicDocuments() {
        migrateLegacySaveDirectory()
        if let saveDir = publicSaveDirectory() {
            ensureDirectory(saveDir)
        }
    }

    // MARK: - Helpers

    private static func resolvedSaveDir(_ cstr: UnsafePointer<CChar>?) -> URL? {
        var dir = cstr.map { String(cString: $0) } ?? ""
        if dir.isEmpty {
            migrateLegacySaveDirectory()
            guard let saveDir = publicSaveDirectory() else { return nil }
            dir = saveDir.path
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        ensureDirectory(url)
        return url
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
    }

    private static func documentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask).first
    }

    private static func publicSaveDirectory() -> URL? {
        documentsDirectory()
    }

    private static func legacySaveDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask).first?
            .appendingPathComponent(loveIdentity, isDirectory: true)
    }

    private static func migrateLegacySaveDirectory() {
        let fm = FileManager.default
        guard let destination = publicSaveDirectory(),
              let legacy = legacySaveDirectory(),
              fm.fileExists(atPath: legacy.path) else {
            return
        }
        ensureDirectory(destination)
        mergeDirectory(from: legacy, to: destination)
        try? fm.removeItem(at: legacy)
    }

    private static func mergeDirectory(from source: URL, to destination: URL) {
        let fm = FileManager.default
        ensureDirectory(destination)
        guard let items = try? fm.contentsOfDirectory(at: source,
                                                       includingPropertiesForKeys: nil)
        else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            var sourceIsDirectory = ObjCBool(false)
            fm.fileExists(atPath: item.path, isDirectory: &sourceIsDirectory)
            var targetIsDirectory = ObjCBool(false)
            let targetExists = fm.fileExists(atPath: target.path,
                                              isDirectory: &targetIsDirectory)
            if sourceIsDirectory.boolValue && targetExists && targetIsDirectory.boolValue {
                mergeDirectory(from: item, to: target)
                continue
            }
            if targetExists {
                if !sourceIsDirectory.boolValue && !targetIsDirectory.boolValue &&
                    fm.contentsEqual(atPath: item.path, andPath: target.path) {
                    try? fm.removeItem(at: item)
                } else {
                    moveToLegacyName(item, in: destination)
                }
                continue
            }
            try? fm.moveItem(at: item, to: target)
        }
    }

    private static func moveToLegacyName(_ item: URL, in destination: URL) {
        let fm = FileManager.default
        let base = item.lastPathComponent + ".legacy"
        var target = destination.appendingPathComponent(base)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(base).\(suffix)")
            suffix += 1
        }
        try? fm.moveItem(at: item, to: target)
    }

    private static func copyItem(at src: URL, into dir: URL, named name: String) {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        ensureDirectory(dir)
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            NSLog("GRPickerBridge: delivered %@", name)
        } catch {
            NSLog("GRPickerBridge: copy failed: \(error)")
            // Surface the failure in-game: the Lua pick poll turns this
            // into an on-screen notice instead of a silent no-op.
            let report = "Could not copy \(src.lastPathComponent): " +
                error.localizedDescription
            try? report.data(using: .utf8)?
                .write(to: dir.appendingPathComponent("pick_error.txt"))
        }
    }

    private static func present(_ picker: UIDocumentPickerViewController,
                                with delegate: PickerDelegate) -> Bool {
        let doPresent = { () -> Bool in
            // Double activation (touch + synthesized mouse) arrives within
            // one frame — before UIKit even exposes the first sheet via
            // presentedViewController — so gate on our own delegate list.
            // Without this the stacked present makes the picker auto-dismiss
            // with zero documents (observed as didPickDocumentsAt 0 urls)
            // and the user's pick silently does nothing.
            guard var top = UIApplication.shared.windows
                .first(where: { $0.isKeyWindow })?.rootViewController
            else { return false }
            // Self-heal before consulting the list. If UIKit is presenting
            // nothing at all, any delegate still in it belongs to a sheet
            // that is long gone, and treating it as live would lock the
            // picker out for the rest of the session. Belt and braces with
            // the dismissal callback above: that one closes the known hole,
            // this one closes whatever hole iOS invents next.
            if top.presentedViewController == nil, !liveDelegates.isEmpty {
                NSLog("GRPickerBridge: clearing %d stale delegate(s)",
                      liveDelegates.count)
                liveDelegates.removeAll()
            }
            guard liveDelegates.isEmpty else {
                NSLog("GRPickerBridge: picker already active; ignoring re-present")
                return true
            }
            while let presented = top.presentedViewController { top = presented }
            picker.delegate = delegate
            picker.presentationController?.delegate = delegate
            liveDelegates.append(delegate)
            delegate.onFinish = { [weak delegate] in
                liveDelegates.removeAll { $0 === delegate }
            }
            top.present(picker, animated: true)
            return true
        }
        if Thread.isMainThread { return doPresent() }
        var ok = false
        DispatchQueue.main.sync { ok = doPresent() }
        return ok
    }
}

private final class PickerDelegate: NSObject, UIDocumentPickerDelegate,
                                    UIAdaptivePresentationControllerDelegate {
    private let onPick: ([URL]) -> Void
    var onFinish: (() -> Void)?
    init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        NSLog("GRPickerBridge: didPickDocumentsAt %d url(s)", urls.count)
        onPick(urls)
        onFinish?()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // No file was written; the Lua side's pending-file poll simply
        // never finds anything.
        NSLog("GRPickerBridge: picker cancelled")
        onFinish?()
    }

    // Swiping the sheet down calls NEITHER of the two above: since iOS 13 an
    // interactively dismissed picker reports only through the adaptive
    // presentation delegate. Without this the delegate is never taken out of
    // liveDelegates, the re-present guard below then swallows every later
    // picker while still answering true -- so Lua arms its poll and waits for
    // a file that no sheet is ever going to produce. That is the whole of the
    // "Import ROM does nothing until you restart the app" report: the restart
    // is not refreshing anything, it is clearing this array.
    func presentationControllerDidDismiss(_ presentationController:
                                          UIPresentationController) {
        NSLog("GRPickerBridge: picker dismissed interactively")
        onFinish?()
    }
}
