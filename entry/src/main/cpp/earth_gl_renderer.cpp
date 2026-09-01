#include "earth_gl_renderer.h"
#include "earth_shader.h"
#include "earth_mesh.h"
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <cstring>
#include <cstdlib>
#include <cmath>

static void mat4Identity(float *m) {
    memset(m, 0, 64);
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void mat4Scale(float sx, float sy, float sz, float *out) {
    memset(out, 0, 64);
    out[0] = sx; out[5] = sy; out[10] = sz; out[15] = 1.0f;
}

static void mat4Translate(float tx, float ty, float tz, float *out) {
    memset(out, 0, 64);
    out[0] = 1; out[5] = 1; out[10] = 1; out[15] = 1;
    out[12] = tx; out[13] = ty; out[14] = tz;
}

static void mat4Multiply(const float *a, const float *b, float *out) {
    float tmp[16];
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            tmp[j*4+i] = 0;
            for (int k = 0; k < 4; k++) {
                tmp[j*4+i] += a[k*4+i] * b[j*4+k];
            }
        }
    }
    memcpy(out, tmp, 64);
}

void EarthGLRenderer::computeNormalMatrix(const float *model, float *out) {
    float a = model[0], b = model[1], c = model[2];
    float d = model[4], e = model[5], f = model[6];
    float g = model[8], h = model[9], i = model[10];
    float det = a*(e*i - f*h) - b*(d*i - f*g) + c*(d*h - e*g);
    if (fabsf(det) < 1e-8f) { memset(out,0,36); out[0]=out[4]=out[8]=1; return; }
    float inv = 1.0f / det;
    out[0] = (e*i-f*h)*inv; out[1] = (c*h-b*i)*inv; out[2] = (b*f-c*e)*inv;
    out[3] = (f*g-d*i)*inv; out[4] = (a*i-c*g)*inv; out[5] = (c*d-a*f)*inv;
    out[6] = (d*h-e*g)*inv; out[7] = (b*g-a*h)*inv; out[8] = (a*e-b*d)*inv;
}

void EarthGLRenderer::initGL() {
    if (glInitialized_) return;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "initGL start");

    shaderProgram_ = compileShaderProgram();
    if (!shaderProgram_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, "EarthGL", "shader compile failed");
        return;
    }
    uViewProjection_ = getUniformLocation(shaderProgram_, "uViewProjection");
    uModel_ = getUniformLocation(shaderProgram_, "uModel");
    uNormalMatrix_ = getUniformLocation(shaderProgram_, "uNormalMatrix");
    uColor_ = getUniformLocation(shaderProgram_, "uBaseColor");
    uEmissive_ = getUniformLocation(shaderProgram_, "uMaterial");

    generateSphere(28, 40, 0.5f, sphereMesh_);
    glGenBuffers(1, &sphereVBO_);
    glBindBuffer(GL_ARRAY_BUFFER, sphereVBO_);
    glBufferData(GL_ARRAY_BUFFER, sphereMesh_.vertices.size() * sizeof(float),
                 sphereMesh_.vertices.data(), GL_STATIC_DRAW);
    glGenBuffers(1, &sphereIBO_);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, sphereIBO_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sphereMesh_.indices.size() * sizeof(unsigned short),
                 sphereMesh_.indices.data(), GL_STATIC_DRAW);
    sphereIndexCount_ = sphereMesh_.indexCount;

    generateTorus(48, 6, 0.5f, 0.035f, torusMesh_);
    glGenBuffers(1, &torusVBO_);
    glBindBuffer(GL_ARRAY_BUFFER, torusVBO_);
    glBufferData(GL_ARRAY_BUFFER, torusMesh_.vertices.size() * sizeof(float),
                 torusMesh_.vertices.data(), GL_STATIC_DRAW);
    glGenBuffers(1, &torusIBO_);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, torusIBO_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, torusMesh_.indices.size() * sizeof(unsigned short),
                 torusMesh_.indices.data(), GL_STATIC_DRAW);
    torusIndexCount_ = torusMesh_.indexCount;

    glGenBuffers(1, &boundaryVBO_);
    glGenBuffers(1, &gridVBO_);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glInitialized_ = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "initGL done, sphereIdx=%d torusIdx=%d",
                 sphereIndexCount_, torusIndexCount_);
}

