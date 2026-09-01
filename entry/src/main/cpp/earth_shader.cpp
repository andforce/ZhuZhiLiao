#include "earth_shader.h"
#include <GLES3/gl3.h>
#include <hilog/log.h>

static const char *VERTEX_SHADER_SRC = R"(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aTexCoord;
uniform mat4 uViewProjection;
uniform mat4 uModel;
uniform mat3 uNormalMatrix;
out vec3 vNormal;
out vec2 vTexCoord;
void main() {
    gl_Position = uViewProjection * uModel * vec4(aPosition, 1.0);
    vNormal = normalize(uNormalMatrix * aNormal);
    vTexCoord = aTexCoord;
}
)";

static const char *FRAGMENT_SHADER_SRC = R"(#version 300 es
precision highp float;
in vec3 vNormal;
in vec2 vTexCoord;
uniform vec4 uBaseColor;
uniform vec2 uMaterial;
uniform vec3 uCoolLight;
uniform vec3 uWarmLight;
out vec4 outColor;
void main() {
    vec3 normal = normalize(vNormal);
    vec3 moon = normalize(vec3(0.55, 0.78, 0.60));
    vec3 warmDir = normalize(vec3(-0.62, 0.18, 0.74));
    vec3 viewDir = normalize(vec3(0.0, 0.04, 1.0));
    vec3 halfDir = normalize(moon + viewDir);
    float diffuse = max(dot(normal, moon), 0.0);
    float rim = pow(1.0 - max(dot(normal, viewDir), 0.0), 2.7);
    float warm = max(dot(normal, warmDir), 0.0);
    float rough = 0.78;
    float surface = vTexCoord.x;
    float specPower = mix(10.0, 74.0, 1.0 - rough);
    float spec = pow(max(dot(normal, halfDir), 0.0), specPower) * mix(0.03, 0.42, 1.0 - rough);
    vec3 light = uCoolLight * 0.25 + vec3(1.0, 0.92, 0.75) * diffuse * 0.88 + uWarmLight * warm * 0.18 + uCoolLight * rim * 0.22;
    vec3 base = uBaseColor.rgb;
    vec3 color = base * light + uWarmLight * spec + base * uMaterial.y * mix(uCoolLight, uWarmLight, 0.55);
    outColor = vec4(color, uBaseColor.a);
}
)";

static unsigned int compileShader(int type, const char *src) {
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    int success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char log[512];
        glGetShaderInfoLog(shader, 512, nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, "EarthShader", "compile error: %{public}s", log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

unsigned int compileShaderProgram() {
    unsigned int vs = compileShader(GL_VERTEX_SHADER, VERTEX_SHADER_SRC);
    unsigned int fs = compileShader(GL_FRAGMENT_SHADER, FRAGMENT_SHADER_SRC);
    if (!vs || !fs) return 0;
    unsigned int program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glBindAttribLocation(program, 0, "aPosition");
    glBindAttribLocation(program, 1, "aNormal");
    glBindAttribLocation(program, 2, "aTexCoord");
    glLinkProgram(program);
    int success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        char log[512];
        glGetProgramInfoLog(program, 512, nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, "EarthShader", "link error: %{public}s", log);
        glDeleteProgram(program);
        program = 0;
    }
    glDeleteShader(vs);
    glDeleteShader(fs);
    return program;
}

int getUniformLocation(unsigned int program, const char *name) {
    return glGetUniformLocation(program, name);
}
