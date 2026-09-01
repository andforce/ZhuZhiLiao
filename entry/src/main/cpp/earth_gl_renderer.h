#ifndef EARTH_GL_RENDERER_H
#define EARTH_GL_RENDERER_H

#include "earth_camera.h"
#include "earth_mesh.h"

class EarthGLRenderer {
public:
    void initGL();
    void cleanupGL();
    void drawFrame();
    void updateBoundaryData(const float *data, int count);
    void updateGridData(const float *data, int count);
    void updateNodes(const float *data, int count);
    void setMeJoined(bool joined);
    void setMeCode(const char *code);

    EarthCamera camera;

private:
    void setMaterial(const float *model, const float *color, float emissive);
    void drawMeshWithVBOs(unsigned int vbo, unsigned int ibo, int indexCount,
                           const float *modelMatrix, const float *color, float emissive);
    void drawLines(unsigned int vbo, int vertexCount, const float *globeModel,
                    const float *color, float emissive);
    void drawNodesOnGlobe(const float *globeModel);
    void drawRipples(const float *globeModel, long long now);
    void computeNormalMatrix(const float *model, float *out);
    void uploadPendingData();

    unsigned int shaderProgram_ = 0;
    int uViewProjection_ = -1;
    int uModel_ = -1;
    int uNormalMatrix_ = -1;
    int uColor_ = -1;
    int uEmissive_ = -1;

    unsigned int sphereVBO_ = 0, sphereIBO_ = 0;
    int sphereIndexCount_ = 0;
    unsigned int torusVBO_ = 0, torusIBO_ = 0;
    int torusIndexCount_ = 0;
    unsigned int boundaryVBO_ = 0;
    int boundaryVertexCount_ = 0;
    unsigned int gridVBO_ = 0;
    int gridVertexCount_ = 0;

    float *pendingBoundaryData_ = nullptr;
    int pendingBoundaryCount_ = 0;
    float *pendingGridData_ = nullptr;
    int pendingGridCount_ = 0;

    float *nodeData_ = nullptr;
    int nodeCount_ = 0;
    bool meJoined_ = false;
    char meCode_[64] = {};

    MeshData sphereMesh_;
    MeshData torusMesh_;
    bool glInitialized_ = false;
    bool firstFrame_ = true;
};

#endif