void EarthGLRenderer::cleanupGL() {
    if (!glInitialized_) return;
    if (shaderProgram_) glDeleteProgram(shaderProgram_);
    if (sphereVBO_) glDeleteBuffers(1, &sphereVBO_);
    if (sphereIBO_) glDeleteBuffers(1, &sphereIBO_);
    if (torusVBO_) glDeleteBuffers(1, &torusVBO_);
    if (torusIBO_) glDeleteBuffers(1, &torusIBO_);
    if (boundaryVBO_) glDeleteBuffers(1, &boundaryVBO_);
    if (gridVBO_) glDeleteBuffers(1, &gridVBO_);
    if (nodeData_) { free(nodeData_); nodeData_ = nullptr; }
    glInitialized_ = false;
}

void EarthGLRenderer::setMaterial(const float *model, const float *color, float emissive) {
    float nm[9];
    computeNormalMatrix(model, nm);
    glUniformMatrix4fv(uModel_, 1, GL_FALSE, model);
    glUniformMatrix3fv(uNormalMatrix_, 1, GL_FALSE, nm);
    glUniform4fv(uColor_, 1, color);
    glUniform2f(uEmissive_, 0.0f, emissive);
}

void EarthGLRenderer::drawMeshWithVBOs(unsigned int vbo, unsigned int ibo, int indexCount,
                                         const float *modelMatrix, const float *color, float emissive) {
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 32, (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 32, (void*)12);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 32, (void*)24);

    setMaterial(modelMatrix, color, emissive);
    glDrawElements(GL_TRIANGLES, indexCount, GL_UNSIGNED_SHORT, 0);
}

void EarthGLRenderer::drawLines(unsigned int vbo, int vertexCount,
                                 const float *globeModel, const float *color, float emissive) {
    if (vertexCount == 0) return;
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 32, (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 32, (void*)12);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 32, (void*)24);

    setMaterial(globeModel, color, emissive);
    glDrawArrays(GL_LINES, 0, vertexCount);
}

static void latLonToSphere(float lat, float lon, float radius, float *out) {
    float phi = lat * 3.14159265f / 180.0f;
    float theta = lon * 3.14159265f / 180.0f;
    float cp = cosf(phi);
    out[0] = -cp * cosf(theta) * radius;
    out[1] = sinf(phi) * radius;
    out[2] = cp * sinf(theta) * radius;
}

void EarthGLRenderer::drawNodesOnGlobe(const float *globeModel) {
    if (nodeCount_ == 0) return;

    for (int i = 0; i < nodeCount_; i++) {
        float lat = nodeData_[i * 4];
        float lon = nodeData_[i * 4 + 1];
        float isMe = nodeData_[i * 4 + 3];
        if (lat == 0 && lon == 0) continue;

        float normal[3];
        latLonToSphere(lat, lon, 1.0f, normal);

        float pos[3] = { normal[0] * 1.035f, normal[1] * 1.035f, normal[2] * 1.035f };

        float visualScale = 0.0052f;

        float color[4];
        if (isMe > 0.5f) {
            color[0] = 0.98f; color[1] = 0.72f; color[2] = 0.28f; color[3] = 1.0f;
        } else {
            color[0] = 0.36f; color[1] = 0.93f; color[2] = 0.86f; color[3] = 0.94f;
        }

        float trans[16], scl[16], nodeModel[16];
        mat4Translate(pos[0], pos[1], pos[2], trans);
        mat4Scale(visualScale * 2, visualScale * 2, visualScale * 2, scl);
        mat4Multiply(trans, scl, nodeModel);

        float fullModel[16];
        mat4Multiply(globeModel, nodeModel, fullModel);

        drawMeshWithVBOs(sphereVBO_, sphereIBO_, sphereIndexCount_, fullModel, color, 0.55f);
    }
}

