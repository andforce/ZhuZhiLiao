package com.azhegezhege.zhuzhiliao.rendering

import android.opengl.GLES30

class GlProgram(vertexSource: String, fragmentSource: String) {
    val id: Int
    private val uniforms = mutableMapOf<String, Int>()

    init {
        val vertex = compile(GLES30.GL_VERTEX_SHADER, vertexSource)
        val fragment = compile(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
        id = GLES30.glCreateProgram()
        GLES30.glAttachShader(id, vertex)
        GLES30.glAttachShader(id, fragment)
        GLES30.glLinkProgram(id)
        val status = IntArray(1)
        GLES30.glGetProgramiv(id, GLES30.GL_LINK_STATUS, status, 0)
        check(status[0] == GLES30.GL_TRUE) { "OpenGL program link failed: ${GLES30.glGetProgramInfoLog(id)}" }
        GLES30.glDeleteShader(vertex); GLES30.glDeleteShader(fragment)
    }

    fun use() = GLES30.glUseProgram(id)
    fun uniform(name: String): Int = uniforms.getOrPut(name) { GLES30.glGetUniformLocation(id, name) }

    private fun compile(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        check(status[0] == GLES30.GL_TRUE) { "OpenGL shader compile failed: ${GLES30.glGetShaderInfoLog(shader)}" }
        return shader
    }
}
