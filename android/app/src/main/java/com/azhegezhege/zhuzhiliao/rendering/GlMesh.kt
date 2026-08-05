package com.azhegezhege.zhuzhiliao.rendering

import android.opengl.GLES30
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer

data class Vertex(
    val px: Float, val py: Float, val pz: Float,
    val nx: Float, val ny: Float, val nz: Float,
    val u: Float = 0f, val v: Float = 0f, val surface: Float = 0f,
)

data class MeshData(val vertices: List<Vertex>, val indices: List<Short>)

class GlMesh(data: MeshData) {
    private val vertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(data.vertices.size * STRIDE_BYTES)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            data.vertices.forEach { vertex ->
                put(vertex.px); put(vertex.py); put(vertex.pz)
                put(vertex.nx); put(vertex.ny); put(vertex.nz)
                put(vertex.u); put(vertex.v); put(vertex.surface)
            }
            position(0)
        }
    private val indexBuffer: ShortBuffer = ByteBuffer
        .allocateDirect(data.indices.size * 2)
        .order(ByteOrder.nativeOrder())
        .asShortBuffer()
        .apply { data.indices.forEach(::put); position(0) }
    private val vao = IntArray(1)
    private val buffers = IntArray(2)
    val indexCount = data.indices.size

    fun upload() {
        GLES30.glGenVertexArrays(1, vao, 0)
        GLES30.glBindVertexArray(vao[0])
        GLES30.glGenBuffers(2, buffers, 0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, buffers[0])
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, vertexBuffer.capacity() * 4, vertexBuffer, GLES30.GL_STATIC_DRAW)
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, buffers[1])
        GLES30.glBufferData(GLES30.GL_ELEMENT_ARRAY_BUFFER, indexBuffer.capacity() * 2, indexBuffer, GLES30.GL_STATIC_DRAW)
        listOf(0 to 0, 1 to 3, 2 to 6).forEach { (location, offset) ->
            GLES30.glEnableVertexAttribArray(location)
            GLES30.glVertexAttribPointer(location, 3, GLES30.GL_FLOAT, false, STRIDE_BYTES, offset * 4)
        }
        GLES30.glBindVertexArray(0)
    }

    fun draw() {
        GLES30.glBindVertexArray(vao[0])
        GLES30.glDrawElements(GLES30.GL_TRIANGLES, indexCount, GLES30.GL_UNSIGNED_SHORT, 0)
        GLES30.glBindVertexArray(0)
    }

    companion object { const val STRIDE_BYTES = 9 * 4 }
}
