package ru.kuduzo.kuduzo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.plugin.common.EventChannel
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress

/**
 * Системный VPN: Android отдаёт TUN-дескриптор, Xray-core (libv2ray.aar) читает из него пакеты
 * и отправляет их на сервер. Собственное приложение исключено из VPN, чтобы соединения ядра
 * с сервером не заворачивались обратно в туннель.
 */
class KuduzoVpnService : VpnService() {

    companion object {
        const val ACTION_START = "ru.kuduzo.vpn.START"
        const val ACTION_STOP = "ru.kuduzo.vpn.STOP"
        private const val CHANNEL_ID = "kuduzo_vpn"
        private const val NOTIF_ID = 1
        private const val TAG = "KuduzoVpn"

        @Volatile
        var events: EventChannel.EventSink? = null

        @Volatile
        var lastStatus: String = "disconnected"

        private val main = Handler(Looper.getMainLooper())

        fun emit(status: String) {
            lastStatus = status
            main.post { events?.success(status) }
        }

        @Volatile
        private var current: KuduzoVpnService? = null

        private const val PREFS = "kuduzo_vpn"

        /** «Постоянный VPN» и «Блокировать соединения без VPN» (Android 10+, когда VPN работает). */
        fun alwaysOnState(): Map<String, Boolean>? {
            val s = current ?: return null
            if (Build.VERSION.SDK_INT < 29) return null
            return mapOf("alwaysOn" to s.isAlwaysOn, "lockdown" to s.isLockdownEnabled)
        }

        /** Трафик с прошлого запроса: «proxy,uplink,123;proxy,downlink,456;». */
        fun queryStats(): String = try {
            current?.core?.queryAllOutboundTrafficStats() ?: ""
        } catch (e: Throwable) {
            ""
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private val lock = Any()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Thread { stopVpn() }.start()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = intent.getStringExtra("config") ?: return START_NOT_STICKY
                val name = intent.getStringExtra("name") ?: "Kuduzo"
                val splitMode = intent.getStringExtra("splitMode") ?: "all"
                val splitApps = intent.getStringArrayListExtra("splitApps") ?: arrayListOf()
                val tunnelText = intent.getStringExtra("tunnel") ?: "{}"
                // Запоминаем подключение: его возьмёт система, если включён «Постоянный VPN».
                getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putString("config", config)
                    .putString("name", name)
                    .putString("splitMode", splitMode)
                    .putString("splitApps", JSONArray(splitApps).toString())
                    .putString("tunnel", tunnelText)
                    .apply()
                launch(config, name, splitMode, splitApps, tunnelText)
            }
            else -> {
                // Запуск системой: «Постоянный VPN» в настройках Android или включение из шторки.
                val p = getSharedPreferences(PREFS, MODE_PRIVATE)
                val config = p.getString("config", null)
                if (config.isNullOrEmpty()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                val apps = try {
                    val a = JSONArray(p.getString("splitApps", "[]"))
                    ArrayList((0 until a.length()).map { a.optString(it) })
                } catch (_: Exception) { arrayListOf() }
                launch(config, p.getString("name", null) ?: "Kuduzo", p.getString("splitMode", null) ?: "all",
                    apps, p.getString("tunnel", null) ?: "{}")
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    private fun launch(config: String, name: String, splitMode: String, splitApps: List<String>, tunnelText: String) {
        val tunnel = try { JSONObject(tunnelText) } catch (_: Exception) { JSONObject() }
        showNotification(name)
        current = this
        Thread { startVpn(config, splitMode, splitApps, tunnel) }.start()
    }

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).map { optString(it).trim() }.filter { it.isNotEmpty() }
    }

    /// «10.0.0.0/8» → (адрес, длина префикса).
    private fun cidr(s: String): Pair<String, Int>? {
        val p = s.trim().split("/")
        val a = p[0].trim()
        if (a.isEmpty()) return null
        val def = if (a.contains(":")) 128 else 32
        return a to (p.getOrNull(1)?.trim()?.toIntOrNull() ?: def)
    }

    private fun startVpn(config: String, splitMode: String, splitApps: List<String>, tunnel: JSONObject) {
        synchronized(lock) {
            stopCore()
            emit("connecting")
            try {
                Libv2ray.initCoreEnv(filesDir.absolutePath, "")

                val mtu = tunnel.optInt("mtu", 1500)
                val dns = tunnel.optString("dns", "1.1.1.1").ifEmpty { "1.1.1.1" }
                val included = tunnel.optJSONArray("includedRoutes").strings().mapNotNull { cidr(it) }
                val excluded = tunnel.optJSONArray("excludedRoutes").strings().mapNotNull { cidr(it) }

                val builder = Builder()
                    .setSession("Kuduzo")
                    .setMtu(mtu)
                    .addAddress("198.18.0.1", 30)
                try {
                    builder.addDnsServer(dns)
                } catch (e: Exception) {
                    builder.addDnsServer("1.1.1.1")
                }
                val in4 = included.filter { !it.first.contains(":") }
                val in6 = included.filter { it.first.contains(":") }
                if (included.isEmpty()) {
                    builder.addRoute("0.0.0.0", 0)
                } else {
                    for ((a, l) in in4) {
                        try { builder.addRoute(a, l) } catch (e: Exception) { Log.w(TAG, "маршрут $a/$l: ${e.message}") }
                    }
                }
                try {
                    builder.addAddress("fd66:6b75:6475::1", 126)
                    if (included.isEmpty()) {
                        builder.addRoute("::", 0)
                    } else {
                        for ((a, l) in in6) {
                            try { builder.addRoute(a, l) } catch (e: Exception) { Log.w(TAG, "маршрут $a/$l: ${e.message}") }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "IPv6 недоступен: ${e.message}")
                }
                // Исключённые маршруты (Android 13+).
                if (Build.VERSION.SDK_INT >= 33) {
                    for ((a, l) in excluded) {
                        try {
                            builder.excludeRoute(IpPrefix(InetAddress.getByName(a), l))
                        } catch (e: Exception) {
                            Log.w(TAG, "исключение $a/$l: ${e.message}")
                        }
                    }
                }
                // Раздельное туннелирование. Своё приложение всегда мимо VPN — иначе ядро зациклится.
                val chosen = splitApps.filter { it != packageName }
                if (splitMode == "only" && chosen.isNotEmpty()) {
                    for (p in chosen) {
                        try { builder.addAllowedApplication(p) } catch (_: Exception) { }
                    }
                } else {
                    builder.addDisallowedApplication(packageName)
                    if (splitMode == "except") {
                        for (p in chosen) {
                            try { builder.addDisallowedApplication(p) } catch (_: Exception) { }
                        }
                    }
                }
                if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)

                val pfd = builder.establish() ?: throw IllegalStateException("Система не дала создать VPN")
                tun = pfd

                val c = Libv2ray.newCoreController(object : CoreCallbackHandler {
                    override fun startup(): Long = 0
                    override fun shutdown(): Long = 0
                    override fun onEmitStatus(p0: Long, p1: String?): Long {
                        Log.i(TAG, "core: $p1")
                        return 0
                    }
                })
                c.startLoop(config, pfd.fd)
                core = c
                emit("connected")
            } catch (e: Throwable) {
                Log.e(TAG, "start failed", e)
                emit("error:" + (e.message ?: e.javaClass.simpleName))
                stopCore()
                stopSelfCompat()
            }
        }
    }

    private fun stopCore() {
        try {
            core?.stopLoop()
        } catch (e: Throwable) {
            Log.w(TAG, "stopLoop: ${e.message}")
        }
        core = null
        try {
            tun?.close()
        } catch (_: Throwable) {
        }
        tun = null
    }

    private fun stopVpn() {
        synchronized(lock) {
            stopCore()
            emit("disconnected")
            stopSelfCompat()
        }
    }

    private fun stopSelfCompat() {
        main.post {
            if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    override fun onRevoke() {
        // Пользователь включил другой VPN или отключил наш в настройках.
        Thread { stopVpn() }.start()
    }

    override fun onDestroy() {
        synchronized(lock) { stopCore() }
        if (current === this) current = null
        if (lastStatus != "disconnected" && !lastStatus.startsWith("error")) emit("disconnected")
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun stopAction(pi: PendingIntent): Notification.Action =
        Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "Выключить", pi).build()

    private fun showNotification(serverName: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, KuduzoVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Kuduzo включён")
            .setContentText(serverName)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(stopAction(stop))
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
