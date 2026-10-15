#include "../Sources/DSP.hpp"
#include <cassert>
#include <iostream>
#include <limits>

double measure(sound::DSP &dsp, double hz, double rate, float amplitude=.05f) {
    double energy=0;
    for(int block=0;block<400;block++) {
        dsp.begin(256);
        for(int i=0;i<256;i++) {
            float l=amplitude*std::sin(2*M_PI*hz*(block*256+i)/rate),r=l;
            dsp.frame(l,r);
            assert(std::isfinite(l) && std::isfinite(r));
            assert(std::abs(l)<=.960001 && std::abs(r)<=.960001);
            assert(std::abs(l-r)<1e-6);
            if(block>=200) energy+=l*l;
        }
    }
    return std::sqrt(energy/(200*256));
}
double thirdHarmonic(sound::DSP &dsp, double rate) {
    double real=0,imaginary=0;
    const int samples=int(rate)*3;
    for(int i=0;i<samples;i++) {
        if(i%256==0) dsp.begin(256);
        float l=.1*std::sin(2*M_PI*60*i/rate),r=0;
        dsp.frame(l,r);
        assert(std::abs(l)<=.960001 && std::abs(r)<=.960001);
        if(i>=int(rate)*2) {
            assert(std::abs(r)<1e-6);
            real+=l*std::cos(2*M_PI*180*i/rate);
            imaginary+=l*std::sin(2*M_PI*180*i/rate);
        }
    }
    return 2*std::hypot(real,imaginary)/rate;
}
int main() {
    for(double rate:{44100.,48000.,96000.}) {
        sound::DSP flat; flat.reset(rate);
        double unity=measure(flat,1000,rate);
        assert(std::abs(unity-(.05/std::sqrt(2)))<.0001);
        sound::DSP bass; bass.set(2,6); bass.reset(rate);
        double low=measure(bass,125,rate),mid=measure(bass,1000,rate);
        // A +6 dB 125 Hz band must produce a clear bass/mid contrast even with auto headroom.
        assert(20*std::log10(low/mid)>5.5);
        assert(bass.headroom.load()>5.8 && bass.headroom.load()<6.1);
        bass.setLoudnessBoost(true);
        double louderMid=measure(bass,1000,rate);
        assert(20*std::log10(louderMid/mid)>5.8);
        assert(bass.headroom.load()<.1);
        measure(bass,125,rate,1); // Compensated boosts must still be limited.
        bass.setLoudnessBoost(false);
        double restoredMid=measure(bass,1000,rate);
        assert(std::abs(restoredMid-mid)<.0001);
        flat.setLoudnessBoost(true);
        assert(std::abs(measure(flat,1000,rate)-unity)<.0001);
        flat.setOutputGain(6);
        assert(std::abs(20*std::log10(measure(flat,1000,rate)/unity)-6)<.05);
        flat.setOutputGain(100);
        assert(std::abs(20*std::log10(measure(flat,1000,rate)/unity)-12)<.05);
        flat.setOutputGain(std::numeric_limits<float>::quiet_NaN());
        assert(std::abs(measure(flat,1000,rate)-unity)<.0001);
        sound::DSP largeBoost;
        largeBoost.set(2,10); largeBoost.set(3,8); largeBoost.reset(rate);
        double attenuated=measure(largeBoost,1000,rate,.01);
        float originalHeadroom=largeBoost.headroom.load();
        assert(originalHeadroom>10);
        largeBoost.setLoudnessBoost(true);
        double compensated=measure(largeBoost,1000,rate,.01);
        // Compensation must recover the ENTIRE attenuation, including more than 6 dB.
        assert(std::abs(20*std::log10(compensated/attenuated)-originalHeadroom)<.05);
        assert(largeBoost.headroom.load()<.001);
        largeBoost.setOutputGain(12);
        measure(largeBoost,125,rate,4);
        sound::DSP speakerBass;
        const float speakerPreset[]{0,3,8,5,0,-1,0,1,0,0};
        for(int b=0;b<10;b++) speakerBass.set(b,speakerPreset[b]);
        speakerBass.setLoudnessBoost(true); speakerBass.reset(rate);
        double bassLevel=measure(speakerBass,125,rate,.01), vocalLevel=measure(speakerBass,1000,rate,.01);
        assert(20*std::log10(bassLevel/vocalLevel)>8);
        sound::DSP harmonics; harmonics.reset(rate);
        assert(thirdHarmonic(harmonics,rate)<1e-5);
        harmonics.setSpeakerBass(.85);
        assert(thirdHarmonic(harmonics,rate)>.001);
        harmonics.setOutputGain(12);
        harmonics.reset(rate);
        measure(harmonics,60,rate,4);
        harmonics.setSpeakerBass(0);
        harmonics.setOutputGain(0);
        assert(thirdHarmonic(harmonics,rate)<1e-5);
        bass.setLoudnessBoost(true);
        for(int band=0;band<10;band++) bass.set(band,12);
        measure(bass,125,rate,4); // Over-range input still cannot clip output.
        for(int band=0;band<10;band++) bass.set(band,-12);
        measure(bass,16000,rate,1);
        float l=std::numeric_limits<float>::quiet_NaN(),r=std::numeric_limits<float>::infinity();
        bass.frame(l,r); assert(std::isfinite(l) && std::isfinite(r));
        sound::DSP stereo; stereo.reset(rate);
        for(int i=0;i<10000;i++) {float a=.1,b=0; stereo.frame(a,b); assert(b==0);}
        stereo.set(0, std::numeric_limits<float>::quiet_NaN());
        stereo.set(1, std::numeric_limits<float>::infinity());
        stereo.set(-1, 12); stereo.set(10, 12);
        assert(std::abs(measure(stereo,1000,rate)-unity)<.0001);
    }
    std::cout<<"PASS: flat response, speaker bass, full loudness recovery above 6 dB, output gain, clipping, parameter changes, stereo isolation, non-finite input at 44.1/48/96 kHz\n";
}
