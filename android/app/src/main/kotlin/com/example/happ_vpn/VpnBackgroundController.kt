
package com.example.happ_vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

object VpnBackgroundController {
    private const val CHANNEL = "com.example.happ_vpn/quick_controls"
    private val isHeadlessRunning = AtomicBoolean(false)

    fun triggerDisconnect(context: Context, pendingResult: BroadcastReceiver.PendingResult?) {
        val mainHandler = Handler(Looper.getMainLooper())
        mainHandler.post {
            val ch = MainActivity.activeChannel
            if (ch != null) {
                try {
                    ch.invokeMethod("safeDisconnectVpn", null)
                } catch (_: Exception) {}
                pendingResult?.finish()
            } else {
                runHeadlessDart(context.applicationContext, "vpnBackgroundDisconnect", pendingResult)
            }
        }
    }

    fun triggerToggle(context: Context, pendingResult: BroadcastReceiver.PendingResult?) {
        val mainHandler = Handler(Looper.getMainLooper())
        mainHandler.post {
            val ch = MainActivity.activeChannel
            if (ch != null) {
                try {
                    ch.invokeMethod("quickToggleVpn", null)
                } catch (_: Exception) {}
                pendingResult?.finish()
            } else {
                runHeadlessDart(context.applicationContext, "vpnBackgroundMain", pendingResult)
            }
        }
    }

    private fun runHeadlessDart(
        appContext: Context,
        entrypoint: String,
        pendingResult: BroadcastReceiver.PendingResult?
    ) {
        if (!isHeadlessRunning.compareAndSet(false, true)) {
            pendingResult?.finish()
            return
        }

        val mainHandler = Handler(Looper.getMainLooper())
        var engine: FlutterEngine? = null
        var finished = false

        fun cleanup() {
            if (finished) return
            finished = true
            try {
                engine?.destroy()
            } catch (_: Exception) {}
            engine = null
            isHeadlessRunning.set(false)
            try {
                pendingResult?.finish()
            } catch (_: Exception) {}
        }

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(appContext)
            loader.ensureInitializationComplete(appContext, null)
            val appBundlePath = loader.findAppBundlePath()

            val bgEngine = FlutterEngine(appContext)
            engine = bgEngine

            val channel = MethodChannel(bgEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setConnectionState" -> {
                        val connected = call.argument<Boolean>("connected") ?: false
                        val status = call.argument<String>("status")
                            ?: if (connected) "CONNECTED" else "DISCONNECTED"
                        val prefs = appContext.getSharedPreferences(
                            MainActivity.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        prefs.edit()
                            .putBoolean("flutter.bg_vpn_connected", connected)
                            .putString("flutter.bg_vpn_status", status)
                            .apply()
                        VpnHomeWidgetProvider.updateAllWidgets(appContext)
                        VpnQuickSettingsTileService.requestTileSync(appContext)
                        result.success(true)
                    }
                    "backgroundTaskDone" -> {
                        result.success(true)
                        mainHandler.postDelayed({ cleanup() }, 300)
                    }
                    else -> result.notImplemented()
                }
            }

            bgEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(appBundlePath, entrypoint)
            )

            // تایم‌اوت اطمینان برای آزادسازی حافظه در صورت بروز خطا
            mainHandler.postDelayed({ cleanup() }, 8000)
        } catch (_: Exception) {
            cleanup()
        }
    }
}
