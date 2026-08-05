package com.azhegezhege.zhuzhiliao.earth

data class EarthJoinPresentation(
    val buttonLabel: String,
    val buttonEnabled: Boolean,
    val statusMessage: String?,
) {
    companion object {
        fun from(state: EarthFeatureState): EarthJoinPresentation = when {
            state.isUpdatingLocation -> EarthJoinPresentation(
                buttonLabel = "正在获取粗略位置…",
                buttonEnabled = false,
                statusMessage = "正在定位，可能需要十几秒",
            )
            state.joinError != null -> EarthJoinPresentation(
                buttonLabel = "重试定位",
                buttonEnabled = true,
                statusMessage = state.joinError,
            )
            else -> EarthJoinPresentation(
                buttonLabel = "继续并允许使用期间定位",
                buttonEnabled = true,
                statusMessage = null,
            )
        }
    }
}
