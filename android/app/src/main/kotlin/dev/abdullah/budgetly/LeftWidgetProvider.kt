package dev.abdullah.budgetly

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Small widget: what is left to spend this month.
class LeftWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_left)
            views.setTextViewText(R.id.label, widgetData.getString("primary_label", ""))
            views.setTextViewText(R.id.value, widgetData.getString("primary_value", ""))
            views.setTextViewText(R.id.caption, widgetData.getString("month", ""))
            WidgetSupport.bindProgress(views, widgetData, R.id.bar_ok, R.id.bar_over)
            WidgetSupport.openApp(context, views, R.id.root)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
