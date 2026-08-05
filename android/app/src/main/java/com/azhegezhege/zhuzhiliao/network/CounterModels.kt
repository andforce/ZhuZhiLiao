package com.azhegezhege.zhuzhiliao.network

data class CounterStats(val online: Int, val wahs: Int)

data class LeaderboardEntry(val code: String, val score: Int, val rank: Int)

data class LeaderboardSnapshot(
    val totalPlayers: Int,
    val entries: List<LeaderboardEntry>,
    val me: LeaderboardEntry?,
)

data class EarthBounds(
    val minLatitude: Double,
    val maxLatitude: Double,
    val minLongitude: Double,
    val maxLongitude: Double,
)

data class EarthNode(
    val kind: Kind,
    val id: String,
    val code: String?,
    val score: Int?,
    val latitude: Double,
    val longitude: Double,
    val userCount: Int?,
    val totalWahs: Int?,
    val activeCount: Int?,
    val activeUntil: Long?,
    val isMe: Boolean?,
    val containsMe: Boolean?,
) {
    enum class Kind { PLAYER, CLUSTER }
    val displayedWahs: Int get() = score ?: totalWahs ?: 0
    val displayedUsers: Int get() = userCount ?: 1
    val highlightsMe: Boolean get() = isMe == true || containsMe == true
    fun isActive(serverNow: Long): Boolean = activeUntil?.let { it > serverNow } ?: false
}

data class EarthSnapshot(
    val requestID: String,
    val serverTime: Long,
    val revision: Int,
    val nodes: List<EarthNode>,
)

data class PlayerIdentity(val id: String, val code: String, val token: String)

sealed interface CounterServerMessage {
    data class Stats(val value: CounterStats) : CounterServerMessage
    data class Player(
        val id: String,
        val code: String,
        val score: Int,
        val migrated: Boolean,
        val earthEnabled: Boolean,
        val locationCell: String?,
    ) : CounterServerMessage
    data class Migration(val score: Int) : CounterServerMessage
    data class Score(val score: Int, val lastWahAt: Long?) : CounterServerMessage
    data class Earth(val snapshot: EarthSnapshot) : CounterServerMessage
    data class EarthRevision(val revision: Int) : CounterServerMessage
    data object Other : CounterServerMessage
}