void EarthGLRenderer::drawRipples(const float *globeModel, long long now) {
    if (nodeCount_ == 0 || !meJoined_) return;

    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);

    for (int i = 0; i < nodeCount_; i++) {
        float isMe = nodeData_[i * 4 + 3];
        if (isMe < 0.5f) continue;
        float lat = nodeData_[i * 4];
        float lon = nodeData_[i * 4 + 1];
        if (lat == 0 && lon == 0) continue;

        float normal[3];
        latLonToSphere(lat, lon, 1.0f, normal);
        float pos[3] = { normal[0] * 1.035f, normal[1] * 1.035f, normal[2] * 1.035f };

        float alignZ[16];
        {
            float target[3] = { normal[0], normal[1], normal[2] };
            float len = sqrtf(target[0]*target[0] + target[1]*target[1] + target[2]*target[2]);
            if (len > 0.0001f) { target[0]/=len; target[1]/=len; target[2]/=len; }
            float src[3] = {0, 0, 1};
            float dot = src[0]*target[0] + src[1]*target[1] + src[2]*target[2];
            if (dot > 0.999999f) {
                mat4Identity(alignZ);
            } else if (dot < -0.999999f) {
                memset(alignZ, 0, 64);
                alignZ[0] = 1; alignZ[5] = -1; alignZ[10] = -1; alignZ[15] = 1;
            } else {
                float axis[3] = {
                    src[1]*target[2] - src[2]*target[1],
                    src[2]*target[0] - src[0]*target[2],
                    src[0]*target[1] - src[1]*target[0]
                };
                float aLen = sqrtf(axis[0]*axis[0] + axis[1]*axis[1] + axis[2]*axis[2]);
                if (aLen > 0.0001f) { axis[0]/=aLen; axis[1]/=aLen; axis[2]/=aLen; }
                float angle = acosf(dot);
                float c = cosf(angle), s = sinf(angle), t = 1 - c;
                float ax = axis[0], ay = axis[1], az = axis[2];
                memset(alignZ, 0, 64);
                alignZ[0] = t*ax*ax + c;     alignZ[1] = t*ax*ay + az*s; alignZ[2] = t*ax*az - ay*s;
                alignZ[4] = t*ax*ay - az*s;  alignZ[5] = t*ay*ay + c;    alignZ[6] = t*ay*az + ax*s;
                alignZ[8] = t*ax*az + ay*s;  alignZ[9] = t*ay*az - ax*s; alignZ[10] = t*az*az + c;
                alignZ[15] = 1;
            }
        }

        float posOffset[3] = { pos[0] + normal[0]*0.008f, pos[1] + normal[1]*0.008f, pos[2] + normal[2]*0.008f };
        float trans[16];
        mat4Translate(posOffset[0], posOffset[1], posOffset[2], trans);

        float phases[] = {0.0f, 0.33f, 0.66f};
        float cycle = (float)((now % 2800) / 2800.0);

        for (int j = 0; j < 3; j++) {
            float t = fmodf(cycle + phases[j], 1.0f);
            float radius = (0.045f + t * 0.18f) * 0.1f;
            float alpha = (1.0f - t) * 0.48f;

            float scl[16];
            mat4Scale(radius * 2, radius * 2, radius * 2, scl);

            float tmp[16], torusModel[16], fullModel[16];
            mat4Multiply(trans, alignZ, tmp);
            mat4Multiply(tmp, scl, torusModel);
            mat4Multiply(globeModel, torusModel, fullModel);

            float color[4] = {0.98f, 0.72f, 0.28f, alpha};
            drawMeshWithVBOs(torusVBO_, torusIBO_, torusIndexCount_, fullModel, color, 0.8f);
        }
    }

    glEnable(GL_CULL_FACE);
    glDepthMask(GL_TRUE);
}

