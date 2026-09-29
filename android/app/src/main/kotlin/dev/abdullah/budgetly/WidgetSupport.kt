package dev.abdullah.budgetly

import android.app.PendingIntent
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

// Shared plumbing for the home-screen widgets. The Dart side pushes
// pre-formatted aggregate strings (see WidgetSnapshot); nothing is computed
// here.
internal object WidgetSupport {
    // Tapping opens the app, which goes through the normal app lock.
    fun openApp(context: Context, views: RemoteViews, rootId: Int) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(rootId, pending)
    }

    fun bindProgress(views: RemoteViews, prefs: SharedPreferences, okId: Int, overId: Int) {
        val show = prefs.getBoolean("show_bar", false)
        val over = prefs.getBoolean("over_budget", false)
        val progress = prefs.getInt("progress", 0)
        views.setViewVisibility(okId, if (show && !over) View.VISIBLE else View.GONE)
        views.setViewVisibility(overId, if (show && over) View.VISIBLE else View.GONE)
        views.setProgressBar(okId, 100, progress, false)
        views.setProgressBar(overId, 100, progress, false)
    }
}
