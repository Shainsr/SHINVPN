package com.example.happ_vpn

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VpnQuickSettingsTileService : TileService() {

    companion object {
        fun requestTileSync(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    requestListeningState(
                        context,
                        ComponentName(context, VpnQuickSettingsTileService::class.java)
                    )
                } catch (_: Exception) {}
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        syncTileState()
    }

    override fun onClick() {
        super.onClick()
        VpnBackgroundController.triggerToggle(applicationContext, null)
    }

    private fun syncTileState() {
        val tile = qsTile ?: return
        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val connected = prefs.getBoolean("flutter.bg_vpn_connected", false)
        val remark = prefs.getString("flutter.native_ready_remark", "SHIN") ?: "SHIN"

        tile.state = if (connected) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "SHIN"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (connected) remark else "Disconnected"
        }
        tile.updateTile()
    }
}
