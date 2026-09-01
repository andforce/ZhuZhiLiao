#include "earth_camera.h"
#include <cstring>

void EarthCamera::onTouchDown(float x, float y) {
    lastX_ = x; lastY_ = y;
    touching_ = true;
    lastInteractionTime = 0;
}

void EarthCamera::onTouchMove(float x, float y) {
    if (!touching_) return;
    float dx = x - lastX_;
    float dy = y - lastY_;
    lastX_ = x; lastY_ = y;
    yaw += dx * 0.006f;
    pitch = clampf(pitch + dy * 0.005f, -1.5708f, 1.5708f);
    lastInteractionTime = 0;
}

void EarthCamera::onTouchUp() {
    touching_ = false;
}

void EarthCamera::onPinchUpdate(float dist) {
    if (pinching_ && lastPinchDist_ > 0) {
        float ratio = dist / lastPinchDist_;
        if (ratio > 0) {
            distance = clampf(distance / ratio, 1.72f, 4.25f);
        }
    }
    lastPinchDist_ = dist;
    pinching_ = true;
    lastInteractionTime = 0;
}

void EarthCamera::onPinchEnd() {
    pinching_ = false;
    lastPinchDist_ = 0;
}

void EarthCamera::updateAutoRotate(double delta) {
    if (autoRotateEnabled && lastInteractionTime > 3000) {
        yaw += delta * 0.055f;
    }
}

static void mat4Identity(float *m) {
    memset(m, 0, 64);
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void mat4Multiply(const float *a, const float *b, float *out) {
    float tmp[16];
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            tmp[j * 4 + i] = 0;
            for (int k = 0; k < 4; k++) {
                tmp[j * 4 + i] += a[k * 4 + i] * b[j * 4 + k];
            }
        }
    }
    memcpy(out, tmp, 64);
}

void EarthCamera::getViewMatrix(float *out) const {
    mat4Identity(out);
    out[14] = -distance;
}

void EarthCamera::getProjectionMatrix(float aspect, float *out) const {
    float fovY = 0.72f;
    float nearP = 0.1f, farP = 20.0f;
    float f = 1.0f / tanf(fovY * 0.5f);
    mat4Identity(out);
    out[0] = f / aspect;
    out[5] = f;
    out[10] = (farP + nearP) / (nearP - farP);
    out[11] = -1.0f;
    out[14] = (2.0f * farP * nearP) / (nearP - farP);
    out[15] = 0.0f;
}

void EarthCamera::getGlobeModelMatrix(float *out) const {
    float ry[16], rx[16];
    mat4Identity(ry);
    float cy = cosf(yaw), sy = sinf(yaw);
    ry[0] = cy; ry[2] = -sy;
    ry[8] = sy; ry[10] = cy;

    mat4Identity(rx);
    float cp = cosf(pitch), sp = sinf(pitch);
    rx[5] = cp; rx[6] = sp;
    rx[9] = -sp; rx[10] = cp;

    mat4Multiply(ry, rx, out);
}
