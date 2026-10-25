import AppKit
import SwiftUI

private final class FaderSliderCell: NSSliderCell {
    var tint=NSColor(red:1,green:0.40,blue:0.29,alpha:1)
    override var knobThickness: CGFloat { 15 }
    override func drawBar(inside rect:NSRect,flipped:Bool) {
        let bar=NSRect(x:rect.minX,y:rect.midY-2.5,width:rect.width,height:5)
        NSColor.white.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect:bar,xRadius:2.5,yRadius:2.5).fill()
        let fraction=CGFloat((doubleValue-minValue)/max(maxValue-minValue,0.001))
        let fill=NSRect(x:bar.minX,y:bar.minY,width:bar.width*fraction,height:bar.height)
        tint.withAlphaComponent(isEnabled ? 1:0.25).setFill()
        NSBezierPath(roundedRect:fill,xRadius:2.5,yRadius:2.5).fill()
    }
    override func drawKnob(_ rect:NSRect) {
        let knob=NSRect(x:rect.midX-7.5,y:rect.midY-7.5,width:15,height:15)
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.3);shadow.shadowBlurRadius=3;shadow.shadowOffset=NSSize(width:0,height:-1);shadow.set()
        (isEnabled ? NSColor(white:0.96,alpha:1):NSColor(white:0.5,alpha:1)).setFill()
        NSBezierPath(ovalIn:knob).fill();NSGraphicsContext.restoreGraphicsState()
    }
}
struct VolumeSlider: NSViewRepresentable {
    @Binding var value: Double
    var label: String
    var muted=false
    var enabled=true
    func makeCoordinator()->Coordinator { Coordinator(value:$value) }
    func makeNSView(context:Context)->NSSlider {
        let slider=NSSlider(value:value,minValue:0,maxValue:1,target:context.coordinator,action:#selector(Coordinator.changed(_:)))
        let cell=FaderSliderCell(); cell.minValue=0;cell.maxValue=1;cell.doubleValue=value;cell.isContinuous=true;cell.target=context.coordinator;cell.action=#selector(Coordinator.changed(_:));slider.cell=cell
        slider.isContinuous=true;slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider:NSSlider,context:Context) {
        context.coordinator.value=$value
        if abs(slider.doubleValue-value)>0.0001 { slider.doubleValue=value }
        slider.isEnabled=enabled
        (slider.cell as? FaderSliderCell)?.tint=muted ? NSColor(white:0.45,alpha:1):NSColor(red:1,green:0.40,blue:0.29,alpha:1)
        slider.setAccessibilityLabel(label);slider.needsDisplay=true
    }
    final class Coordinator:NSObject {
        var value:Binding<Double>
        init(value:Binding<Double>) { self.value=value }
        @objc func changed(_ slider:NSSlider) { value.wrappedValue=slider.doubleValue }
    }
}
