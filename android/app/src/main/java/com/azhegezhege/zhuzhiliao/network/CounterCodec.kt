package com.azhegezhege.zhuzhiliao.network

import org.json.JSONArray
import org.json.JSONObject

object CounterCodec {
    fun score(value: Int): String = JSONObject()
        .put("t", "score")
        .put("value", value.coerceAtLeast(0))
        .toString()

    fun migration(personal: Int, pendingGlobal: Int): String = JSONObject()
        .put("t", "migrate")
        .put("personal", personal.coerceAtLeast(0))
        .put("pendingGlobal", pendingGlobal.coerceIn(0, personal.coerceAtLeast(0)))
        .toString()

    fun earthView(requestID: String, detail: Int, bounds: List<EarthBounds>): String {
        val boxes = JSONArray()
        bounds.forEach { bound ->
            boxes.put(
                JSONObject()
                    .put("minLatitude", bound.minLatitude)
                    .put("maxLatitude", bound.maxLatitude)
                    .put("minLongitude", bound.minLongitude)
                    .put("maxLongitude", bound.maxLongitude),
            )
        }
        return JSONObject()
            .put("t", "earth_view")
            .put("requestID", requestID)
            .put("detail", detail.coerceIn(0, 4))
            .put("bounds", boxes)
            .toString()
    }

    fun decode(text: String): CounterServerMessage {
        val objectValue = JSONObject(text)
        return when (objectValue.optString("t")) {
            "stats" -> CounterServerMessage.Stats(
                CounterStats(objectValue.getInt("online"), objectValue.getInt("wahs")),
            )
            "player" -> CounterServerMessage.Player(
                id = objectValue.getString("id"),
                code = objectValue.getString("code"),
                score = objectValue.getInt("score"),
                migrated = objectValue.optBoolean("migrated"),
                earthEnabled = objectValue.optBoolean("earthEnabled"),
                locationCell = objectValue.nullableString("locationCell"),
            )
            "migration" -> CounterServerMessage.Migration(objectValue.getInt("score"))
            "score" -> CounterServerMessage.Score(
                objectValue.getInt("score"),
                objectValue.nullableLong("lastWahAt"),
            )
            "earth_snapshot" -> CounterServerMessage.Earth(objectValue.toEarthSnapshot())
            "earth_revision" -> CounterServerMessage.EarthRevision(objectValue.getInt("revision"))
            else -> CounterServerMessage.Other
        }
    }

    fun leaderboard(text: String): LeaderboardSnapshot {
        val root = JSONObject(text)
        val entries = root.getJSONArray("entries").objects().map { it.toLeaderboardEntry() }.toList()
        val me = root.optJSONObject("me")?.toLeaderboardEntry()
        return LeaderboardSnapshot(root.getInt("totalPlayers"), entries, me)
    }

    fun playerIdentity(text: String): PlayerIdentity {
        val root = JSONObject(text)
        return PlayerIdentity(root.getString("id"), root.getString("code"), root.getString("token"))
    }

    private fun JSONObject.toEarthSnapshot(): EarthSnapshot = EarthSnapshot(
        requestID = getString("requestID"),
        serverTime = getLong("serverTime"),
        revision = getInt("revision"),
        nodes = getJSONArray("nodes").objects().map { node ->
            EarthNode(
                kind = if (node.getString("kind") == "player") EarthNode.Kind.PLAYER else EarthNode.Kind.CLUSTER,
                id = node.getString("id"),
                code = node.nullableString("code"),
                score = node.nullableInt("score"),
                latitude = node.getDouble("latitude"),
                longitude = node.getDouble("longitude"),
                userCount = node.nullableInt("userCount"),
                totalWahs = node.nullableInt("totalWahs"),
                activeCount = node.nullableInt("activeCount"),
                activeUntil = node.nullableLong("activeUntil"),
                isMe = node.nullableBoolean("isMe"),
                containsMe = node.nullableBoolean("containsMe"),
            )
        }.toList(),
    )

    private fun JSONObject.toLeaderboardEntry() = LeaderboardEntry(
        code = getString("code"),
        score = getInt("score"),
        rank = getInt("rank"),
    )
}

private fun JSONArray.objects(): Sequence<JSONObject> = sequence {
    for (index in 0 until length()) yield(getJSONObject(index))
}

private fun JSONObject.hasValue(key: String): Boolean = has(key) && !isNull(key)
private fun JSONObject.nullableString(key: String): String? = if (hasValue(key)) getString(key) else null
private fun JSONObject.nullableInt(key: String): Int? = if (hasValue(key)) getInt(key) else null
private fun JSONObject.nullableLong(key: String): Long? = if (hasValue(key)) getLong(key) else null
private fun JSONObject.nullableBoolean(key: String): Boolean? = if (hasValue(key)) getBoolean(key) else null
