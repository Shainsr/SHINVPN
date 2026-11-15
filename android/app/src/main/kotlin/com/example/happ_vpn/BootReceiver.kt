package com.example.happ_vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
            val autoConnect = prefs.getBoolean("flutter.auto_connect_on_boot", false)
            val hasConfig = !prefs.getString("flutter.native_ready_config", "").isNullOrEmpty()

            prefs.edit()
                .putBoolean("flutter.bg_vpn_connected", false)
                .putString("flutter.bg_vpn_status", "DISCONNECTED")
                .apply()

            VpnHomeWidgetProvider.updateAllWidgets(context)
            VpnQuickSettingsTileService.requestTileSync(context)

            if (autoConnect && hasConfig) {
                try {
                    val launchIntent = Intent(context, MainActivity::class.java).apply {
                        this.action = MainActivity.ACTION_QUICK_TOGGLE_VPN
                        putExtra("quick_toggle_vpn", true)
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        )
                    }
                    context.startActivity(launchIntent)
                } catch (_: Exception) {}
            }
        }
    }
}
