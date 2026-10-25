#include "../Sources/FaderDSP.h"
#include <cassert>
#include <iostream>
#include <limits>
int main() {
    assert(faderSample(0.8f,0.5f)==0.4f);
    assert(faderSample(-0.8f,0.5f)==-0.4f);
    assert(faderSample(0.7f,0)==0);
    assert(faderSample(std::numeric_limits<float>::quiet_NaN(),1)==0);
    assert(faderSample(std::numeric_limits<float>::infinity(),1)==0);
    assert(faderSample(2,1)==1);
    FaderGain gain; float previous=1;
    for(int i=0;i<4800;i++) { auto v=gain.step(0,1-std::exp(-1.f/(0.008f*48000))); assert(v<=previous && v>=0); assert(previous-v<0.003f); previous=v; }
    assert(gain.current<0.00001f);
    for(int i=0;i<4800;i++) gain.step(0.6f,1-std::exp(-1.f/(0.008f*48000)));
    assert(std::abs(gain.current-0.6f)<0.00001f);
    std::cout<<"DSP: attenuation, mute, invalid samples, clipping, smooth ramp and restore passed\n";
}
