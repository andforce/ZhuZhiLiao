#ifndef EARTH_MESH_H
#define EARTH_MESH_H

#include <vector>

struct MeshData {
    std::vector<float> vertices;
    std::vector<unsigned short> indices;
    int vertexCount = 0;
    int indexCount = 0;
};

void generateSphere(int latSegments, int lonSegments, float radius, MeshData &out);
void generateTorus(int majorSegments, int minorSegments, float majorRadius, float minorRadius, MeshData &out);

#endif
