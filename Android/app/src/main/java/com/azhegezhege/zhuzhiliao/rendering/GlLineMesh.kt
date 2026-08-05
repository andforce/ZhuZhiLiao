package com.azhegezhege.zhuzhiliao.rendering

import android.opengl.GLES30
import java.nio.ByteBuffer
import java.nio.ByteOrder

class GlLineMesh(vertices: List<Vertex>) {
    private val vertexBuffer = ByteBuffer.allocateDirect(vertices.size * GlMesh.STRIDE_BYTES)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            vertices.forEach { vertex ->
                put(vertex.px); put(vertex.py); put(vertex.pz)
                put(vertex.nx); put(vertex.ny); put(vertex.nz)
                put(vertex.u); put(vertex.v); put(vertex.surface)
            }
            position(0)
        }
    private val vao = IntArray(1)
    private val buffer = IntArray(1)
    private val vertexCount = vertices.size

    fun upload() {
        GLES30.glGenVertexArrays(1, vao, 0)
        GLES30.glBindVertexArray(vao[0])
        GLES30.glGenBuffers(1, buffer, 0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, buffer[0])
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, vertexBuffer.capacity() * 4, vertexBuffer, GLES30.GL_STATIC_DRAW)
        listOf(0 to 0, 1 to 3, 2 to 6).forEach { (location, offset) ->
            GLES30.glEnableVertexAttribArray(location)
            GLES30.glVertexAttribPointer(location, 3, GLES30.GL_FLOAT, false, GlMesh.STRIDE_BYTES, offset * 4)
        }
        GLES30.glBindVertexArray(0)
    }

    fun draw(alpha: Float) {
        if (vertexCount == 0 || alpha <= 0f) return
        GLES30.glBindVertexArray(vao[0])
        GLES30.glDrawArrays(GLES30.GL_LINES, 0, vertexCount)
        GLES30.glBindVertexArray(0)
    }
}
