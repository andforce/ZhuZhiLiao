package com.azhegezhege.zhuzhiliao.earth

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Looper
import androidx.core.content.ContextCompat
import kotlinx.coroutines.suspendCancellableCoroutine
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
        val provider = when {
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            else -> throw EarthLocationException("当前无法获取位置，请稍后再试")
        }
        return suspendCancellableCoroutine { continuation ->
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
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
}
