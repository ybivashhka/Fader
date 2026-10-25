#import "FaderAudio.h"
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <libproc.h>
#include <atomic>
#include <map>
#include <memory>
#include <vector>
#include "FaderDSP.h"

static AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal, UInt32 element=kAudioObjectPropertyElementMain) { return {selector,scope,element}; }
template<class T> static T value(AudioObjectID object, AudioObjectPropertySelector selector, T fallback={}, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal, UInt32 element=kAudioObjectPropertyElementMain) {
    auto a=address(selector,scope,element); UInt32 size=sizeof(T); T result=fallback;
    if (AudioObjectGetPropertyData(object,&a,0,nullptr,&size,&result)!=noErr) return fallback;
    return result;
}
static NSArray<NSNumber*>* objects(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {
    auto a=address(selector,scope); UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(object,&a,0,nullptr,&size)!=noErr || !size) return @[];
    std::vector<AudioObjectID> ids(size/sizeof(AudioObjectID));
    if(AudioObjectGetPropertyData(object,&a,0,nullptr,&size,ids.data())!=noErr) return @[];
    NSMutableArray *result=[NSMutableArray new]; for(UInt32 i=0;i<size/sizeof(AudioObjectID);i++) [result addObject:@(ids[i])]; return result;
}
static NSString* stringValue(AudioObjectID object, AudioObjectPropertySelector selector) {
    CFStringRef s=nullptr; auto a=address(selector); UInt32 size=sizeof(s);
    if(AudioObjectGetPropertyData(object,&a,0,nullptr,&size,&s)!=noErr || !s) return @"";
    return CFBridgingRelease(s);
}
static UInt32 channelCount(AudioObjectID object, AudioObjectPropertyScope scope) {
    auto a=address(kAudioDevicePropertyStreamConfiguration,scope); UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(object,&a,0,nullptr,&size)!=noErr || !size) return 0;
    std::vector<uint8_t> bytes(size); auto list=(AudioBufferList*)bytes.data();
    if(AudioObjectGetPropertyData(object,&a,0,nullptr,&size,list)!=noErr) return 0;
    UInt32 n=0; for(UInt32 i=0;i<list->mNumberBuffers;i++) n+=list->mBuffers[i].mNumberChannels; return n;
}
static NSString* statusText(NSString* step, OSStatus status) { return [NSString stringWithFormat:@"%@: Core Audio %d",step,(int)status]; }
struct Lane {
    AudioObjectID tap=0, device=0;
    AudioDeviceIOProcID io=nullptr;
    std::atomic<float> target{1}, peak{0}, rms{0};
    std::atomic<uint64_t> callbacks{0}, frames{0};
    std::atomic<bool> render{false};
    FaderGain gain;
    UInt32 tapChannels=2;
    bool controlled=false;
    double sampleRate=48000;
    CATapDescription *description=nil;
    NSArray<NSNumber*> *processes=nil;
    AudioObjectID source=0;
    NSString *error=nil;
    ~Lane() { stop(); }
    void stop() {
        // Stopping the IO first restores the original app's sound automatically.
        if(device && io) { AudioDeviceStop(device,io); AudioDeviceDestroyIOProcID(device,io); io=nullptr; }
        if(device) { AudioHardwareDestroyAggregateDevice(device); device=0; }
        if(tap) { AudioHardwareDestroyProcessTap(tap); tap=0; }
    }
};
static OSStatus audioIO(AudioObjectID, const AudioTimeStamp*, const AudioBufferList* input, const AudioTimeStamp*, AudioBufferList* output, const AudioTimeStamp*, void* context) {
    auto &lane=*(Lane*)context;
    if(output) for(UInt32 b=0;b<output->mNumberBuffers;b++) if(output->mBuffers[b].mData) memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    if(!input || !input->mNumberBuffers) return noErr;
    // Physical input streams precede the tap in an aggregate. Read only its last channels.
    UInt32 total=0; for(UInt32 b=0;b<input->mNumberBuffers;b++) total+=input->mBuffers[b].mNumberChannels;
    UInt32 skip=total>lane.tapChannels?total-lane.tapChannels:0;
    const float *channels[32]={}; UInt32 strides[32]={}; UInt32 count=0, frames=UINT32_MAX, before=0;
    for(UInt32 b=0;b<input->mNumberBuffers;b++) {
        const auto &buf=input->mBuffers[b];
        if(buf.mData && buf.mNumberChannels) for(UInt32 ch=0;ch<buf.mNumberChannels && count<32;ch++) if(before+ch>=skip) {
            channels[count]=(const float*)buf.mData+ch; strides[count]=buf.mNumberChannels; count++;
            frames=std::min(frames,buf.mDataByteSize/(UInt32)(sizeof(float)*buf.mNumberChannels));
        }
        before+=buf.mNumberChannels;
    }
    if(!count || frames==UINT32_MAX) return noErr;
    const bool render=lane.render.load(std::memory_order_relaxed);
    const float target=lane.target.load(std::memory_order_relaxed);
    const float smoothing=1.0f-std::exp(-1.0f/(0.008f*(float)lane.sampleRate));
    float peak=0; double square=0;
    UInt32 outFrames=frames;
    if(output) for(UInt32 b=0;b<output->mNumberBuffers;b++) if(output->mBuffers[b].mNumberChannels && output->mBuffers[b].mData) outFrames=std::min(outFrames,output->mBuffers[b].mDataByteSize/(UInt32)(sizeof(float)*output->mBuffers[b].mNumberChannels));
    for(UInt32 f=0;f<frames;f++) {
        float g=lane.gain.step(target,smoothing);
        for(UInt32 ch=0;ch<count;ch++) { float s=channels[ch][f*strides[ch]]; if(std::isfinite(s)) { peak=std::max(peak,std::abs(s)); square+=(double)s*s; } }
        if(render && output && f<outFrames) {
            UInt32 channel=0;
            for(UInt32 b=0;b<output->mNumberBuffers;b++) {
                auto &buf=output->mBuffers[b]; auto data=(float*)buf.mData;
                for(UInt32 ch=0;ch<buf.mNumberChannels;ch++,channel++) if(data) {
                    if(channel<count) data[f*buf.mNumberChannels+ch]=faderSample(channels[channel][f*strides[channel]],g);
                    else data[f*buf.mNumberChannels+ch]=0;
                }
            }
        }
    }
    float previous=lane.peak.load(std::memory_order_relaxed);
    while(previous<peak && !lane.peak.compare_exchange_weak(previous,peak,std::memory_order_relaxed)) {}
    lane.rms.store(std::sqrt(square/(frames*count)),std::memory_order_relaxed);
    lane.frames.fetch_add(frames,std::memory_order_relaxed); lane.callbacks.fetch_add(1,std::memory_order_relaxed);
    return noErr;
}

