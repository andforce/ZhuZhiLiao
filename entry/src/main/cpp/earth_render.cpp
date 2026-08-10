#include <napi/native_api.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <cstring>

#include "earth_gl_renderer.h"
#include "earth_camera.h"

static EarthGLRenderer g_renderer;
static OH_NativeXComponent* g_component = nullptr;
static void* g_savedWindow = nullptr;
static EGLDisplay g_display = EGL_NO_DISPLAY;
static EGLSurface g_surface = EGL_NO_SURFACE;
static EGLContext g_context = EGL_NO_CONTEXT;
static int g_surfaceWidth = 0;
static int g_surfaceHeight = 0;
static long long g_lastFrameTime = 0;

#define LOG_TAG "EarthRender"
#define LOG_DOMAIN 0

static void OnSurfaceCreated(OH_NativeXComponent* component, void* window);
static void OnSurfaceChanged(OH_NativeXComponent* component, void* window);
static void OnSurfaceDestroyed(OH_NativeXComponent* component, void* window);
static void OnDispatchTouchEvent(OH_NativeXComponent* component, void* window);
static void OnFrameCallback(OH_NativeXComponent* component, uint64_t timestamp, uint64_t targetTimestamp);

static napi_value NAPI_RegisterCallback(napi_env env, napi_callback_info info);
static napi_value NAPI_UpdateBoundaryData(napi_env env, napi_callback_info info);
static napi_value NAPI_UpdateGridData(napi_env env, napi_callback_info info);
static napi_value NAPI_UpdateNodes(napi_env env, napi_callback_info info);
static napi_value NAPI_SetAutoRotate(napi_env env, napi_callback_info info);
static napi_value NAPI_SetCameraDistance(napi_env env, napi_callback_info info);
static napi_value NAPI_SetMeJoined(napi_env env, napi_callback_info info);
static napi_value NAPI_SetMeCode(napi_env env, napi_callback_info info);
static napi_value NAPI_Cleanup(napi_env env, napi_callback_info info);

static void RegisterXComponentCallbacks(OH_NativeXComponent* nativeXComponent) {
    if (nativeXComponent == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "RegisterXComponentCallbacks: null component");
        return;
    }
    g_component = nativeXComponent;

    static OH_NativeXComponent_Callback callback;
    memset(&callback, 0, sizeof(callback));
    callback.OnSurfaceCreated = OnSurfaceCreated;
    callback.OnSurfaceChanged = OnSurfaceChanged;
    callback.OnSurfaceDestroyed = OnSurfaceDestroyed;
    callback.DispatchTouchEvent = OnDispatchTouchEvent;
    int32_t ret = OH_NativeXComponent_RegisterCallback(nativeXComponent, &callback);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RegisterCallback ret=%d", ret);
}

static void RegisterFrameCallback(OH_NativeXComponent* nativeXComponent) {
    if (nativeXComponent == nullptr) return;
    OH_NativeXComponent_ExpectedRateRange range = {30, 120, 60};
    OH_NativeXComponent_SetExpectedFrameRateRange(nativeXComponent, &range);
    OH_NativeXComponent_RegisterOnFrameCallback(nativeXComponent, OnFrameCallback);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Frame callback registered");
}

static void InitEGL(void* window) {
    if (g_display != EGL_NO_DISPLAY) return;
    if (window == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "InitEGL: window is null!");
        return;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitEGL start, window=%p", window);

    OHNativeWindow* nativeWindow = static_cast<OHNativeWindow*>(window);
    if (nativeWindow == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "InitEGL: nativeWindow is null!");
        return;
    }

    g_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_display == EGL_NO_DISPLAY) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglGetDisplay failed");
        return;
    }
    EGLBoolean initRet = eglInitialize(g_display, nullptr, nullptr);
    if (!initRet) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglInitialize failed: 0x%x", eglGetError());
        return;
    }

    const EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_NONE
    };
    EGLConfig config;
    EGLint numConfigs;
    eglChooseConfig(g_display, attribs, &config, 1, &numConfigs);
    if (numConfigs < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglChooseConfig failed: 0x%x", eglGetError());
        return;
    }

    g_surface = eglCreateWindowSurface(g_display, config,
        reinterpret_cast<EGLNativeWindowType>(nativeWindow), nullptr);
    if (g_surface == EGL_NO_SURFACE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglCreateWindowSurface failed: 0x%x", eglGetError());
        return;
    }

    const EGLint contextAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    g_context = eglCreateContext(g_display, config, EGL_NO_CONTEXT, contextAttribs);
    if (g_context == EGL_NO_CONTEXT) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglCreateContext failed: 0x%x", eglGetError());
        return;
    }

    EGLBoolean makeCurrentRet = eglMakeCurrent(g_display, g_surface, g_surface, g_context);
    if (!makeCurrentRet) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "eglMakeCurrent failed: 0x%x", eglGetError());
        return;
    }

    g_renderer.initGL();
    g_lastFrameTime = 0;

    if (g_surfaceWidth > 0 && g_surfaceHeight > 0) {
        glViewport(0, 0, g_surfaceWidth, g_surfaceHeight);
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "EGL initialized OK, viewport=%{public}dx%{public}d", g_surfaceWidth, g_surfaceHeight);
}

