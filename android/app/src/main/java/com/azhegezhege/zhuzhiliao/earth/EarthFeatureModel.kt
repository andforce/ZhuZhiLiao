package com.azhegezhege.zhuzhiliao.earth

import com.azhegezhege.zhuzhiliao.ExperienceCoordinator
import com.azhegezhege.zhuzhiliao.network.EarthNode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class EarthFeatureState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val nodes: List<EarthNode> = emptyList(),
    val serverClockOffsetMilliseconds: Long = 0L,
    val selectedNode: EarthNode? = null,
    val isParticipating: Boolean = false,
    val isUpdatingLocation: Boolean = false,
    val isLeaving: Boolean = false,
)

class EarthFeatureModel(
    private val coordinator: ExperienceCoordinator,
    private val scope: CoroutineScope,
    private val onChange: (EarthFeatureState) -> Unit,
) {
    var state = EarthFeatureState(isParticipating = coordinator.uiState.earthIsEnabled)
        private set
    private var detail = 2
    private var refreshJob: Job? = null

    fun start() {
        refresh(showLoading = true)
    }

    fun refreshForRevision() {
        scheduleRefresh(delayMilliseconds = 120, showLoading = false)
    }

    fun retry() = refresh(showLoading = state.nodes.isEmpty())

    fun setDetail(value: Int) {
        val clamped = value.coerceIn(0, 4)
        if (clamped == detail) return
        detail = clamped
        scheduleRefresh(delayMilliseconds = 180, showLoading = false)
    }

    fun select(node: EarthNode?) = update(state.copy(selectedNode = node))

    fun join(locationService: EarthLocationService, after: (Boolean) -> Unit = {}) {
        if (state.isUpdatingLocation) return
        scope.launch {
            update(state.copy(isUpdatingLocation = true, error = null))
            val succeeded = try {
                val location = locationService.requestOneLocation()
                val cellID = EarthLocationGrid.cellID(location.latitude, location.longitude)
                    ?: throw EarthLocationException("当前位置无效，请稍后再试")
                if (coordinator.uiState.earthCellID != cellID || !state.isParticipating) {
                    coordinator.setEarthLocation(cellID)
                }
                update(state.copy(isParticipating = true))
                refresh(showLoading = false)
                true
            } catch (_: CancellationException) {
                false
            } catch (error: Throwable) {
                update(state.copy(error = error.localizedMessage ?: "当前位置更新失败"))
                false
            } finally {
                update(state.copy(isUpdatingLocation = false))
            }
            after(succeeded)
        }
    }

    fun refreshExistingLocation(locationService: EarthLocationService) {
        if (!state.isParticipating || !locationService.canRefreshWithoutPrompt) return
        scope.launch {
            runCatching { locationService.requestOneLocation() }.getOrNull()?.let { location ->
                val cellID = EarthLocationGrid.cellID(location.latitude, location.longitude) ?: return@let
                if (cellID != coordinator.uiState.earthCellID) {
                    runCatching { coordinator.setEarthLocation(cellID) }
                    refresh(showLoading = false)
                }
            }
        }
    }

    fun leave(after: (Boolean) -> Unit = {}) {
        if (state.isLeaving) return
        scope.launch {
            update(state.copy(isLeaving = true, error = null))
            val succeeded = runCatching { coordinator.disableEarth() }
                .onSuccess {
                    update(state.copy(isParticipating = false, selectedNode = null))
                    refresh(showLoading = false)
                }
                .onFailure { update(state.copy(error = it.localizedMessage ?: "退出失败，请稍后重试")) }
                .isSuccess
            update(state.copy(isLeaving = false))
            after(succeeded)
        }
    }

    fun showError(message: String) = update(state.copy(error = message, isLoading = false))

    fun close() {
        refreshJob?.cancel()
    }

    private fun refresh(showLoading: Boolean) {
        scheduleRefresh(delayMilliseconds = 0, showLoading = showLoading)
    }

    private fun scheduleRefresh(delayMilliseconds: Long, showLoading: Boolean) {
        refreshJob?.cancel()
        refreshJob = scope.launch {
            if (delayMilliseconds > 0) delay(delayMilliseconds)
            refreshSuspend(showLoading)
        }
    }

    private suspend fun refreshSuspend(showLoading: Boolean) {
        if (showLoading && state.nodes.isEmpty()) update(state.copy(isLoading = true, error = null))
        try {
            val snapshot = coordinator.loadEarthSnapshot(detail)
            val selectedID = state.selectedNode?.id
            update(
                state.copy(
                    isLoading = false,
                    error = null,
                    nodes = snapshot.nodes,
                    serverClockOffsetMilliseconds = snapshot.serverTime - System.currentTimeMillis(),
                    selectedNode = selectedID?.let { id -> snapshot.nodes.firstOrNull { it.id == id } },
                    isParticipating = state.isParticipating,
                ),
            )
        } catch (_: CancellationException) {
            return
        } catch (error: Throwable) {
            update(state.copy(isLoading = false, error = error.localizedMessage ?: "暂时无法载入哇声地球"))
        }
    }

    private fun update(value: EarthFeatureState) {
        state = value
        onChange(value)
    }
}
