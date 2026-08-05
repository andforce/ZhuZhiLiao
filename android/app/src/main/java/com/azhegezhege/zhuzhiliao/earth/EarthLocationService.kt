package com.azhegezhege.zhuzhiliao.earth

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class EarthLocationException(message: String) : Exception(message)

@Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
class EarthLocationService(private val context: Context) {
    private val manager = context.getSystemService(LocationManager::class.java)

    val canRefreshWithoutPrompt: Boolean
        get() = hasLocationPermission()

    suspend fun requestOneLocation(): Location {
        if (!hasLocationPermission()) throw EarthLocationException("没有位置权限，你仍然可以浏览哇声地球")
        val enabledProviders = manager.getProviders(true).toSet()
        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.FUSED_PROVIDER,
            LocationManager.GPS_PROVIDER,
        ).filter(enabledProviders::contains)
        val provider = providers.firstOrNull()
            ?: throw EarthLocationException("当前无法获取位置，请确认系统定位已开启")
        val now = SystemClock.elapsedRealtimeNanos()
        (providers + LocationManager.PASSIVE_PROVIDER)
            .distinct()
            .mapNotNull(::lastKnownLocation)
            .filter { location -> location.isRecentAndValid(now) }
            .maxByOrNull(Location::getElapsedRealtimeNanos)
            ?.let { return it }
        return try {
            withTimeout(LOCATION_TIMEOUT_MILLISECONDS) { requestCurrentLocation(provider) }
        } catch (_: TimeoutCancellationException) {
            throw EarthLocationException("定位超时，请确认系统定位可用后重试")
        }
    }

    @SuppressLint("MissingPermission")
    private fun lastKnownLocation(provider: String): Location? =
        runCatching { manager.getLastKnownLocation(provider) }.getOrNull()

    private suspend fun requestCurrentLocation(provider: String): Location =
        suspendCancellableCoroutine { continuation ->
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val signal = CancellationSignal()
                    continuation.invokeOnCancellation { signal.cancel() }
                    manager.getCurrentLocation(provider, signal, context.mainExecutor) { location ->
                        if (!continuation.isActive) return@getCurrentLocation
                        if (location == null) {
                            continuation.resumeWithException(EarthLocationException("当前无法获取位置，请稍后再试"))
                        } else continuation.resume(location)
                    }
                } else {
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            manager.removeUpdates(this)
                            if (continuation.isActive) continuation.resume(location)
                        }
                        override fun onProviderDisabled(provider: String) = Unit
                        override fun onProviderEnabled(provider: String) = Unit
                        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
                    }
                    continuation.invokeOnCancellation { manager.removeUpdates(listener) }
                    manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                }
            } catch (error: SecurityException) {
                continuation.resumeWithException(EarthLocationException("没有位置权限，你仍然可以浏览哇声地球"))
            }
        }

    private fun Location.isRecentAndValid(now: Long): Boolean {
        val age = now - elapsedRealtimeNanos
        return latitude.isFinite() && latitude in -90.0..90.0 &&
            longitude.isFinite() && longitude in -180.0..180.0 &&
            accuracy >= 0f && age in 0..MAX_CACHED_LOCATION_AGE_NANOSECONDS
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    companion object {
        private const val LOCATION_TIMEOUT_MILLISECONDS = 15_000L
        private const val MAX_CACHED_LOCATION_AGE_NANOSECONDS = 10L * 60L * 1_000_000_000L
    }
}
