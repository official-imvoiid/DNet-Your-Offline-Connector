package org.dnet.dnet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * Keeps the app alive while it is finding people nearby and not on screen.
 *
 * Android stops apps it cannot see. A service with a visible notice is the
 * way an app says "I am still doing something the user asked for". This one
 * does nothing itself: the radio lives in the activity. It runs only while
 * the radio is working, and stops when the radio stops or the app is
 * closed.
 *
 * Not yet verified on devices.
 */
class LinkService : Service() {
    companion object {
        private const val CHANNEL = "links"
        private const val NOTICE = 41
        private const val TITLE = "title"
        private const val TEXT = "text"

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, LinkService::class.java).putExtra(TITLE, title).putExtra(TEXT, text)
            // Android refuses this if the app is not on screen at the time.
            // Then there is simply no notice, and the radio runs for as
            // long as Android lets the app be.
            runCatching { context.startForegroundService(intent) }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(TITLE).orEmpty()
        val text = intent?.getStringExtra(TEXT).orEmpty()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            // Low importance: no sound, no pop-up.
            NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notice = Notification.Builder(this, CHANNEL)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        runCatching {
            startForeground(NOTICE, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        }.onFailure { stopSelf() }
        // If Android does stop the app, it is not to be started again
        // behind the user's back.
        return START_NOT_STICKY
    }
}
