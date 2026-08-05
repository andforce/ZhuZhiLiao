package com.azhegezhege.zhuzhiliao.network

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow

class CounterService(context: Context) {
    private val preferences = context.getSharedPreferences("zhuzhiliao", Context.MODE_PRIVATE)
    private val identityStore = PlayerIdentityStore(context)
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .pingInterval(30, TimeUnit.SECONDS)
        .build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val identityMutex = Mutex()
    @Volatile private var identity = identityStore.load()
    @Volatile private var socket: WebSocket? = null
    @Volatile private var flushJob: Job? = null
    @Volatile private var heartbeatJob: Job? = null
    @Volatile private var reconnectJob: Job? = null
    @Volatile private var isStarted = false
    @Volatile private var isMigrated = false
    @Volatile private var migrationInFlight = false
    @Volatile private var scoreInFlight = false
    @Volatile private var serverScore = 0
    @Volatile private var reconnectAttempt = 0
    private val earthRequests = ConcurrentHashMap<String, CompletableDeferred<EarthSnapshot>>()

    @Volatile var stats = CounterStats(0, 0); private set
    @Volatile var personalWahs = preferences.getInt(KEY_PERSONAL, 0); private set
    @Volatile var publicCode: String? = identity?.code; private set
    @Volatile var earthIsEnabled = preferences.getBoolean(KEY_EARTH_ENABLED, false); private set
    @Volatile var earthCellID: String? = preferences.getString(KEY_EARTH_CELL, null); private set
    @Volatile var stateListener: (() -> Unit)? = null
    @Volatile var earthRevisionListener: ((Int) -> Unit)? = null

    init {
        if (identity == null) preferences.edit().putBoolean(KEY_MIGRATION_CAPTURED, false).apply()
        captureMigrationIfNeeded()
    }

