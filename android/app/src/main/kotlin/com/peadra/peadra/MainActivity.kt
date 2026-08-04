package com.peadra.peadra

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL = "com.peadra.sync/multicast_lock"
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        val lock = getMulticastLock()
                        if (lock == null) {
                            result.error("no_wifi_service", "WifiManager unavailable", null)
                        } else {
                            if (!lock.isHeld) {
                                lock.acquire()
                            }
                            result.success(true)
                        }
                    }
                    "release" -> {
                        multicastLock?.let {
                            if (it.isHeld) {
                                it.release()
                            }
                            multicastLock = null
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getMulticastLock(): WifiManager.MulticastLock? {
        multicastLock?.let { return it }
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val lock = wifiManager?.createMulticastLock("peadra-sync")
        lock?.setReferenceCounted(false)
        multicastLock = lock
        return lock
    }
}
