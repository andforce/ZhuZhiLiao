#include "earth_mesh.h"
#include <cmath>

void generateSphere(int latSegments, int lonSegments, float radius, MeshData &out) {
    out.vertices.clear();
    out.indices.clear();

    for (int lat = 0; lat <= latSegments; lat++) {
        float theta = lat * 3.14159265f / latSegments;
        float sinT = sinf(theta);
        float cosT = cosf(theta);
        for (int lon = 0; lon <= lonSegments; lon++) {
            float phi = lon * 2.0f * 3.14159265f / lonSegments;
            float sinP = sinf(phi);
            float cosP = cosf(phi);
            float x = cosP * sinT * radius;
            float y = cosT * radius;
            float z = sinP * sinT * radius;
            float len = sqrtf(x*x+y*y+z*z);
            float nx = x/len, ny = y/len, nz = z/len;
            float u = (float)lon / lonSegments;
            float v = (float)lat / latSegments;
            out.vertices.push_back(x); out.vertices.push_back(y); out.vertices.push_back(z);
            out.vertices.push_back(nx); out.vertices.push_back(ny); out.vertices.push_back(nz);
            out.vertices.push_back(u); out.vertices.push_back(v);
        }
    }

    for (int lat = 0; lat < latSegments; lat++) {
        for (int lon = 0; lon < lonSegments; lon++) {
            int a = lat * (lonSegments + 1) + lon;
            int b = a + lonSegments + 1;
            out.indices.push_back((unsigned short)a);
            out.indices.push_back((unsigned short)b);
            out.indices.push_back((unsigned short)(a + 1));
            out.indices.push_back((unsigned short)(a + 1));
            out.indices.push_back((unsigned short)b);
            out.indices.push_back((unsigned short)(b + 1));
        }
    }

    out.vertexCount = (latSegments + 1) * (lonSegments + 1);
    out.indexCount = out.indices.size();
}

void generateTorus(int majorSegments, int minorSegments, float majorRadius, float minorRadius, MeshData &out) {
    out.vertices.clear();
    out.indices.clear();

    for (int i = 0; i <= majorSegments; i++) {
        float outerAngle = i * 2.0f * 3.14159265f / majorSegments;
        float cosOA = cosf(outerAngle);
        float sinOA = sinf(outerAngle);
        for (int j = 0; j <= minorSegments; j++) {
            float innerAngle = j * 2.0f * 3.14159265f / minorSegments;
            float cosIA = cosf(innerAngle);
            float sinIA = sinf(innerAngle);
            float radial = majorRadius + minorRadius * cosIA;
            float x = radial * cosOA;
            float y = radial * sinOA;
            float z = minorRadius * sinIA;
            float nx = cosIA * cosOA;
            float ny = cosIA * sinOA;
            float nz = sinIA;
            float u = (float)i / majorSegments;
            float v = (float)j / minorSegments;
            out.vertices.push_back(x); out.vertices.push_back(y); out.vertices.push_back(z);
            out.vertices.push_back(nx); out.vertices.push_back(ny); out.vertices.push_back(nz);
            out.vertices.push_back(u); out.vertices.push_back(v);
        }
    }

    for (int i = 0; i < majorSegments; i++) {
        for (int j = 0; j < minorSegments; j++) {
            int a = i * (minorSegments + 1) + j;
            int b = a + minorSegments + 1;
            out.indices.push_back((unsigned short)a);
            out.indices.push_back((unsigned short)b);
            out.indices.push_back((unsigned short)(a + 1));
            out.indices.push_back((unsigned short)(a + 1));
            out.indices.push_back((unsigned short)b);
            out.indices.push_back((unsigned short)(b + 1));
        }
    }

    out.vertexCount = (majorSegments + 1) * (minorSegments + 1);
    out.indexCount = out.indices.size();
}
