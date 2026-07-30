// gen1recomp iOS native bridge: document picker + Files-app inbox sweep.
//
// liblove's wrap_System.cpp calls into this class through the Objective-C
// runtime (objc_getClass / objc_msgSend), so nothing here may be renamed
// without updating that patch (see mobile/ios/patch_love_src.py).
//
// Contract (mirrors love-android's GameActivity.showFilePicker):
//   love.system.pickFile("rom"|"mod"|"sav") -> copies the user's pick into
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

    // conf.lua t.identity — where LÖVE puts the fused save directory on iOS
    // (<sandbox>/Library/Application Support/<identity>).
    private static let loveIdentity = "pokemon-love2d"

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
        default:
            destName = "picked_rom.gb"
            for ext in ["gb", "gbc"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
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
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let appSupport = fm.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first else { return }
        let saveDir = appSupport.appendingPathComponent(loveIdentity, isDirectory: true)
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

    // MARK: - Helpers

    private static func resolvedSaveDir(_ cstr: UnsafePointer<CChar>?) -> URL? {
        var dir = cstr.map { String(cString: $0) } ?? ""
        if dir.isEmpty {
            guard let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            else { return nil }
            dir = appSupport.appendingPathComponent(loveIdentity).path
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        ensureDirectory(url)
        return url
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
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
            guard liveDelegates.isEmpty else {
                NSLog("GRPickerBridge: picker already active; ignoring re-present")
                return true
            }
            guard var top = UIApplication.shared.windows
                .first(where: { $0.isKeyWindow })?.rootViewController
            else { return false }
            while let presented = top.presentedViewController { top = presented }
            picker.delegate = delegate
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

private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
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
}
