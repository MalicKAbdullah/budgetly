package dev.abdullah.tally

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray

/**
 * Reads notifications on-device and queues any that look like a bank/wallet
 * transaction (e.g. Meezan SMS from 8079 shown by the messaging app). Nothing
 * is uploaded — the raw text is stored locally for Tally to parse + confirm.
 * The user must grant "notification access" in system settings for this to run.
 */
class CaptureListener : NotificationListenerService() {
    companion object {
        const val prefsName = "tally_capture"
        const val queueKey = "queue"
        private const val channelId = "tally_capture"
        private const val maxQueued = 50

        private val amountRe =
            Regex("(?i)(?:PKR|Rs\\.?)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)")

        fun looksLikeTxn(body: String): Boolean {
            val l = body.lowercase()
            val hasAmount = l.contains("pkr") || l.contains("rs ")
            val hasVerb = l.contains("sent to") ||
                l.contains("received from") ||
                l.contains("debited") ||
                l.contains("credited")
            return hasAmount && hasVerb
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val body = if (text.isNotBlank()) text else title
        if (body.isBlank() || !looksLikeTxn(body)) return
        enqueue(body)
        postNudge(body)
    }

    private fun enqueue(body: String) {
        val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(queueKey, "[]")) }
            .getOrElse { JSONArray() }
        for (i in 0 until arr.length()) {
            if (arr.optString(i) == body) return // already queued
        }
        arr.put(body)
        while (arr.length() > maxQueued) arr.remove(0)
        prefs.edit().putString(queueKey, arr.toString()).apply()
    }

    private fun postNudge(body: String) {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(
                channelId,
                "Captured transactions",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val amount = amountRe.find(body)?.groupValues?.getOrNull(1)
        val title =
            if (amount != null) "Transaction detected · PKR $amount" else "Transaction detected"
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText("Tap to review and add it in Tally.")
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        nm.notify(body.hashCode(), n)
    }
}
