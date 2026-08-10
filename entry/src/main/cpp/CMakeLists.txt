cmake_minimum_required(VERSION 3.5.0)
project(earthrender)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(earthrender SHARED
    earth_render.cpp
    earth_gl_renderer.cpp
    earth_camera.cpp
    earth_mesh.cpp
    earth_shader.cpp
)

target_link_libraries(earthrender PUBLIC
    libace_ndk.z.so
    libace_napi.z.so
    libegl.so
    libGLESv3.so
    libhilog_ndk.z.so
    libnative_window.so
)
