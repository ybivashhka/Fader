import SwiftUI
import AppKit

private let accent=Color(red:1,green:0.40,blue:0.29)
private let mutedText=Color(red:0.54,green:0.56,blue:0.61)
private let surface=Color(red:0.105,green:0.112,blue:0.13)

struct BrandMark: View {
    var body: some View {
        HStack(spacing:4) {
            ForEach(0..<3) { i in
                ZStack { Capsule().fill(accent.opacity(0.3)).frame(width:3,height:24)
                    RoundedRectangle(cornerRadius:2).fill(accent).frame(width:9,height:6).offset(y:CGFloat([4,-5,1][i]))
                }.frame(width:9,height:28)
            }
        }
    }
}
struct LevelMeter: View {
    var level: Float
    var muted: Bool
    var body: some View {
        let normalized=level>0.00001 ? max(0,min(1,(20*log10(Double(level))+54)/54)) : 0
        HStack(spacing:3) {
            ForEach(0..<16) { i in
                Capsule().fill(!muted && Double(i)/16<normalized ? (i>12 ? accent : Color(red:0.54,green:0.85,blue:0.65)) : Color.white.opacity(0.07)).frame(height:3)
            }
        }.animation(.linear(duration:0.07),value:level).accessibilityElement(children:.ignore).accessibilityLabel("Уровень звука").accessibilityValue(level>0.00001 ? "\(Int(20*log10(Double(level)))) децибел":"Тишина")
    }
}
struct MixerView: View {
    @ObservedObject var model: MixerModel
    var body: some View {
        VStack(spacing:0) {
            header
            ScrollView {
                VStack(spacing:20) {
                    outputCard
                    if !model.enabled { onboarding }
                    if model.permissionWaiting { permissionCard }
                    if let notice=model.notice { Text(notice).font(.system(size:12)).foregroundColor(accent).frame(maxWidth:.infinity,alignment:.leading) }
                    appSection
                }.padding(.horizontal,24).padding(.top,8).padding(.bottom,24)
            }.scrollIndicators(.hidden)
            footer
        }
        .background(Color(red:0.065,green:0.071,blue:0.085))
        .foregroundColor(.white).preferredColorScheme(.dark)
        .frame(minWidth:440,maxWidth:520,minHeight:570)
    }
    var header: some View {
        HStack(spacing:12) {
            BrandMark()
            VStack(alignment:.leading,spacing:3) {
                Text("Fader").font(.system(size:25,weight:.semibold,design:.rounded)).tracking(-0.8)
                Text("Каждому свой уровень").font(.system(size:11,weight:.medium)).foregroundColor(mutedText)
            }
            Spacer()
            Button { model.toggleEnabled() } label: {
                Image(systemName:"power").font(.system(size:16,weight:.semibold)).foregroundColor(model.enabled ? accent : mutedText)
                    .frame(width:38,height:38).background(model.enabled ? accent.opacity(0.13):Color.white.opacity(0.04)).clipShape(Circle())
            }.buttonStyle(.plain).help(model.enabled ? "Выключить микшер и восстановить обычный звук":"Включить микшер").accessibilityLabel(model.enabled ? "Выключить микшер":"Включить микшер")
            Menu {
                Button("Сбросить уровни",action:model.reset)
                Button("Переподключить аудио",action:model.reconnect)
                Button("Разрешение на системный звук",action:model.openPermissions)
                Divider()
                Button("Завершить Fader") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName:"ellipsis").font(.system(size:18,weight:.semibold)).foregroundColor(mutedText).frame(width:25,height:36)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Настройки")
        }.padding(.horizontal,24).padding(.top,35).padding(.bottom,22)
    }
    var outputCard: some View {
        VStack(alignment:.leading,spacing:17) {
            HStack(spacing:12) {
                Image(systemName:model.outputSymbol).font(.system(size:19,weight:.medium)).foregroundColor(accent).frame(width:40,height:40).background(accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:4) {
                    Text("ВЫХОД ЗВУКА").font(.system(size:9,weight:.bold)).tracking(1.7).foregroundColor(mutedText)
                    Menu {
                        ForEach(model.devices) { d in
                            Button { model.changeOutput(d.id) } label: { if d.id==model.output { Label(d.name,systemImage:"checkmark") } else { Text(d.name) } }
                        }
                    } label: {
                        HStack(spacing:7) { Text(model.outputName).font(.system(size:14,weight:.semibold)).lineLimit(1); Image(systemName:"chevron.down").font(.system(size:9,weight:.bold)).foregroundColor(mutedText) }
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal:false,vertical:true).help("Выбрать системный аудиовыход")
                }
                Spacer(minLength:0)
            }
            if model.masterAvailable {
                HStack(spacing:10) {
                    Image(systemName:"speaker.fill").font(.system(size:11)).foregroundColor(mutedText)
                    VolumeSlider(value:Binding(get:{model.master},set:{model.changeMaster($0)}),label:"Общая громкость").frame(height:24)
                    Text("\(Int((model.master*100).rounded()))%").font(.system(size:11,weight:.medium,design:.monospaced)).foregroundColor(mutedText).frame(width:35,alignment:.trailing)
                }
            } else {
                Text("Общая громкость регулируется на устройстве").font(.system(size:11)).foregroundColor(mutedText)
            }
        }.padding(17).background(surface).clipShape(RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Color.white.opacity(0.045),lineWidth:1))
    }
    var onboarding: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("У каждого приложения —\nсвоя громкость.").font(.system(size:22,weight:.semibold)).tracking(-0.5).fixedSize(horizontal:false,vertical:true)
            Text("macOS попросит доступ к системному звуку.\nАудио обрабатывается на Mac и не сохраняется.").font(.system(size:12)).foregroundColor(mutedText).lineSpacing(4)
            Button { model.toggleEnabled() } label: {
                HStack { Text("Включить микшер").font(.system(size:13,weight:.semibold)); Spacer(); Image(systemName:"arrow.right").font(.system(size:13,weight:.semibold)) }.padding(13).background(accent).foregroundColor(Color(red:0.18,green:0.055,blue:0.03)).clipShape(RoundedRectangle(cornerRadius:10))
            }.buttonStyle(.plain)
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(accent.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius:16))
    }
    var permissionCard: some View {
        VStack(alignment:.leading,spacing:9) {
            Label("Пока не поступает звук",systemImage:"waveform.badge.exclamationmark").font(.system(size:12,weight:.semibold))
            Text("Включи воспроизведение. Если индикатор не оживает, разреши Fader доступ к системному звуку в настройках macOS, затем переподключи аудио.").font(.system(size:11)).foregroundColor(mutedText).fixedSize(horizontal:false,vertical:true)
            HStack { Button("Настройки",action:model.openPermissions); Button("Переподключить",action:model.reconnect) }.font(.system(size:11))
        }.padding(14).background(accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:12))
    }
    var appSection: some View {
        VStack(spacing:13) {
            HStack {
                Text("ПРИЛОЖЕНИЯ").font(.system(size:10,weight:.bold)).tracking(1.8).foregroundColor(mutedText)
                Text("\(model.apps.count)").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundColor(mutedText).padding(.horizontal,6).padding(.vertical,3).background(Color.white.opacity(0.05)).clipShape(Capsule())
                Spacer()
                Button { withAnimation(.easeInOut(duration:0.18)) { model.onlyActive.toggle() } } label: { HStack(spacing:4) { Circle().fill(model.onlyActive ? accent : mutedText).frame(width:4,height:4); Text(model.onlyActive ? "Активные":"Все").font(.system(size:11,weight:.medium)) }.foregroundColor(model.onlyActive ? accent:mutedText) }.buttonStyle(.plain).help("Показать только активные аудиоприложения")
            }
            if model.apps.count>5 {
                HStack { Image(systemName:"magnifyingglass").foregroundColor(mutedText); TextField("Найти приложение",text:$model.search).textFieldStyle(.plain).font(.system(size:12)) }.padding(10).background(surface).clipShape(RoundedRectangle(cornerRadius:9))
            }
            if model.visibleApps.isEmpty {
                VStack(spacing:10) { Image(systemName:"waveform").font(.system(size:30,weight:.light)).foregroundColor(mutedText); Text(model.search.isEmpty ? "Здесь появятся приложения со звуком":"Ничего не найдено").font(.system(size:13,weight:.medium)); Text("Запусти музыку или открой видео").font(.system(size:11)).foregroundColor(mutedText) }.frame(maxWidth:.infinity).padding(.vertical,34)
            } else {
                LazyVStack(spacing:10) { ForEach(model.visibleApps) { row in AppRow(row:row,model:model) } }
            }
        }
    }
    var footer: some View {
        HStack(spacing:7) {
            Circle().fill(model.enabled ? Color(red:0.54,green:0.85,blue:0.65):mutedText).frame(width:5,height:5)
            Text(model.enabled ? "Микшер включён":"Обычный звук").font(.system(size:10,weight:.medium))
            Spacer()
            Text("Всегда в строке меню").font(.system(size:10))
        }.foregroundColor(mutedText).padding(.horizontal,25).padding(.vertical,15).background(Color.white.opacity(0.018))
    }
}
struct AppRow: View {
    @ObservedObject var row: AudioApp
    @ObservedObject var model: MixerModel
    var body: some View {
        VStack(spacing:12) {
            HStack(spacing:11) {
                Image(nsImage:row.icon).resizable().interpolation(.high).frame(width:35,height:35)
                VStack(alignment:.leading,spacing:4) {
                    Text(row.name).font(.system(size:13,weight:.semibold)).lineLimit(1)
                    HStack(spacing:4) {
                        if row.active { Circle().fill(row.controlled ? Color(red:0.54,green:0.85,blue:0.65):mutedText).frame(width:4,height:4) }
                        Text(row.error != nil ? "Не удалось подключить" : row.muted && row.controlled ? "Звук выключен" : row.active ? row.sourceName : "Ожидает воспроизведения").font(.system(size:10)).foregroundColor(row.error != nil ? accent:mutedText).lineLimit(1)
                    }
                }
                Spacer(minLength:0)
                Button { model.volume(row,1) } label: { Text("\(Int((row.volume*100).rounded()))").font(.system(size:17,weight:.medium,design:.rounded)).monospacedDigit().foregroundColor(row.muted ? mutedText:.white)+Text(" %").font(.system(size:10,weight:.medium)).foregroundColor(mutedText) }.buttonStyle(.plain).help("Вернуть громкость 100%")
            }
            HStack(spacing:12) {
                Button { model.mute(row) } label: { Image(systemName:row.muted || row.volume==0 ? "speaker.slash.fill":"speaker.wave.2.fill").font(.system(size:13)).foregroundColor(row.muted ? accent:mutedText).frame(width:22,height:22) }.buttonStyle(.plain).accessibilityLabel("\(row.muted ? "Включить":"Выключить") звук \(row.name)")
                VolumeSlider(value:Binding(get:{row.volume},set:{model.volume(row,$0)}),label:"Громкость \(row.name)",muted:row.muted,enabled:model.enabled && row.error == nil).frame(height:24)
            }.disabled(!model.enabled || row.error != nil).opacity(model.enabled ? 1:0.4)
            LevelMeter(level:row.peak,muted:row.muted).padding(.leading,34)
            if let e=row.error { Text(e).font(.system(size:10)).foregroundColor(accent).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled) }
        }.padding(15).background(surface.opacity(row.active ? 1:0.6)).clipShape(RoundedRectangle(cornerRadius:15))
        .overlay(RoundedRectangle(cornerRadius:15).strokeBorder(row.controlled && !row.muted && row.peak>0.001 ? accent.opacity(0.19):Color.white.opacity(0.035),lineWidth:1))
    }
}
