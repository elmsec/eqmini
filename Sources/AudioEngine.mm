#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include "AudioBridge.h"
#include "DSP.hpp"
#include <mach/mach_time.h>
#include <vector>
#include <string>
#include <libproc.h>

namespace {
sound::DSP dsp;
AudioObjectID tap=0, aggregate=0;
AudioDeviceIOProcID proc=nullptr;
std::string errorText, outputName;
bool permissionDenied=false;
double sampleRate=0;
AudioDeviceID activeOutput=0;
unsigned inputBufferOffset=0;
std::atomic<uint64_t> heartbeat{0};
std::atomic<uint64_t> renderedFrames{0};
std::atomic<float> inputPeak{0};

AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {
    return {selector,scope,kAudioObjectPropertyElementMain};
}
template<class T> OSStatus read(AudioObjectID object, AudioObjectPropertySelector selector,T &value, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {
    auto a=address(selector,scope); UInt32 size=sizeof(T);
    return AudioObjectGetPropertyData(object,&a,0,nullptr,&size,&value);
}
bool check(OSStatus status,const char *operation) {
    if(!status) return true;
    if(status==kAudioDevicePermissionsError) permissionDenied=true;
    errorText=std::string(operation)+" (Core Audio "+std::to_string(status)+").";
    return false;
}
unsigned streamCount(AudioObjectID device, AudioObjectPropertyScope scope) {
    auto a=address(kAudioDevicePropertyStreams,scope); UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(device,&a,0,nullptr,&bytes)) return 0;
    return bytes/sizeof(AudioStreamID);
}
// No locks, allocation, Objective-C, logging or file access on the render thread.
OSStatus render(AudioObjectID,const AudioTimeStamp*,const AudioBufferList *input,
                const AudioTimeStamp*,AudioBufferList *output,const AudioTimeStamp*,void*) {
    heartbeat.store(mach_absolute_time(),std::memory_order_relaxed);
    for(UInt32 b=0;b<output->mNumberBuffers;b++)
        if(output->mBuffers[b].mData) memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    if(input->mNumberBuffers<=inputBufferOffset || !output->mNumberBuffers) return noErr;
    const AudioBuffer &in=input->mBuffers[inputBufferOffset];
    if(!in.mData || !in.mNumberChannels) return noErr;
    AudioBuffer &out=output->mBuffers[0];
    if(!out.mData || !out.mNumberChannels) return noErr;
    bool planarInput=in.mNumberChannels==1;
    bool planarOutput=out.mNumberChannels==1;
    const float *il=(float*)in.mData;
    const float *ir=il;
    bool hasRightInput=planarInput && input->mNumberBuffers>inputBufferOffset+1 && input->mBuffers[inputBufferOffset+1].mData;
    if(hasRightInput)
        ir=(float*)input->mBuffers[inputBufferOffset+1].mData;
    unsigned frames=std::min(in.mDataByteSize/(4*in.mNumberChannels),out.mDataByteSize/(4*out.mNumberChannels));
    if(hasRightInput) frames=std::min(frames,input->mBuffers[inputBufferOffset+1].mDataByteSize/4);
    float *ol=(float*)out.mData, *orr=nullptr;
    if(planarOutput && output->mNumberBuffers>1) orr=(float*)output->mBuffers[1].mData;
    if(orr) frames=std::min(frames,output->mBuffers[1].mDataByteSize/4);
    dsp.begin(frames);
    float peak=0;
    for(unsigned i=0;i<frames;i++) {
        float l=il[i*in.mNumberChannels];
        float r=planarInput?ir[i]:il[i*in.mNumberChannels+1];
        peak=std::max(peak,std::max(std::abs(l),std::abs(r)));
        dsp.frame(l,r);
        if(planarOutput) {ol[i]=orr?l:(l+r)*.5f; if(orr) orr[i]=r;}
        else {ol[i*out.mNumberChannels]=l; ol[i*out.mNumberChannels+1]=r;}
    }
    renderedFrames.fetch_add(frames,std::memory_order_relaxed);
    inputPeak.store(std::max(inputPeak.load(std::memory_order_relaxed),peak),std::memory_order_relaxed);
    return noErr;
}
bool validateStreams(AudioObjectID device,AudioObjectPropertyScope scope) {
    auto a=address(kAudioDevicePropertyStreams,scope); UInt32 bytes=0;
    if(!check(AudioObjectGetPropertyDataSize(device,&a,0,nullptr,&bytes),"Read audio streams")) return false;
    std::vector<AudioStreamID> streams(bytes/sizeof(AudioStreamID));
    if(!check(AudioObjectGetPropertyData(device,&a,0,nullptr,&bytes,streams.data()),"Read stream list")) return false;
    // On input, only the final tap stream is used; hardware inputs are disabled below.
    if(streams.empty()) {errorText="The audio route has no streams."; return false;}
    unsigned first=scope==kAudioObjectPropertyScopeInput?unsigned(streams.size()-1):0;
    if(scope==kAudioObjectPropertyScopeInput) {
        inputBufferOffset=0;
        for(unsigned i=0;i<first;i++) {
            AudioStreamBasicDescription prior{};
            if(!check(read(streams[i],kAudioStreamPropertyVirtualFormat,prior),"Read input layout")) return false;
            inputBufferOffset+=(prior.mFormatFlags & kAudioFormatFlagIsNonInterleaved)?prior.mChannelsPerFrame:1;
        }
    }
    for(unsigned i=first;i<streams.size();i++) {
        AudioStreamBasicDescription format{};
        if(!check(read(streams[i],kAudioStreamPropertyVirtualFormat,format),"Read audio format")) return false;
        if(format.mFormatID!=kAudioFormatLinearPCM || !(format.mFormatFlags & kAudioFormatFlagIsFloat) || format.mBitsPerChannel!=32) {
            errorText="This output does not support 32-bit floating-point audio."; return false;
        }
        if(format.mChannelsPerFrame<1 || format.mChannelsPerFrame>2) {
            errorText="Choose a mono or stereo output device. Surround outputs are not supported yet."; return false;
        }
    }
    return true;
}
}