    @Synchronized
    fun start() {
        if (isStarted) return
        isStarted = true
        connect()
        flushJob = scope.launch {
            while (isActive) {
                delay(1_200)
                flushPendingWahs()
            }
        }
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(25_000)
                socket?.send("ping")
            }
        }
    }

    @Synchronized
    fun stop() {
        isStarted = false
        flushJob?.cancel(); flushJob = null
        heartbeatJob?.cancel(); heartbeatJob = null
        reconnectJob?.cancel(); reconnectJob = null
        closeSocket()
    }

    fun release() {
        stop()
        scope.cancel()
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }

    @Synchronized
    fun record(wahs: Int) {
        if (wahs <= 0) return
        personalWahs += wahs
        preferences.edit().putInt(KEY_PERSONAL, personalWahs).apply()
        notifyState()
    }

    suspend fun loadLeaderboard(): LeaderboardSnapshot {
        val identity = ensureIdentity()
        val request = Request.Builder()
            .url("$BASE_URL/api/leaderboard?limit=100")
            .header("Authorization", "Bearer ${identity.token}")
            .build()
        return execute(request, setOf(200)) { response -> CounterCodec.leaderboard(response.body!!.string()) }
    }

    suspend fun resetAnonymousIdentity() {
        val oldIdentity = ensureIdentity()
        val request = Request.Builder()
            .url("$BASE_URL/api/players/me")
            .delete()
            .header("Authorization", "Bearer ${oldIdentity.token}")
            .build()
        execute(request, setOf(204, 401)) { Unit }
        closeSocket()
        identityStore.delete()
        synchronized(this) {
            identity = null
            publicCode = null
            personalWahs = 0
            serverScore = 0
            isMigrated = false
            earthIsEnabled = false
            earthCellID = null
            preferences.edit()
                .putInt(KEY_PERSONAL, 0)
                .putInt(KEY_PENDING_GLOBAL, 0)
                .putBoolean(KEY_MIGRATION_CAPTURED, false)
                .remove(KEY_MIGRATION_PERSONAL)
                .putBoolean(KEY_EARTH_ENABLED, false)
                .remove(KEY_EARTH_CELL)
                .apply()
            captureMigrationIfNeeded()
        }
        ensureIdentity()
        notifyState()
        restartConnection()
    }

    suspend fun setEarthLocation(cellID: String) {
        val identity = ensureIdentity()
        val body = JSONObject().put("enabled", true).put("cellID", cellID).toString()
            .toRequestBody(JSON)
        val request = Request.Builder()
            .url("$BASE_URL/api/players/me/earth")
            .put(body)
            .header("Authorization", "Bearer ${identity.token}")
            .build()
        val responseValue = execute(request, setOf(200)) { JSONObject(it.body!!.string()) }
        earthIsEnabled = responseValue.getBoolean("enabled")
        earthCellID = responseValue.getString("cellID")
        preferences.edit()
            .putBoolean(KEY_EARTH_ENABLED, earthIsEnabled)
            .putString(KEY_EARTH_CELL, earthCellID)
            .apply()
        notifyState()
    }

    suspend fun disableEarth() {
        val identity = ensureIdentity()
        val request = Request.Builder()
            .url("$BASE_URL/api/players/me/earth")
            .delete()
            .header("Authorization", "Bearer ${identity.token}")
            .build()
        execute(request, setOf(204)) { Unit }
        earthIsEnabled = false
        earthCellID = null
        preferences.edit().putBoolean(KEY_EARTH_ENABLED, false).remove(KEY_EARTH_CELL).apply()
        notifyState()
    }

    suspend fun loadEarthSnapshot(detail: Int, bounds: List<EarthBounds> = emptyList()): EarthSnapshot {
        val activeSocket = socket ?: throw IOException("正在连接服务器，请稍后重试")
        val requestID = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<EarthSnapshot>()
        earthRequests[requestID] = deferred
        if (!activeSocket.send(CounterCodec.earthView(requestID, detail, bounds))) {
            earthRequests.remove(requestID)
            throw IOException("正在连接服务器，请稍后重试")
        }
        return try {
            withTimeout(8_000) { deferred.await() }
        } finally {
            earthRequests.remove(requestID)
        }
    }

    @Synchronized
    private fun connect() {
        if (!isStarted || socket != null || reconnectJob?.isActive == true) return
        scope.launch {
            runCatching {
                val identity = ensureIdentity()
                synchronized(this@CounterService) {
                    if (!isStarted || socket != null) return@launch
                    val request = Request.Builder()
                        .url("$WS_URL/api/ws")
                        .header("Authorization", "Bearer ${identity.token}")
                        .build()
                    socket = client.newWebSocket(request, listener)
                }
            }.onFailure { scheduleReconnect() }
        }
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            synchronized(this@CounterService) {
                if (webSocket === socket) reconnectAttempt = 0
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            runCatching { CounterCodec.decode(text) }.getOrNull()?.let(::handle)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (webSocket === socket) {
                closeSocket()
                scheduleReconnect()
            }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (webSocket === socket) {
                closeSocket()
                scheduleReconnect()
            }
        }
    }

    @Synchronized
    private fun handle(message: CounterServerMessage) {
        when (message) {
            is CounterServerMessage.Stats -> stats = message.value
            is CounterServerMessage.Player -> {
                publicCode = message.code
                serverScore = message.score
                personalWahs = maxOf(personalWahs, message.score)
                earthIsEnabled = message.earthEnabled
                earthCellID = message.locationCell
                preferences.edit()
                    .putInt(KEY_PERSONAL, personalWahs)
                    .putBoolean(KEY_EARTH_ENABLED, earthIsEnabled)
                    .apply { if (earthCellID == null) remove(KEY_EARTH_CELL) else putString(KEY_EARTH_CELL, earthCellID) }
                    .apply()
                isMigrated = message.migrated
                if (message.migrated) {
                    finishMigration()
                } else if (!migrationInFlight) {
                    migrationInFlight = true
                    val migrationPersonal = preferences.getInt(KEY_MIGRATION_PERSONAL, personalWahs)
                    val pendingGlobal = preferences.getInt(KEY_PENDING_GLOBAL, 0)
                    if (socket?.send(CounterCodec.migration(migrationPersonal, pendingGlobal)) != true) {
                        migrationInFlight = false
                    }
                }
            }
            is CounterServerMessage.Migration -> {
                migrationInFlight = false
                serverScore = message.score
                personalWahs = maxOf(personalWahs, message.score)
                preferences.edit().putInt(KEY_PERSONAL, personalWahs).apply()
                isMigrated = true
                finishMigration()
            }
            is CounterServerMessage.Score -> {
                serverScore = message.score
                scoreInFlight = false
            }
            is CounterServerMessage.Earth -> earthRequests.remove(message.snapshot.requestID)?.complete(message.snapshot)
            is CounterServerMessage.EarthRevision -> earthRevisionListener?.invoke(message.revision)
            CounterServerMessage.Other -> Unit
        }
        notifyState()
    }

    @Synchronized
    private fun flushPendingWahs() {
        val activeSocket = socket ?: return
        if (!isMigrated || scoreInFlight || serverScore >= personalWahs) return
        scoreInFlight = true
        val target = min(personalWahs, serverScore + 30)
        if (!activeSocket.send(CounterCodec.score(target))) scoreInFlight = false
    }

    private suspend fun ensureIdentity(): PlayerIdentity = identityMutex.withLock {
        identity?.let { return@withLock it }
        val request = Request.Builder()
            .url("$BASE_URL/api/players")
            .post(ByteArray(0).toRequestBody(null))
            .build()
        val created = execute(request, setOf(201)) { CounterCodec.playerIdentity(it.body!!.string()) }
        identityStore.save(created)
        identity = created
        publicCode = created.code
        notifyState()
        created
    }

    @Synchronized
    private fun scheduleReconnect() {
        if (!isStarted || reconnectJob?.isActive == true) return
        val delayMillis = (min(30.0, 2.0.pow(reconnectAttempt.toDouble())) * 1_000).toLong()
        reconnectAttempt += 1
        reconnectJob = scope.launch {
            delay(delayMillis)
            synchronized(this@CounterService) { reconnectJob = null }
            connect()
        }
    }

    @Synchronized
    private fun restartConnection() {
        closeSocket()
        reconnectJob?.cancel(); reconnectJob = null
        reconnectAttempt = 0
        connect()
    }

    @Synchronized
    private fun closeSocket() {
        socket?.close(1001, null)
        socket = null
        earthRequests.values.forEach { it.completeExceptionally(IOException("正在连接服务器，请稍后重试")) }
        earthRequests.clear()
        migrationInFlight = false
        scoreInFlight = false
        isMigrated = false
    }

    private fun notifyState() = stateListener?.invoke()

    private fun captureMigrationIfNeeded() {
        if (preferences.getBoolean(KEY_MIGRATION_CAPTURED, false)) return
        preferences.edit()
            .putInt(KEY_MIGRATION_PERSONAL, personalWahs)
            .putBoolean(KEY_MIGRATION_CAPTURED, true)
            .apply()
    }

    private fun finishMigration() {
        preferences.edit()
            .putInt(KEY_PENDING_GLOBAL, 0)
            .remove(KEY_MIGRATION_PERSONAL)
            .apply()
    }

    private suspend fun <T> execute(
        request: Request,
        acceptedStatus: Set<Int>,
        transform: (Response) -> T,
    ): T = withContext(Dispatchers.IO) {
        client.newCall(request).execute().use { response ->
            if (response.code !in acceptedStatus) throw IOException("服务器暂时不可用（${response.code}）")
            transform(response)
        }
    }

    companion object {
        private const val BASE_URL = "https://zhuzhiliao.aimfor.top"
        private const val WS_URL = "wss://zhuzhiliao.aimfor.top"
        private const val KEY_PERSONAL = "zzl_mywah"
        private const val KEY_PENDING_GLOBAL = "zzl_pending_wah"
        private const val KEY_MIGRATION_CAPTURED = "zzl_rank_migration_captured"
        private const val KEY_MIGRATION_PERSONAL = "zzl_rank_migration_personal"
        private const val KEY_EARTH_ENABLED = "zzl_earth_enabled"
        private const val KEY_EARTH_CELL = "zzl_earth_cell"
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
