package dev.abdullah.budgetly

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Medium widget: month spend vs budget, top three categories, owed to you.
class OverviewWidgetProvider : HomeWidgetProvider() {
    private val rows = listOf(
        Triple(R.id.cat0, R.id.cat0_name, R.id.cat0_amount),
        Triple(R.id.cat1, R.id.cat1_name, R.id.cat1_amount),
        Triple(R.id.cat2, R.id.cat2_name, R.id.cat2_amount),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_overview)
            views.setTextViewText(R.id.month, widgetData.getString("month", ""))
            views.setTextViewText(R.id.spent, widgetData.getString("spent_value", ""))
            views.setTextViewText(R.id.budget, widgetData.getString("budget_value", ""))
            views.setTextViewText(R.id.owed, widgetData.getString("owed_value", ""))
            WidgetSupport.bindProgress(views, widgetData, R.id.bar_ok, R.id.bar_over)
            rows.forEachIndexed { i, (row, name, amount) ->
                val label = widgetData.getString("cat${i}_name", "")
                views.setViewVisibility(row, if (label.isNullOrEmpty()) View.GONE else View.VISIBLE)
                views.setTextViewText(name, label)
                views.setTextViewText(amount, widgetData.getString("cat${i}_amount", ""))
            }
            WidgetSupport.openApp(context, views, R.id.root)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
