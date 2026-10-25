import AppKit
import SwiftUI

if CommandLine.arguments.contains("--inventory") {
    let audio=FaderAudio()
    let result:[String:Any]=["apps":audio.applications(),"devices":audio.outputDevices(),"defaultOutput":audio.defaultOutput(),"masterVolume":audio.masterVolume()]
    if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),let s=String(data:data,encoding:.utf8) { print(s) }
    exit(0)
}
final class FaderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: MixerModel!
    var window: NSWindow!
    var status: NSStatusItem!
    var diagnosticTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One owner of the audio path, even when a second copy is opened.
        if NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "dev.ybivashhka.fader").contains(where:{$0.processIdentifier != getpid()}) { NSApp.terminate(nil); return }
        model=MixerModel()
        window=FaderWindow(contentRect:NSRect(x:0,y:0,width:460,height:710),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="Fader"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent=true
        window.isReleasedWhenClosed=false; window.delegate=self
        window.backgroundColor=NSColor(red:0.065,green:0.071,blue:0.085,alpha:1)
        window.contentView=NSHostingView(rootView:MixerView(model:model))
        window.center()
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let b=status.button { b.image=NSImage(systemSymbolName:"slider.horizontal.3",accessibilityDescription:"Fader"); b.target=self; b.action=#selector(toggle); b.sendAction(on:[.leftMouseUp,.rightMouseUp]) }
        show()
        if CommandLine.arguments.contains("--start") { model.toggleEnabled() }
        // A local, opt-in diagnostic file contains meters and states, never audio.
        if let arg=CommandLine.arguments.first(where:{$0.hasPrefix("--diagnostic=")}) {
            let path=String(arg.dropFirst("--diagnostic=".count))
            diagnosticTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
                guard let self=self,let data=try? JSONSerialization.data(withJSONObject:self.model.diagnostic(),options:[.prettyPrinted,.sortedKeys]) else { return }
                try? data.write(to:URL(fileURLWithPath:path),options:.atomic)
            }
        }
    }
    @objc func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu=NSMenu()
            menu.addItem(withTitle:"Открыть Fader",action:#selector(show),keyEquivalent:"").target=self
            menu.addItem(.separator())
            menu.addItem(withTitle:"Завершить Fader",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            status.menu=menu; status.button?.performClick(nil); status.menu=nil
        } else { window.isVisible ? window.orderOut(nil):show() }
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { show(); return true }
    func windowShouldClose(_ sender:NSWindow)->Bool { sender.orderOut(nil); return false }
    func applicationWillTerminate(_ notification:Notification) { model?.stop() }
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate=AppDelegate()
app.delegate=delegate
app.run()