@implementation FaderAudio { std::map<std::string,std::unique_ptr<Lane>> _lanes; }
- (NSArray<NSDictionary*>*)applications {
    NSMutableDictionary<NSString*,NSMutableDictionary*> *groups=[NSMutableDictionary new];
    for(NSNumber *n in objects(kAudioObjectSystemObject,kAudioHardwarePropertyProcessObjectList)) {
        AudioObjectID object=n.unsignedIntValue; pid_t pid=value<pid_t>(object,kAudioProcessPropertyPID);
        if(pid==getpid() || pid<=0) continue;
        BOOL active=value<UInt32>(object,kAudioProcessPropertyIsRunningOutput)!=0;
        NSArray *devices=objects(object,kAudioProcessPropertyDevices,kAudioObjectPropertyScopeOutput);
        if(!active && !devices.count) continue;
        NSRunningApplication *running=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        NSString *bundle=stringValue(object,kAudioProcessPropertyBundleID);
        char path[PROC_PIDPATHINFO_MAXSIZE]={}; proc_pidpath(pid,path,sizeof(path));
        NSString *executable=path[0]?[NSString stringWithUTF8String:path]:@"";
        NSString *appPath=running.bundleURL.path ?: @"";
        NSRange end=[executable rangeOfString:@".app/"];
        if(end.location!=NSNotFound) appPath=[executable substringToIndex:end.location+4];
        NSBundle *app=appPath.length?[NSBundle bundleWithPath:appPath]:nil;
        NSString *key=app.bundleIdentifier ?: (bundle.length?bundle:[NSString stringWithFormat:@"pid.%d",pid]);
        if([key hasPrefix:@"dev.ybivashhka.fader"]) continue;
        NSString *name=[app objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [app objectForInfoDictionaryKey:@"CFBundleName"] ?: running.localizedName ?: executable.lastPathComponent;
        if(!name.length) name=bundle.length?bundle:@"Аудиопроцесс";
        NSMutableDictionary *g=groups[key];
        if(!g) { g=[@{@"key":key,@"name":name,@"path":appPath,@"processes":[NSMutableArray new],@"devices":[NSMutableArray new],@"active":@NO} mutableCopy]; groups[key]=g; }
        [g[@"processes"] addObject:n];
        for(NSNumber *d in devices) if(![g[@"devices"] containsObject:d]) [g[@"devices"] addObject:d];
        if(active) g[@"active"]=@YES;
    }
    return [[groups allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}
- (NSArray<NSDictionary*>*)outputDevices {
    NSMutableArray *result=[NSMutableArray new];
    for(NSNumber *n in objects(kAudioObjectSystemObject,kAudioHardwarePropertyDevices)) {
        AudioObjectID d=n.unsignedIntValue;
        NSString *uid=stringValue(d,kAudioDevicePropertyDeviceUID);
        if([uid hasPrefix:@"dev.ybivashhka.fader."] || !channelCount(d,kAudioObjectPropertyScopeOutput)) continue;
        [result addObject:@{@"id":n,@"uid":uid,@"name":stringValue(d,kAudioObjectPropertyName),@"transport":@(value<UInt32>(d,kAudioDevicePropertyTransportType))}];
    } return result;
}
- (uint32_t)defaultOutput { return value<AudioObjectID>(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice); }
- (BOOL)setDefaultOutput:(uint32_t)device {
    auto a=address(kAudioHardwarePropertyDefaultOutputDevice);
    return AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,sizeof(device),&device)==noErr;
}
- (float)masterVolume {
    AudioObjectID d=self.defaultOutput; auto a=address(kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput);
    if(AudioObjectHasProperty(d,&a)) return value<Float32>(d,kAudioDevicePropertyVolumeScalar,-1,kAudioObjectPropertyScopeOutput);
    float left=value<Float32>(d,kAudioDevicePropertyVolumeScalar,-1,kAudioObjectPropertyScopeOutput,1);
    float right=value<Float32>(d,kAudioDevicePropertyVolumeScalar,left,kAudioObjectPropertyScopeOutput,2);
    return left<0?-1:(left+right)*0.5f;
}
- (BOOL)setMasterVolume:(float)volume {
    Float32 v=std::clamp(volume,0.f,1.f); AudioObjectID d=self.defaultOutput;
    auto a=address(kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput); Boolean settable=false;
    if(AudioObjectIsPropertySettable(d,&a,&settable)==noErr && settable) return AudioObjectSetPropertyData(d,&a,0,nullptr,sizeof(v),&v)==noErr;
    bool success=false;
    for(UInt32 ch=1;ch<=2;ch++) { a=address(kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput,ch); if(AudioObjectIsPropertySettable(d,&a,&settable)==noErr && settable) success|=AudioObjectSetPropertyData(d,&a,0,nullptr,sizeof(v),&v)==noErr; }
    return success;
}
- (NSString*)connect:(NSString*)key processes:(NSArray<NSNumber*>*)processes device:(uint32_t)source volume:(float)volume muted:(BOOL)muted {
    std::string k=key.UTF8String; auto found=_lanes.find(k);
    if(found!=_lanes.end() && found->second->source==source && [found->second->processes isEqual:processes]) { [self setVolume:volume muted:muted forKey:key]; return nil; }
    _lanes.erase(k);
    if(!source || !processes.count) return @"Нет доступного аудиовыхода";
    auto lane=std::make_unique<Lane>(); lane->source=source; lane->processes=processes; lane->target.store(muted?0:std::clamp(volume,0.f,1.f)); lane->gain.current=lane->target.load();
    NSString *uid=stringValue(source,kAudioDevicePropertyDeviceUID);
    CATapDescription *desc=[[CATapDescription alloc] initWithProcesses:processes andDeviceUID:uid withStream:0];
    desc.name=[@"Fader · " stringByAppendingString:key]; desc.privateTap=YES; desc.muteBehavior=CATapUnmuted;
    lane->description=desc;
    NSLog(@"Fader connecting %@",key);
    OSStatus status=AudioHardwareCreateProcessTap(desc,&lane->tap);
    NSLog(@"Fader tap %@: %d",key,(int)status);
    if(status!=noErr) return statusText(@"Не удалось подключить приложение",status);
    auto format=value<AudioStreamBasicDescription>(lane->tap,kAudioTapPropertyFormat);
    if(format.mFormatID!=kAudioFormatLinearPCM || !(format.mFormatFlags&kAudioFormatFlagIsFloat) || format.mBitsPerChannel!=32 || format.mChannelsPerFrame>32) return @"Этот формат аудиовыхода пока не поддерживается";
    lane->tapChannels=format.mChannelsPerFrame; lane->sampleRate=format.mSampleRate;
    NSDictionary *config=@{@kAudioAggregateDeviceNameKey:[@"Fader · " stringByAppendingString:key],@kAudioAggregateDeviceUIDKey:[@"dev.ybivashhka.fader." stringByAppendingString:NSUUID.UUID.UUIDString],@kAudioAggregateDeviceIsPrivateKey:@YES,@kAudioAggregateDeviceIsStackedKey:@NO,@kAudioAggregateDeviceMainSubDeviceKey:uid,@kAudioAggregateDeviceSubDeviceListKey:@[@{@kAudioSubDeviceUIDKey:uid,@kAudioSubDeviceInputChannelsKey:@0}],@kAudioAggregateDeviceTapListKey:@[@{@kAudioSubTapUIDKey:desc.UUID.UUIDString,@kAudioSubTapDriftCompensationKey:@YES}],@kAudioAggregateDeviceTapAutoStartKey:@NO};
    status=AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config,&lane->device);
    NSLog(@"Fader aggregate %@: %d, channels %u rate %.0f",key,(int)status,format.mChannelsPerFrame,format.mSampleRate);
    if(status!=noErr) return statusText(@"Не удалось создать аудиоканал",status);
    status=AudioDeviceCreateIOProcID(lane->device,audioIO,lane.get(),&lane->io);
    NSLog(@"Fader IO %@: %d",key,(int)status);
    if(status!=noErr) return statusText(@"Не удалось подключить обработку",status);
    status=AudioDeviceStart(lane->device,lane->io);
    NSLog(@"Fader start %@: %d",key,(int)status);
    if(status!=noErr) return statusText(@"Не удалось запустить канал",status);
    _lanes[k]=std::move(lane); return nil;
}
- (void)setVolume:(float)volume muted:(BOOL)muted forKey:(NSString*)key { auto i=_lanes.find(key.UTF8String); if(i!=_lanes.end()) i->second->target.store(muted?0:std::clamp(volume,0.f,1.f)); }
- (NSDictionary*)meterForKey:(NSString*)key {
    auto i=_lanes.find(key.UTF8String); if(i==_lanes.end()) return @{@"peak":@0,@"rms":@0,@"controlled":@NO,@"callbacks":@0};
    Lane &lane=*i->second; float peak=lane.peak.exchange(0);
    // Only take over after real audio arrives: denied capture permission must never silence an app.
    if(!lane.controlled && peak>0.000001f) {
        lane.render.store(true); lane.description.muteBehavior=CATapMutedWhenTapped;
        auto a=address(kAudioTapPropertyDescription); CATapDescription *desc=lane.description;
        OSStatus s=AudioObjectSetPropertyData(lane.tap,&a,0,nullptr,sizeof(desc),&desc);
        if(s==noErr) lane.controlled=true;
        else { lane.render.store(false); lane.description.muteBehavior=CATapUnmuted; lane.error=statusText(@"Нет управления звуком",s); }
    }
    float gain=lane.controlled?lane.target.load():1;
    return @{@"peak":@(peak*gain),@"inputPeak":@(peak),@"rms":@(lane.rms.load()*gain),@"controlled":@(lane.controlled),@"callbacks":@(lane.callbacks.load()),@"frames":@(lane.frames.load()),@"error":lane.error ?: @""};
}
- (void)disconnect:(NSString*)key { _lanes.erase(key.UTF8String); }
- (void)stopAll { _lanes.clear(); }
- (void)dealloc { _lanes.clear(); }
@end
