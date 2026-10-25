import AppKit
import SwiftUI

struct OutputDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let transport: UInt32
    var symbol: String {
        if name.localizedCaseInsensitiveContains("airpod") || name.localizedCaseInsensitiveContains("headphone") || name.localizedCaseInsensitiveContains("науш") { return "headphones" }
        if name.localizedCaseInsensitiveContains("display") || name.localizedCaseInsensitiveContains("hdmi") { return "display" }
        return "hifispeaker.fill"
    }
}
final class AudioApp: ObservableObject, Identifiable {
    let id: String
    @Published var name: String
    let icon: NSImage
    var processes: [NSNumber] = []
    var sourceDevice: UInt32 = 0
    @Published var sourceName = ""
    @Published var active = false
    @Published var volume: Double
    @Published var muted: Bool
    @Published var peak: Float = 0
    @Published var controlled = false
    @Published var error: String? = nil
    var callbacks: UInt64 = 0
    init(key: String, name: String, path: String) {
        self.id=key; self.name=name
        self.icon=path.isEmpty ? (NSImage(systemSymbolName:"app.fill", accessibilityDescription:nil) ?? NSImage()) : NSWorkspace.shared.icon(forFile:path)
        self.volume = UserDefaults.standard.object(forKey:"volume.\(key)") as? Double ?? 1
        self.muted = UserDefaults.standard.bool(forKey:"mute.\(key)")
    }
}
final class MixerModel: ObservableObject {
    let audio=FaderAudio()
    @Published var apps: [AudioApp] = []
    @Published var devices: [OutputDevice] = []
    @Published var output: UInt32 = 0
    @Published var master: Double = 1
    @Published var masterAvailable = false
    @Published var enabled = false
    @Published var onlyActive = false
    @Published var notice: String? = nil
    @Published var permissionWaiting = false
    @Published var search = ""
    private var scanTimer: Timer?
    private var meterTimer: Timer?
    private var enableTime = Date()
    private let audioQueue=DispatchQueue(label:"dev.ybivashhka.fader.audio",qos:.userInitiated)
    private var requested: [String:String] = [:]
    private var meterPending=false
    private let discoveryQueue=DispatchQueue(label:"dev.ybivashhka.fader.discovery",qos:.utility)
    private var scanPending=false
    private var missingSince: [String:Date] = [:]
    var visibleApps: [AudioApp] { apps.filter { (!onlyActive || $0.active || $0.controlled) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    var activeCount: Int { apps.filter(\.active).count }
    var outputName: String { devices.first(where:{$0.id==output})?.name ?? "Аудиовыход" }
    var outputSymbol: String { devices.first(where:{$0.id==output})?.symbol ?? "hifispeaker.fill" }
    init() {
        scan()
        scanTimer=Timer.scheduledTimer(withTimeInterval:1, repeats:true) { [weak self] _ in self?.scan() }
        meterTimer=Timer.scheduledTimer(withTimeInterval:1.0/24, repeats:true) { [weak self] _ in self?.updateMeters() }
        RunLoop.main.add(scanTimer!,forMode:.common); RunLoop.main.add(meterTimer!,forMode:.common)
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.reconnect() }
    }
    func scan() {
        guard !scanPending else { return }
        scanPending=true
        discoveryQueue.async { [weak self,audio] in
            let ds=audio.outputDevices() as? [[String:Any]] ?? []
            let current=audio.defaultOutput(), v=audio.masterVolume()
            let inventory=audio.applications() as? [[String:Any]] ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self=self else { return }
                self.scanPending=false
                self.applyScan(ds:ds,current:current,v:v,inventory:inventory)
            }
        }
    }
    func applyScan(ds:[[String:Any]],current:UInt32,v:Float,inventory:[[String:Any]]) {
        let newDevices=ds.compactMap { d -> OutputDevice? in
            guard let id=d["id"] as? NSNumber, let name=d["name"] as? String else { return nil }
            return OutputDevice(id:id.uint32Value,name:name,transport:(d["transport"] as? NSNumber)?.uint32Value ?? 0)
        }
        if devices != newDevices { devices=newDevices }
        if output != current { audioQueue.async { [audio] in audio.stopAll() }; requested.removeAll(); output=current; apps.forEach{$0.controlled=false} }
        masterAvailable=v>=0
        if v>=0 && abs(master-Double(v))>0.015 { master=Double(v) }
        var seen=Set<String>()
        for d in inventory {
            guard let key=d["key"] as? String, let name=d["name"] as? String else { continue }
            seen.insert(key); missingSince[key]=nil
            let row: AudioApp
            if let existing=apps.first(where:{$0.id==key}) { row=existing }
            else { row=AudioApp(key:key,name:name,path:d["path"] as? String ?? ""); apps.append(row) }
            row.name=name
            row.active=(d["active"] as? NSNumber)?.boolValue ?? false
            let sources=(d["devices"] as? [NSNumber] ?? []).map(\.uint32Value)
            row.sourceDevice=sources.first(where: { id in devices.contains(where:{$0.id==id}) }) ?? output
            row.sourceName=devices.first(where:{$0.id==row.sourceDevice})?.name ?? outputName
            row.processes=d["processes"] as? [NSNumber] ?? []
            if enabled {
                let signature="\(row.sourceDevice):\(row.processes.map(\.stringValue).sorted().joined(separator:","))"
                if requested[row.id] != signature {
                    requested[row.id]=signature
                    let key=row.id, processes=row.processes, source=row.sourceDevice, volume=Float(row.volume), muted=row.muted
                    audioQueue.async { [weak self,audio] in
                        let error=audio.connect(key,processes:processes,device:source,volume:volume,muted:muted)
                        DispatchQueue.main.async { [weak self] in
                            guard let self=self,self.enabled,self.requested[key]==signature else { return }
                            self.apps.first(where:{$0.id==key})?.error=error
                        }
                    }
                }
            }
        }
        // A short grace period prevents rows jumping when a browser restarts an audio helper.
        for row in apps where !seen.contains(row.id) {
            row.active=false; row.peak=0
            if missingSince[row.id]==nil { missingSince[row.id]=Date() }
            if Date().timeIntervalSince(missingSince[row.id]!)>4 { audioQueue.async { [audio] in audio.disconnect(row.id) }; requested[row.id]=nil; apps.removeAll{$0.id==row.id}; missingSince[row.id]=nil }
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if enabled && Date().timeIntervalSince(enableTime)>7 {
            permissionWaiting=apps.contains(where:{$0.active}) && !apps.contains(where:{$0.controlled})
        }
    }
    func updateMeters() {
        guard enabled && !meterPending else { return }
        meterPending=true
        let keys=apps.map(\.id)
        audioQueue.async { [weak self,audio] in
            let meters=keys.map { ($0,audio.meter(forKey:$0) as? [String:Any] ?? [:]) }
            DispatchQueue.main.async { [weak self] in
                guard let self=self else { return }
                self.meterPending=false
                guard self.enabled else { return }
                for (key,data) in meters {
                    guard let row=self.apps.first(where:{$0.id==key}) else { continue }
                    let p=(data["peak"] as? NSNumber)?.floatValue ?? 0
                    row.peak=max(p,row.peak*0.79)
                    let controlled=(data["controlled"] as? NSNumber)?.boolValue ?? false
                    if row.controlled != controlled { row.controlled=controlled }
                    row.callbacks=(data["callbacks"] as? NSNumber)?.uint64Value ?? 0
                    if let e=data["error"] as? String,!e.isEmpty { row.error=e }
                }
                if self.apps.contains(where:{$0.controlled}) { self.permissionWaiting=false }
            }
        }
    }
    func toggleEnabled() {
        enabled.toggle(); notice=nil; permissionWaiting=false
        if enabled { enableTime=Date(); scan() }
        else { audioQueue.async { [audio] in audio.stopAll() }; requested.removeAll(); apps.forEach { $0.controlled=false; $0.peak=0; $0.error=nil } }
    }
    func reconnect() {
        audioQueue.async { [audio] in audio.stopAll() }; requested.removeAll(); apps.forEach{$0.controlled=false; $0.error=nil}; enableTime=Date(); scan()
    }
    func volume(_ row: AudioApp, _ value: Double) {
        row.volume=value; if row.muted && value>0 { row.muted=false }
        persist(row); apply(row)
    }
    func mute(_ row: AudioApp) {
        row.muted.toggle(); persist(row); apply(row)
    }
    func apply(_ row: AudioApp) {
        let v=Float(row.volume), muted=row.muted, key=row.id
        audioQueue.async { [audio] in audio.setVolume(v,muted:muted,forKey:key) }
    }
    func persist(_ row: AudioApp) {
        UserDefaults.standard.set(row.volume,forKey:"volume.\(row.id)")
        UserDefaults.standard.set(row.muted,forKey:"mute.\(row.id)")
    }
    func changeMaster(_ v: Double) {
        master=v
        discoveryQueue.async { [weak self,audio] in
            let ok=audio.setMasterVolume(Float(v))
            if !ok { DispatchQueue.main.async { self?.notice="Громкость меняется на самом устройстве" } }
        }
    }
    func changeOutput(_ id: UInt32) {
        guard id != output else { return }
        audioQueue.async { [audio] in audio.stopAll() }; requested.removeAll()
        discoveryQueue.async { [weak self,audio] in
            let ok=audio.setDefaultOutput(id)
            DispatchQueue.main.async { if !ok { self?.notice="Не удалось переключить аудиовыход" }; self?.scan() }
        }
        apps.forEach{$0.controlled=false}; scan()
    }
    func reset() { for row in apps { row.muted=false; volume(row,1) } }
    func stop() { scanTimer?.invalidate(); meterTimer?.invalidate(); let group=DispatchGroup(); group.enter(); audioQueue.async { [audio] in audio.stopAll(); group.leave() }; _=group.wait(timeout:.now()+1) }
    func openPermissions() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    func diagnostic() -> [String:Any] {
        ["enabled":enabled,"output":outputName,"master":master,"apps":apps.map{["name":$0.name,"key":$0.id,"active":$0.active,"controlled":$0.controlled,"volume":$0.volume,"muted":$0.muted,"peak":$0.peak,"callbacks":$0.callbacks,"error":$0.error ?? ""] as [String:Any]}]
    }
}
