package org.dnet.dnet

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * The phone's own notifications for what arrives while DNet is not on
 * screen: messages, chat requests, mentions in spaces and calls.
 *
 * The app decides what to say and when (lib/data/notices.dart); this only
 * shows it, takes it away, and brings the user back to the app with the
 * notice's key when they tap it. Each notice is filed under its key, so a
 * newer one about the same chat replaces the older.
 *
 * On the lock screen a notice shows only that DNet has something: what it
 * says stays hidden until the phone is unlocked.
 */
class Notices(private val context: Context) {
    companion object {
        /** Carries a notice's key to the app when the user taps it. */
        const val EXTRA_KEY = "org.dnet.dnet.notice"

        private const val MESSAGES = "messages"
        private const val CALLS = "calls"

        /** Every notice has this number; its key is its tag. */
        private const val ID = 7

        /** The names of the two kinds, as the user's settings list them. */
        var messagesName = "Messages"
        var callsName = "Calls"
    }

    private val manager = context.getSystemService(NotificationManager::class.java)

    /** Whether Android lets the app show notifications. */
    fun allowed(): Boolean =
        manager.areNotificationsEnabled() &&
            (
                Build.VERSION.SDK_INT < 33 ||
                    context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                )

    private fun channels() {
        manager.createNotificationChannel(
            NotificationChannel(MESSAGES, messagesName, NotificationManager.IMPORTANCE_HIGH),
        )
        manager.createNotificationChannel(
            NotificationChannel(CALLS, callsName, NotificationManager.IMPORTANCE_HIGH),
        )
    }

    fun show(key: String, kind: String, title: String, text: String) {
        if (!allowed()) return
        channels()
        val open = PendingIntent.getActivity(
            context,
            key.hashCode(),
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val call = kind == "call"
        val notice = Notification.Builder(context, if (call) CALLS else MESSAGES)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(R.drawable.ic_notice)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(if (call) Notification.CATEGORY_CALL else Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        runCatching { manager.notify(key, ID, notice) }
    }

    fun cancel(key: String) {
        runCatching { manager.cancel(key, ID) }
    }

    /** Takes away every notice of the app's, not the radio's own. */
    fun cancelAll() {
        runCatching {
            for (shown in manager.activeNotifications) {
                if (shown.id == ID) manager.cancel(shown.tag, ID)
            }
        }
    }
}
