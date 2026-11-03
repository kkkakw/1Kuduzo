package ru.kuduzo.kuduzo

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterActivity
import libv2ray.Libv2ray
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
                    val splitMode = call.argument<String>("splitMode") ?: "all"
                    val splitApps = ArrayList(call.argument<List<String>>("splitApps") ?: emptyList())
                    val tunnel = call.argument<String>("tunnelJson") ?: "{}"
                    val i = Intent(this, KuduzoVpnService::class.java)
                        .setAction(KuduzoVpnService.ACTION_START)
                        .putExtra("config", config)
                        .putExtra("name", name)
                        .putExtra("splitMode", splitMode)
                        .putStringArrayListExtra("splitApps", splitApps)
                        .putExtra("tunnel", tunnel)
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                    result.success(null)
                }
                "stop" -> {
                    val i = Intent(this, KuduzoVpnService::class.java).setAction(KuduzoVpnService.ACTION_STOP)
                    startService(i)
                    result.success(null)
                }
                "stats" -> result.success(KuduzoVpnService.queryStats())
                "coreVersion" -> result.success(try { Libv2ray.checkVersionX() } catch (e: Throwable) { null })
                "alwaysOn" -> result.success(KuduzoVpnService.alwaysOnState())
                "openVpnSettings" -> {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_VPN_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "proxyPing" -> {
                    // Пинг через прокси: временное ядро на каждый сервер. Приложение исключено из VPN,
                    // поэтому замер идёт напрямую к серверу.
                    @Suppress("UNCHECKED_CAST")
                    val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                    val url = call.argument<String>("url") ?: "https://www.gstatic.com/generate_204"
                    Thread {
                        val out = java.util.concurrent.ConcurrentHashMap<String, Long>()
                        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
                        for (item in items) {
                            val id = item["id"] as? String ?: continue
                            val config = item["config"] as? String ?: continue
                            pool.execute {
                                out[id] = try { Libv2ray.measureOutboundDelay(config, url) } catch (e: Throwable) { -1L }
                            }
                        }
                        pool.shutdown()
                        pool.awaitTermination(60, java.util.concurrent.TimeUnit.SECONDS)
                        Handler(Looper.getMainLooper()).post { result.success(HashMap(out)) }
                    }.start()
                }
                "logs" -> Thread {
                    val lines = readLogs()
                    Handler(Looper.getMainLooper()).post { result.success(lines) }
                }.start()
                "apps" -> Thread {
                    val list = try { launcherApps() } catch (e: Exception) { emptyList() }
                    Handler(Looper.getMainLooper()).post { result.success(list) }
                }.start()
                else -> result.notImplemented()
            }
        }
    }

    /** Последние строки журнала своего процесса (ядро Xray пишет в logcat). */
    private fun readLogs(): List<String> = try {
        val p = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-t", "300", "--pid=" + android.os.Process.myPid()))
        p.inputStream.bufferedReader().readLines()
            .filter { it.contains("GoLog") || it.contains("KuduzoVpn") || it.contains("libv2ray") || it.contains("Xray") }
            .ifEmpty { listOf("Журнал пуст — включите VPN и откройте снова") }
    } catch (e: Exception) {
        listOf("Не удалось прочитать журнал: ${e.message}")
    }

    /** Приложения с ярлыком: пакет, название, иконка 64×64 PNG. */
    private fun launcherApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val acts = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any?>>()
        for (ri in acts) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val label = ri.loadLabel(pm).toString()
            val icon: ByteArray? = try {
                val d = ri.loadIcon(pm)
                val bmp = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                val c = Canvas(bmp)
                d.setBounds(0, 0, 64, 64)
                d.draw(c)
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                bos.toByteArray()
            } catch (e: Exception) { null }
            out.add(mapOf("pkg" to pkg, "label" to label, "icon" to icon))
        }
        return out
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
