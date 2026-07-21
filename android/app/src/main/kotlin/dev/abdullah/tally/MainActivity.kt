package dev.abdullah.tally

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tally/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(listenerEnabled())
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "getPending" -> result.success(readQueue())
                    "removePending" -> {
                        removeFromQueue(call.argument<String>("text"))
                        result.success(null)
                    }
                    "clearPending" -> {
                        prefs().edit().remove(CaptureListener.queueKey).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prefs() =
        getSharedPreferences(CaptureListener.prefsName, Context.MODE_PRIVATE)

    private fun listenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.split(":").any { it.contains(packageName) }
    }

    private fun readQueue(): List<String> {
        val arr = runCatching {
            JSONArray(prefs().getString(CaptureListener.queueKey, "[]"))
        }.getOrElse { JSONArray() }
        return (0 until arr.length()).map { arr.optString(it) }
    }

    private fun removeFromQueue(text: String?) {
        if (text == null) return
        val kept = readQueue().filter { it != text }
        prefs().edit()
            .putString(CaptureListener.queueKey, JSONArray(kept).toString())
            .apply()
    }
}
