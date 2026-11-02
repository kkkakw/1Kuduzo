package ru.kuduzo.kuduzo

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "kuduzo/vpn/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                KuduzoVpnService.events = events
                events?.success(KuduzoVpnService.lastStatus)
            }

            override fun onCancel(arguments: Any?) {
                KuduzoVpnService.events = null
            }
        })

        MethodChannel(messenger, "kuduzo/vpn").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    askNotificationPermission()
                    val intent = VpnService.prepare(this)
                    if (intent == null) {
                        result.success(true)
                    } else {
                        pendingPrepare = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQ_VPN)
                    }
                }
                "start" -> {
                    val config = call.argument<String>("config") ?: ""
                    val name = call.argument<String>("name") ?: "Kuduzo"
                    val i = Intent(this, KuduzoVpnService::class.java)
                        .setAction(KuduzoVpnService.ACTION_START)
                        .putExtra("config", config)
                        .putExtra("name", name)
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                    result.success(null)
                }
                "stop" -> {
                    val i = Intent(this, KuduzoVpnService::class.java).setAction(KuduzoVpnService.ACTION_STOP)
                    startService(i)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
        }
    }

    companion object {
        private const val REQ_VPN = 1001
        private const val REQ_NOTIF = 1002
    }
}