static void OnSurfaceCreated(OH_NativeXComponent* component, void* window) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreated, component=%{public}p window=%{public}p", component, window);
    if (window != nullptr) {
        g_savedWindow = window;
    }
}

static void OnSurfaceChanged(OH_NativeXComponent* component, void* window) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChanged, component=%{public}p window=%{public}p", component, window);
    if (window != nullptr) {
        g_savedWindow = window;
    }
    if (g_savedWindow != nullptr) {
        InitEGL(g_savedWindow);
    }
    if (g_component != nullptr && g_savedWindow != nullptr) {
        uint64_t w, h;
        OH_NativeXComponent_GetXComponentSize(g_component, g_savedWindow, &w, &h);
        g_surfaceWidth = (int)w;
        g_surfaceHeight = (int)h;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Surface size w=%{public}d h=%{public}d", (int)w, (int)h);
    }
}

static void OnSurfaceDestroyed(OH_NativeXComponent* component, void* window) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyed");
    eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    g_renderer.cleanupGL();
    if (g_surface != EGL_NO_SURFACE) eglDestroySurface(g_display, g_surface);
    if (g_context != EGL_NO_CONTEXT) eglDestroyContext(g_display, g_context);
    if (g_display != EGL_NO_DISPLAY) eglTerminate(g_display);
    g_display = EGL_NO_DISPLAY;
    g_surface = EGL_NO_SURFACE;
    g_context = EGL_NO_CONTEXT;
}

static void OnDispatchTouchEvent(OH_NativeXComponent* component, void* window) {
    OH_NativeXComponent_TouchEvent touchEvent;
    OH_NativeXComponent_GetTouchEvent(component, window, &touchEvent);

    if (touchEvent.numPoints == 2) {
        g_renderer.camera.onTouchUp();
        float x0 = touchEvent.touchPoints[0].x;
        float y0 = touchEvent.touchPoints[0].y;
        float x1 = touchEvent.touchPoints[1].x;
        float y1 = touchEvent.touchPoints[1].y;
        float dist = sqrtf((x1-x0)*(x1-x0) + (y1-y0)*(y1-y0));

        int type = touchEvent.type;
        if (type == OH_NATIVEXCOMPONENT_DOWN || type == OH_NATIVEXCOMPONENT_MOVE) {
            g_renderer.camera.onPinchUpdate(dist);
        } else if (type == OH_NATIVEXCOMPONENT_UP || type == OH_NATIVEXCOMPONENT_CANCEL) {
            g_renderer.camera.onPinchEnd();
        }
        return;
    }

    g_renderer.camera.onPinchEnd();
    float x = touchEvent.x;
    float y = touchEvent.y;

    int type = touchEvent.type;
    if (type == OH_NATIVEXCOMPONENT_DOWN) {
        g_renderer.camera.onTouchDown(x, y);
    } else if (type == OH_NATIVEXCOMPONENT_MOVE) {
        g_renderer.camera.onTouchMove(x, y);
    } else {
        g_renderer.camera.onTouchUp();
    }
}

static void OnFrameCallback(OH_NativeXComponent* component, uint64_t timestamp, uint64_t targetTimestamp) {
    if (g_display == EGL_NO_DISPLAY) return;

    static bool firstFrame = true;
    if (firstFrame) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnFrameCallback first frame, surface=%{public}dx%{public}d", g_surfaceWidth, g_surfaceHeight);
        GLenum err = glGetError();
        if (err != GL_NO_ERROR) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "GL error before first frame: 0x%x", err);
        }
        firstFrame = false;
    }

    if (g_surfaceWidth > 0 && g_surfaceHeight > 0) {
        glViewport(0, 0, g_surfaceWidth, g_surfaceHeight);
    }

    long long now = (long long)(timestamp / 1000000);
    if (g_lastFrameTime == 0) g_lastFrameTime = now;
    double delta = (now - g_lastFrameTime) / 1000.0;
    if (delta > 0.05) delta = 0.016;
    g_lastFrameTime = now;

    g_renderer.camera.lastInteractionTime += (long long)(delta * 1000);
    g_renderer.camera.updateAutoRotate(delta);

    g_renderer.drawFrame();
    eglSwapBuffers(g_display, g_surface);
}

