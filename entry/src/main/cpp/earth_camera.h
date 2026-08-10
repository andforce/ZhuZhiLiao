#ifndef EARTH_CAMERA_H
#define EARTH_CAMERA_H

#include <cmath>

class EarthCamera {
public:
    float yaw = -1.35f;
    float pitch = 0.18f;
    float distance = 3.25f;
    bool autoRotateEnabled = true;
    long long lastInteractionTime = 0;

    void onTouchDown(float x, float y);
    void onTouchMove(float x, float y);
    void onTouchUp();
    void onPinchUpdate(float dist);
    void onPinchEnd();
    void updateAutoRotate(double delta);

    void getViewMatrix(float *out) const;
    void getProjectionMatrix(float aspect, float *out) const;
    void getGlobeModelMatrix(float *out) const;

    float clampf(float v, float lo, float hi) const {
        return v < lo ? lo : (v > hi ? hi : v);
    }

private:
    float lastX_ = 0, lastY_ = 0;
    bool touching_ = false;
    float lastPinchDist_ = 0;
    bool pinching_ = false;
};

#endif
