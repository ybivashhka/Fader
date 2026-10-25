#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
// A per-frame ramp keeps stereo channels identical and prevents slider clicks.
struct FaderGain {
    float current = 1.0f;
    float step(float target, float coefficient) {
        current += (target-current)*coefficient;
        if (std::abs(current-target)<0.00002f) current=target;
        return current;
    }
};
inline float faderSample(float sample, float gain) {
    if (!std::isfinite(sample)) return 0;
    return std::clamp(sample*gain, -1.0f, 1.0f);
}
