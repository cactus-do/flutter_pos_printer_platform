package com.cactus.flutter_pos_printer_platform.usb

import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.ConcurrentHashMap

/**
 * Singleton to coordinate USB permission requests between UsbPrinter and UsbReceiver.
 * Uses CompletableDeferred to provide a "Future-like" experience.
 */
object UsbPermissionManager {
    private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()

    fun registerRequest(deviceName: String): CompletableDeferred<Boolean> {
        val deferred = CompletableDeferred<Boolean>()
        pendingRequests[deviceName] = deferred
        return deferred
    }

    fun handlePermissionResult(deviceName: String, granted: Boolean) {
        val deferred = pendingRequests.remove(deviceName)
        Log.d("UsbPermissionManager", "Result for $deviceName: $granted (hasPending=${deferred != null})")
        deferred?.complete(granted)
    }

    fun cancelAll() {
        pendingRequests.values.forEach { it.cancel() }
        pendingRequests.clear()
    }
}