static napi_value NAPI_RegisterCallback(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "NAPI_RegisterCallback called, savedWindow=%{public}p", g_savedWindow);

    RegisterFrameCallback(g_component);

    if (g_component != nullptr && g_savedWindow != nullptr) {
        uint64_t w, h;
        OH_NativeXComponent_GetXComponentSize(g_component, g_savedWindow, &w, &h);
        g_surfaceWidth = (int)w;
        g_surfaceHeight = (int)h;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "registerCallback surface=%{public}d x %{public}d", (int)w, (int)h);
    }

    if (g_savedWindow != nullptr && g_display == EGL_NO_DISPLAY) {
        InitEGL(g_savedWindow);
    }

    if (g_surfaceWidth > 0 && g_surfaceHeight > 0) {
        glViewport(0, 0, g_surfaceWidth, g_surfaceHeight);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "glViewport set to %{public}d x %{public}d", g_surfaceWidth, g_surfaceHeight);
    }
    return nullptr;
}

static napi_value NAPI_UpdateBoundaryData(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_typedarray_type arrayType;
    size_t length;
    void* data;
    napi_value arraybuffer;
    size_t byteOffset;
    napi_get_typedarray_info(env, args[0], &arrayType, &length, &data, &arraybuffer, &byteOffset);

    g_renderer.updateBoundaryData(static_cast<float*>(data), (int)length);
    return nullptr;
}

static napi_value NAPI_UpdateGridData(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_typedarray_type arrayType;
    size_t length;
    void* data;
    napi_value arraybuffer;
    size_t byteOffset;
    napi_get_typedarray_info(env, args[0], &arrayType, &length, &data, &arraybuffer, &byteOffset);

    g_renderer.updateGridData(static_cast<float*>(data), (int)length);
    return nullptr;
}

static napi_value NAPI_UpdateNodes(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_typedarray_type arrayType;
    size_t length;
    void* data;
    napi_value arraybuffer;
    size_t byteOffset;
    napi_get_typedarray_info(env, args[0], &arrayType, &length, &data, &arraybuffer, &byteOffset);

    g_renderer.updateNodes(static_cast<float*>(data), (int)length);
    return nullptr;
}

static napi_value NAPI_SetAutoRotate(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool enabled;
    napi_get_value_bool(env, args[0], &enabled);
    g_renderer.camera.autoRotateEnabled = enabled;
    return nullptr;
}

static napi_value NAPI_SetCameraDistance(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double dist;
    napi_get_value_double(env, args[0], &dist);
    g_renderer.camera.distance = (float)dist;
    return nullptr;
}

static napi_value NAPI_SetMeJoined(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool joined;
    napi_get_value_bool(env, args[0], &joined);
    g_renderer.setMeJoined(joined);
    return nullptr;
}

static napi_value NAPI_SetMeCode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char* buf = (char*)malloc(len + 1);
    napi_get_value_string_utf8(env, args[0], buf, len + 1, &len);
    g_renderer.setMeCode(buf);
    free(buf);
    return nullptr;
}

static napi_value NAPI_Cleanup(napi_env env, napi_callback_info info) {
    g_renderer.cleanupGL();
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Init() called");

    napi_value nativeXComponentVal = nullptr;
    napi_status status = napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &nativeXComponentVal);

    OH_NativeXComponent* nativeXComponent = nullptr;
    if (status == napi_ok && nativeXComponentVal != nullptr) {
        napi_unwrap(env, nativeXComponentVal, reinterpret_cast<void**>(&nativeXComponent));
    }

    if (nativeXComponent != nullptr) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Init: got nativeXComponent, registering surface callbacks");
        g_component = nativeXComponent;
        static OH_NativeXComponent_Callback callback;
        memset(&callback, 0, sizeof(callback));
        callback.OnSurfaceCreated = OnSurfaceCreated;
        callback.OnSurfaceChanged = OnSurfaceChanged;
        callback.OnSurfaceDestroyed = OnSurfaceDestroyed;
        callback.DispatchTouchEvent = OnDispatchTouchEvent;
        int32_t ret = OH_NativeXComponent_RegisterCallback(nativeXComponent, &callback);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Init: RegisterCallback ret=%d", ret);
    }

    napi_property_descriptor desc[] = {
        {"registerCallback", nullptr, NAPI_RegisterCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"updateBoundaryData", nullptr, NAPI_UpdateBoundaryData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"updateGridData", nullptr, NAPI_UpdateGridData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"updateNodes", nullptr, NAPI_UpdateNodes, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAutoRotate", nullptr, NAPI_SetAutoRotate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCameraDistance", nullptr, NAPI_SetCameraDistance, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setMeJoined", nullptr, NAPI_SetMeJoined, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setMeCode", nullptr, NAPI_SetMeCode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cleanup", nullptr, NAPI_Cleanup, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    return exports;
}
EXTERN_C_END

static napi_module earthrenderModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "earthrender",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEarthrenderModule(void) {
    napi_module_register(&earthrenderModule);
}