void EarthGLRenderer::drawFrame() {
    if (!glInitialized_) return;

    if (firstFrame_) {
        GLint vp[4];
        glGetIntegerv(GL_VIEWPORT, vp);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "drawFrame first, viewport=%{public}d,%{public}d,%{public}d,%{public}d", vp[0], vp[1], vp[2], vp[3]);
    }

    glClearColor(0.012f, 0.022f, 0.055f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    uploadPendingData();

    int viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    float aspect = (float)viewport[2] / (float)viewport[3];

    float proj[16], view[16], viewProj[16];
    camera.getProjectionMatrix(aspect, proj);
    camera.getViewMatrix(view);
    mat4Multiply(proj, view, viewProj);

    float globeModel[16];
    camera.getGlobeModelMatrix(globeModel);

    glUseProgram(shaderProgram_);
    glUniformMatrix4fv(uViewProjection_, 1, GL_FALSE, viewProj);

    float coolLight[3] = {0.35f, 0.80f, 0.88f};
    float warmLight[3] = {1.0f, 0.84f, 0.42f};
    glUniform3f(getUniformLocation(shaderProgram_, "uCoolLight"), coolLight[0], coolLight[1], coolLight[2]);
    glUniform3f(getUniformLocation(shaderProgram_, "uWarmLight"), warmLight[0], warmLight[1], warmLight[2]);

    float globeScale[16], sphereModel[16];
    mat4Scale(2.0f, 2.0f, 2.0f, globeScale);
    mat4Multiply(globeModel, globeScale, sphereModel);

    float globeColor[4] = {0.025f, 0.07f, 0.11f, 0.98f};
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    drawMeshWithVBOs(sphereVBO_, sphereIBO_, sphereIndexCount_, sphereModel, globeColor, 0.08f);

    glDisable(GL_CULL_FACE);
    float boundaryColor[4] = {0.30f, 0.62f, 0.65f, 0.45f};
    drawLines(boundaryVBO_, boundaryVertexCount_, globeModel, boundaryColor, 0.35f);

    glEnable(GL_CULL_FACE);
    drawNodesOnGlobe(globeModel);

    drawRipples(globeModel, (long long)(clock() * 1000.0 / CLOCKS_PER_SEC));

    static int frameCount = 0;
    frameCount++;
    if (firstFrame_) {
        GLenum frameErr = glGetError();
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "first frame done, err=0x%x", frameErr);
        firstFrame_ = false;
    }
}

void EarthGLRenderer::updateBoundaryData(const float *data, int count) {
    if (count == 0) return;
    if (pendingBoundaryData_) { free(pendingBoundaryData_); pendingBoundaryData_ = nullptr; }
    pendingBoundaryCount_ = count;
    pendingBoundaryData_ = (float*)malloc(count * sizeof(float));
    memcpy(pendingBoundaryData_, data, count * sizeof(float));
}

void EarthGLRenderer::updateGridData(const float *data, int count) {
    if (count == 0) return;
    if (pendingGridData_) { free(pendingGridData_); pendingGridData_ = nullptr; }
    pendingGridCount_ = count;
    pendingGridData_ = (float*)malloc(count * sizeof(float));
    memcpy(pendingGridData_, data, count * sizeof(float));
}

void EarthGLRenderer::uploadPendingData() {
    if (pendingBoundaryData_ != nullptr) {
        glBindBuffer(GL_ARRAY_BUFFER, boundaryVBO_);
        glBufferData(GL_ARRAY_BUFFER, pendingBoundaryCount_ * sizeof(float),
                     pendingBoundaryData_, GL_STATIC_DRAW);
        boundaryVertexCount_ = pendingBoundaryCount_ / 8;
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "boundary uploaded, verts=%d", boundaryVertexCount_);
        free(pendingBoundaryData_);
        pendingBoundaryData_ = nullptr;
        pendingBoundaryCount_ = 0;
    }
    if (pendingGridData_ != nullptr) {
        glBindBuffer(GL_ARRAY_BUFFER, gridVBO_);
        glBufferData(GL_ARRAY_BUFFER, pendingGridCount_ * sizeof(float),
                     pendingGridData_, GL_STATIC_DRAW);
        gridVertexCount_ = pendingGridCount_ / 8;
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "grid uploaded, verts=%d", gridVertexCount_);
        free(pendingGridData_);
        pendingGridData_ = nullptr;
        pendingGridCount_ = 0;
    }
}

void EarthGLRenderer::updateNodes(const float *data, int count) {
    if (nodeData_) { free(nodeData_); nodeData_ = nullptr; }
    nodeCount_ = count / 4;
    if (nodeCount_ > 0) {
        nodeData_ = (float*)malloc(count * sizeof(float));
        memcpy(nodeData_, data, count * sizeof(float));
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "EarthGL", "nodes updated, count=%d", nodeCount_);
}

void EarthGLRenderer::setMeJoined(bool joined) {
    meJoined_ = joined;
}

void EarthGLRenderer::setMeCode(const char *code) {
    strncpy(meCode_, code, sizeof(meCode_) - 1);
    meCode_[sizeof(meCode_) - 1] = 0;
}
