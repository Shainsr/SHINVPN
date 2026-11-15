package com.example.happ_vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class VpnActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == MainActivity.ACTION_SAFE_DISCONNECT_VPN) {
            VpnBackgroundController.triggerDisconnect(context, goAsync())
        }
    }
}
