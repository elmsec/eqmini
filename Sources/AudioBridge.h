#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
bool EQStart(void);
bool EQStartSelected(const unsigned int *processes, unsigned int count);
const char *EQAudioProcessesJSON(void);
bool EQTapMatchesSelected(const unsigned int *processes, unsigned int count);
void EQStop(void);
void EQSetBand(int band, float gain);
void EQSetLoudnessBoost(bool enabled);
void EQSetOutputGain(float db);
void EQSetSpeakerBass(float amount);
const char *EQError(void);
const char *EQOutputName(void);
unsigned int EQDefaultOutput(void);
double EQSampleRate(void);
bool EQHealthy(void);
bool EQPermissionDenied(void);
float EQHeadroom(void);
float EQReduction(void);
unsigned long long EQRenderedFrames(void);
float EQInputPeak(void);
bool EQOutputChanged(void);
#ifdef __cplusplus
}
#endif