unsigned EQDefaultOutput() {
    AudioDeviceID device=0; read(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,device); return device;
}
void EQStop() {
    if(aggregate && proc) {AudioDeviceStop(aggregate,proc); AudioDeviceDestroyIOProcID(aggregate,proc);}
    proc=nullptr;
    if(aggregate) AudioHardwareDestroyAggregateDevice(aggregate);
    aggregate=0;
    if(tap) AudioHardwareDestroyProcessTap(tap);
    tap=0; heartbeat.store(0); sampleRate=0; activeOutput=0;
}
static bool startAudio(NSArray<NSNumber*> *includedProcesses) {
    EQStop(); errorText.clear(); permissionDenied=false;
    @autoreleasepool {
        AudioDeviceID output=EQDefaultOutput(); activeOutput=output;
        if(!output) {errorText="No output device is available."; return false;}
        CFStringRef uid=nullptr, name=nullptr;
        if(!check(read(output,kAudioDevicePropertyDeviceUID,uid),"Read output device")) return false;
        NSString *outputUID=CFBridgingRelease(uid);
        outputName="System output";
        if(!read(output,kAudioObjectPropertyName,name) && name) outputName=[CFBridgingRelease(name) UTF8String];
        pid_t pid=getpid(); AudioObjectID ownProcess=0; UInt32 size=sizeof(ownProcess);
        auto processAddress=address(kAudioHardwarePropertyTranslatePIDToProcessObject);
        if(!check(AudioObjectGetPropertyData(kAudioObjectSystemObject,&processAddress,sizeof(pid),&pid,&size,&ownProcess),"Identify audio process")) return false;
        if(!ownProcess) {errorText="Could not exclude the equalizer from audio capture."; return false;}
        // Device-specific tap preserves normal per-output routing and system volume behavior.
        CATapDescription *description;
        if(includedProcesses) {
            NSMutableArray<NSNumber*> *safeProcesses=[includedProcesses mutableCopy];
            [safeProcesses removeObject:@(ownProcess)];
            if(!safeProcesses.count) {errorText="No selected audio apps are available."; return false;}
            description=[[CATapDescription alloc] initWithProcesses:safeProcesses andDeviceUID:outputUID withStream:0];
        } else {
            description=[[CATapDescription alloc] initExcludingProcesses:@[@(ownProcess)] andDeviceUID:outputUID withStream:0];
        }
        description.name=@"eqmini"; description.privateTap=YES;
        description.muteBehavior=CATapMutedWhenTapped;
        if(!check(AudioHardwareCreateProcessTap(description,&tap),"Create system audio tap")) {EQStop(); return false;}
        NSDictionary *composition=@{
            @kAudioAggregateDeviceNameKey:@"eqmini Private Output",
            @kAudioAggregateDeviceUIDKey:[[NSUUID UUID] UUIDString],
            @kAudioAggregateDeviceIsPrivateKey:@YES,
            @kAudioAggregateDeviceIsStackedKey:@NO,
            @kAudioAggregateDeviceMainSubDeviceKey:outputUID,
            @kAudioAggregateDeviceSubDeviceListKey:@[@{@kAudioSubDeviceUIDKey:outputUID,@kAudioSubDeviceInputChannelsKey:@0}],
            @kAudioAggregateDeviceTapListKey:@[@{@kAudioSubTapUIDKey:description.UUID.UUIDString,@kAudioSubTapDriftCompensationKey:@YES}],
            @kAudioAggregateDeviceTapAutoStartKey:@YES
        };
        if(!check(AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition,&aggregate),"Create private audio route")) {EQStop(); return false;}
        if(!check(read(aggregate,kAudioDevicePropertyNominalSampleRate,sampleRate),"Read sample rate") || !std::isfinite(sampleRate) || sampleRate<8000 ||
           !validateStreams(aggregate,kAudioObjectPropertyScopeInput) || !validateStreams(aggregate,kAudioObjectPropertyScopeOutput)) {EQStop(); return false;}
        dsp.reset(sampleRate);
        if(!check(AudioDeviceCreateIOProcID(aggregate,render,nullptr,&proc),"Create audio renderer")) {EQStop(); return false;}
        unsigned count=streamCount(aggregate,kAudioObjectPropertyScopeInput);
        if(!count) {errorText="The system audio tap has no input stream."; EQStop(); return false;}
        std::vector<uint8_t> storage(offsetof(AudioHardwareIOProcStreamUsage,mStreamIsOn)+count*sizeof(UInt32));
        auto *usage=(AudioHardwareIOProcStreamUsage*)storage.data();
        usage->mIOProc=(void*)proc; usage->mNumberStreams=count;
        for(unsigned i=0;i<count;i++) usage->mStreamIsOn[i]=(i==count-1);
        auto usageAddress=address(kAudioDevicePropertyIOProcStreamUsage,kAudioObjectPropertyScopeInput);
        if(!check(AudioObjectSetPropertyData(aggregate,&usageAddress,0,nullptr,UInt32(storage.size()),usage),"Disable hardware input streams")) {EQStop(); return false;}
        renderedFrames.store(0); inputPeak.store(0); heartbeat.store(mach_absolute_time());
        if(!check(AudioDeviceStart(aggregate,proc),"Start system audio")) {EQStop(); return false;}
        return true;
    }
}
bool EQStart() { return startAudio(nil); }
bool EQStartSelected(const unsigned int *processes,unsigned int count) {
    @autoreleasepool {
        NSMutableArray<NSNumber*> *included=[NSMutableArray array];
        if(processes) for(unsigned i=0;i<count;i++) [included addObject:@(processes[i])];
        return startAudio(included);
    }
}
bool EQTapMatchesSelected(const unsigned int *processes,unsigned int count) {
    @autoreleasepool {
        if(!tap || !processes || !count) return false;
        CFTypeRef raw=nullptr;
        if(read(tap,kAudioTapPropertyDescription,raw) || !raw) return false;
        CATapDescription *description=CFBridgingRelease(raw);
        NSMutableSet *expected=[NSMutableSet set];
        for(unsigned i=0;i<count;i++) [expected addObject:@(processes[i])];
        return !description.isExclusive && [[NSSet setWithArray:description.processes] isEqualToSet:expected];
    }
}
const char *EQAudioProcessesJSON() {
    static std::string result;
    @autoreleasepool {
        auto property=address(kAudioHardwarePropertyProcessObjectList);
        UInt32 bytes=0;
        OSStatus status=AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&property,0,nullptr,&bytes);
        std::vector<AudioObjectID> processes(bytes/sizeof(AudioObjectID));
        if(!status && bytes) status=AudioObjectGetPropertyData(kAudioObjectSystemObject,&property,0,nullptr,&bytes,processes.data());
        NSMutableArray *items=[NSMutableArray array];
        AudioDeviceID outputDevice=EQDefaultOutput();
        if(!status) for(AudioObjectID object:processes) {
            pid_t pid=0;
            if(read(object,kAudioProcessPropertyPID,pid) || pid==getpid()) continue;
            CFStringRef raw=nullptr;
            NSString *bundleID=@"";
            if(!read(object,kAudioProcessPropertyBundleID,raw) && raw) bundleID=CFBridgingRelease(raw);
            NSString *rawBundleID=bundleID;
            NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            NSString *name=app.localizedName;
            // Chromium-style audio helpers live inside their owning app bundle.
            // Resolve that exact bundle rather than matching broad ID prefixes.
            char path[PROC_PIDPATHINFO_MAXSIZE]{};
            if(proc_pidpath(pid,path,sizeof(path))>0) {
                NSString *executable=[NSString stringWithUTF8String:path];
                NSString *parent=@"/";
                for(NSString *part in executable.pathComponents) {
                    parent=[parent stringByAppendingPathComponent:part];
                    if([parent.pathExtension isEqualToString:@"app"]) {
                        NSBundle *owner=[NSBundle bundleWithPath:parent];
                        if(owner.bundleIdentifier) {
                            bundleID=owner.bundleIdentifier;
                            name=[owner objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [owner objectForInfoDictionaryKey:@"CFBundleName"] ?: parent.lastPathComponent.stringByDeletingPathExtension;
                        }
                        break;
                    }
                }
            }
            if(!bundleID.length) bundleID=app.bundleIdentifier ?: @"";
            if(!bundleID.length || [bundleID isEqualToString:NSBundle.mainBundle.bundleIdentifier]) continue;
            UInt32 runningOutput=0;
            OSStatus runningStatus=read(object,kAudioProcessPropertyIsRunningOutput,runningOutput);
            if(!runningStatus && runningOutput) {
                auto devicesAddress=address(kAudioProcessPropertyDevices,kAudioObjectPropertyScopeOutput);
                UInt32 deviceBytes=0;
                runningStatus=AudioObjectGetPropertyDataSize(object,&devicesAddress,0,nullptr,&deviceBytes);
                std::vector<AudioObjectID> devices(deviceBytes/sizeof(AudioObjectID));
                if(!runningStatus && deviceBytes)
                    runningStatus=AudioObjectGetPropertyData(object,&devicesAddress,0,nullptr,&deviceBytes,devices.data());
                if(!runningStatus)
                    runningOutput=std::find(devices.begin(),devices.end(),outputDevice)!=devices.end();
            }
            // Unknown activity must not cause a watchdog failure.
            id activity=runningStatus ? (id)[NSNull null] : @(runningOutput!=0);
            [items addObject:@{@"runningOutput":activity,@"id":@(object),@"pid":@(pid),@"bundleID":bundleID,@"rawBundleID":rawBundleID,@"name":name ?: bundleID}];
        }
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"processes":items,@"status":@(status)} options:0 error:nil];
        result=json?std::string((const char*)json.bytes,json.length):"{\"processes\":[],\"status\":-1}";
        return result.c_str();
    }
}
void EQSetBand(int band,float gain) {dsp.set(band,gain);}
void EQSetLoudnessBoost(bool enabled) {dsp.setLoudnessBoost(enabled);}
void EQSetOutputGain(float db) {dsp.setOutputGain(db);}
void EQSetSpeakerBass(float amount) {dsp.setSpeakerBass(amount);}
bool EQPermissionDenied() {return permissionDenied;}
const char *EQError() {return errorText.c_str();}
const char *EQOutputName() {return outputName.c_str();}
double EQSampleRate() {return sampleRate;}
bool EQHealthy() {
    uint64_t last=heartbeat.load(); if(!last) return false;
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    return double(mach_absolute_time()-last)*timebase.numer/timebase.denom/1e9<3;
}
float EQHeadroom() {return dsp.headroom.load();}
float EQReduction() {return dsp.reduction.load();}
unsigned long long EQRenderedFrames() {return renderedFrames.load();}
float EQInputPeak() {return inputPeak.load();}
bool EQOutputChanged() {
    if(EQDefaultOutput()!=activeOutput) return true;
    double rate=0; UInt32 alive=0;
    return read(activeOutput,kAudioDevicePropertyDeviceIsAlive,alive) || !alive ||
           read(activeOutput,kAudioDevicePropertyNominalSampleRate,rate) || std::abs(rate-sampleRate)>.1;
}
