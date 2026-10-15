#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <complex>

namespace sound {
constexpr int bands = 10;
constexpr std::array<double, bands> frequencies{31.25,62.5,125,250,500,1000,2000,4000,8000,16000};
struct Biquad {
    double b0=1,b1=0,b2=0,a1=0,a2=0;
    double z1[2]{}, z2[2]{};
    void tune(double hz, double db, double rate) {
        hz=std::min(hz,rate*0.45);
        const double A=std::pow(10.,db/40.), w=2*M_PI*hz/rate;
        const double alpha=std::sin(w)/(2*1.4), a0=1+alpha/A;
        b0=(1+alpha*A)/a0; b1=-2*std::cos(w)/a0; b2=(1-alpha*A)/a0;
        a1=b1; a2=(1-alpha/A)/a0;
    }
    double tick(double x, int ch) {
        double y=b0*x+z1[ch]; z1[ch]=b1*x-a1*y+z2[ch]; z2[ch]=b2*x-a2*y;
        // Flush tiny states instead of spending CPU on denormals.
        if(std::abs(z1[ch])<1e-25) z1[ch]=0;
        if(std::abs(z2[ch])<1e-25) z2[ch]=0;
        return y;
    }
    double magnitude(double w) const {
        auto z=std::polar(1.,-w);
        return std::abs((b0+b1*z+b2*z*z)/(1.+a1*z+a2*z*z));
    }
};
// UI writes atomic targets. All filter state belongs exclusively to the audio thread.
class DSP {
    std::array<std::atomic<float>,bands> target{};
    std::array<float,bands> current{};
    std::array<Biquad,bands> filters{};
    double rate=48000, preamp=1, basePreamp=1, desiredPreamp=1, envelope=1, fade=0;
    std::atomic<bool> loudnessBoost{false};
    std::atomic<float> outputDB{0};
    std::atomic<float> speakerAmount{0};
    double speakerMix=0, bassEnvelope=.001, bassAlpha=0, dcAlpha=0, harmonicHP=0, harmonicLP=0;
    double low1[2]{},low2[2]{},dc[2]{},harmonicLow[2]{},harmonicTop[2]{};
    void updatePreamp() {
        // Volume match removes the full EQ attenuation, including large bass curves.
        // Explicit output gain is independent; the linked limiter always stays active.
        double attenuation=loudnessBoost.load(std::memory_order_relaxed)?1:basePreamp;
        desiredPreamp=attenuation*std::pow(10.,outputDB.load(std::memory_order_relaxed)/20.);
        headroom.store(float(std::max(0.,-20*std::log10(attenuation))),std::memory_order_relaxed);
    }
public:
    std::atomic<float> peak{0}, reduction{0}, headroom{0};
    void set(int band,float gain) {
        if(band>=0 && band<bands && std::isfinite(gain)) target[band].store(std::clamp(gain,-12.f,12.f));
    }
    void setLoudnessBoost(bool enabled) { loudnessBoost.store(enabled,std::memory_order_relaxed); }
    void setOutputGain(float db) { outputDB.store(std::isfinite(db)?std::clamp(db,-12.f,12.f):0,std::memory_order_relaxed); }
    void setSpeakerBass(float amount) { speakerAmount.store(std::isfinite(amount)?std::clamp(amount,0.f,1.f):0,std::memory_order_relaxed); }
    void reset(double sr) {
        rate=sr; filters={}; envelope=1; fade=0;
        speakerMix=speakerAmount.load(); bassEnvelope=.001;
        for(int ch=0;ch<2;ch++) low1[ch]=low2[ch]=dc[ch]=harmonicLow[ch]=harmonicTop[ch]=0;
        bassAlpha=1-std::exp(-2*M_PI*120/rate); dcAlpha=1-std::exp(-2*M_PI*35/rate);
        harmonicHP=1-std::exp(-2*M_PI*180/rate); harmonicLP=1-std::exp(-2*M_PI*700/rate);
        for(int b=0;b<bands;b++) {current[b]=target[b].load(); filters[b].tune(frequencies[b],current[b],rate);}
        calculateHeadroom(); updatePreamp(); preamp=desiredPreamp;
    }
    void calculateHeadroom() {
        double maximum=1;
        for(int i=0;i<=512;i++) {
            double hz=10*std::pow(rate*.05,i/512.);
            double w=2*M_PI*hz/rate, magnitude=1;
            for(auto &f:filters) magnitude*=f.magnitude(w);
            maximum=std::max(maximum,magnitude);
        }
        basePreamp=1/maximum;
    }
    void begin(unsigned frames) {
        bool changed=false;
        const float smooth=1-std::exp(-double(frames)/(rate*.025));
        for(int b=0;b<bands;b++) {
            float t=target[b].load(std::memory_order_relaxed);
            if(std::abs(t-current[b])>.001f) {
                current[b]+=(t-current[b])*smooth;
                filters[b].tune(frequencies[b],current[b],rate); changed=true;
            }
        }
        if(changed) calculateHeadroom();
        updatePreamp();
        speakerMix+=(speakerAmount.load(std::memory_order_relaxed)-speakerMix)*smooth;
    }
    void frame(float &left,float &right) {
        preamp+=(desiredPreamp-preamp)*(1-std::exp(-1/(rate*.01)));
        double l=std::isfinite(left)?left*preamp:0, r=std::isfinite(right)?right*preamp:0;
        double bass[2];
        const double dry[2]{l,r};
        for(int ch=0;ch<2;ch++) {
            low1[ch]+=bassAlpha*(dry[ch]-low1[ch]);
            low2[ch]+=bassAlpha*(low1[ch]-low2[ch]);
            dc[ch]+=dcAlpha*(low2[ch]-dc[ch]);
            bass[ch]=low2[ch]-dc[ch];
        }
        double bassPeak=std::max(std::abs(bass[0]),std::abs(bass[1]));
        if(bassPeak>bassEnvelope) bassEnvelope=bassPeak;
        else bassEnvelope+=(bassPeak-bassEnvelope)*(1-std::exp(-1/(rate*.15)));
        double added[2]{};
        for(int ch=0;ch<2;ch++) {
            // Parallel harmonic bass: translate some low-bass energy into audible
            // upper harmonics, instead of spending all headroom on inaudible lows.
            double normalized=bass[ch]/std::max(.001,bassEnvelope);
            double shaped=speakerMix>1e-5 ? (std::tanh(3*normalized)-normalized)*bassEnvelope : 0;
            harmonicLow[ch]+=harmonicHP*(shaped-harmonicLow[ch]);
            harmonicTop[ch]+=harmonicLP*((shaped-harmonicLow[ch])-harmonicTop[ch]);
            added[ch]=harmonicTop[ch]*speakerMix;
        }
        for(auto &f:filters) { l=f.tick(l,0); r=f.tick(r,1); }
        l+=added[0]; r+=added[1];
        double p=std::max(std::abs(l),std::abs(r));
        double required=p>.96?.96/p:1;
        if(required<envelope) envelope=required;
        else envelope+=(required-envelope)*(1-std::exp(-1/(rate*.08)));
        fade=std::min(1.,fade+1/(rate*.02));
        left=float(std::clamp(l*envelope*fade,-.96,.96));
        right=float(std::clamp(r*envelope*fade,-.96,.96));
        peak.store(std::max(std::abs(left),std::abs(right)),std::memory_order_relaxed);
        reduction.store(float(-20*std::log10(std::max(envelope,1e-9))),std::memory_order_relaxed);
    }
};
}
