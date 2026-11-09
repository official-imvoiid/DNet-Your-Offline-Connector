package org.dnet.dnet

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * What outlives the app's screen.
 *
 * Android closes an activity when the user swipes the app away or presses
 * back on its first screen. If the app ran inside the activity, it would
 * stop there: no more finding people, no more messages. So the Flutter
 * engine, which runs the app, and the radios it uses are kept here, for
 * the whole run of the app's process, and each new screen joins them
 * instead of starting its own.
 *
 * Whether they go on once the screen is gone is the user's choice: "Keep
 * running in the background" on the Privacy screen, which the app passes
 * on as [keepRunning]. While they do, [LinkService] shows a notice saying
 * so, which is also what keeps Android from stopping the process.
 */
object Background {
    private var engine: FlutterEngine? = null

    /** Whether the app goes on once its screen is gone. Told by the app. */
    @Volatile
    var keepRunning = false

    // The radios and where they report to.
    var radio: BleRadio? = null
    var radioEvents: EventChannel.EventSink? = null
    var radioSerial: RadioSerial? = null
    var radioBle: RadioBle? = null
    var radioLinkEvents: EventChannel.EventSink? = null
    var networkLock: WifiManager.MulticastLock? = null

    /** What the radio's notice says, in the app's own words. */
    var noticeTitle = ""
    var noticeText = ""

    /** Where tapped notifications are told to the app. */
    var noticeChannel: MethodChannel? = null

    /** The notification the app was opened from, until the app asks. */
    var launchKey: String? = null

    /** The one engine, made the first time a screen asks for it. */
    fun engine(context: Context): FlutterEngine =
        engine ?: FlutterEngine(context.applicationContext).also { engine = it }

    /**
     * The app is closed for good: the engine goes, and the radios, which
     * the screen has already stopped, are forgotten. The next start begins
     * afresh.
     */
    fun release() {
        radio = null
        radioEvents = null
        radioSerial = null
        radioBle = null
        radioLinkEvents = null
        networkLock = null
        noticeChannel = null
        engine?.destroy()
        engine = null
    }
}
