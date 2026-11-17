import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GDCMetadataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var state = AppState()
    @StateObject var loc = Loc()
    let args = ProcessInfo.processInfo.arguments

    func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state).environmentObject(loc)
                .task { await launchActions() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open…") { state.chooseFolder() }.keyboardShortcut("o") }
            CommandGroup(replacing: .help) { Button(loc.t("help.guide")) { loc.openGuide() }.keyboardShortcut("?") }
        }
    }

    @MainActor func launchActions() async {
        if let l = arg("--lang") { loc.langRaw = l }
        if let o = arg("--open") { state.openIDs = Set(o.split(separator: ",").map(String.init)) }
        if let p = arg("--scan") { await state.scan(p) }
        else if args.contains("--demo") { state.loadDemo() }
        if let n = arg("--select"), let i = Int(n), i < state.clips.count { state.selection = state.clips[i].id }
        if args.contains("--expand") { state.expandAll = true }
        if let q = arg("--query") { state.query = q }
        if args.contains("--resolve") { state.showResolve = true; if !state.demo { await state.loadResolvePlan(); if args.contains("--apply") { await state.applyResolve(); await state.loadResolvePlan() } } }
        if let out = arg("--snapshot") {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            snapshot(to: out)
            NSApp.terminate(nil)
        }
    }

    @MainActor func snapshot(to path: String) {
        let win = (state.showResolve ? NSApp.windows.first { $0.sheetParent != nil } ?? NSApp.windows.first : NSApp.windows.first) ?? NSApp.keyWindow
        guard let w = win, let v = w.contentView else { return }
        if let size = arg("--size")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2, w.sheetParent == nil { w.setContentSize(NSSize(width: size[0], height: size[1])); v.layoutSubtreeIfNeeded() }
        if args.contains("--screen") {
            // real window capture of this app's own window (needs Screen Recording permission for the host process)
            let pr = Process(); pr.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            pr.arguments = ["-x", "-o", "-l", String(w.windowNumber), path]
            try? pr.run(); pr.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) { return }
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
}
