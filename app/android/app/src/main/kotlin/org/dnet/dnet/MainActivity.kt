package org.dnet.dnet

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val ASK_PERMISSIONS = 4101
        const val ASK_BLUETOOTH_ON = 4102
        const val PICK_FILE = 4103
        const val ASK_MICROPHONE = 4104
        const val ASK_WIFI_DIRECT = 4105
        const val ASK_LOCATION = 4106
        const val ASK_CALL_MICROPHONE = 4107
        const val ASK_CALL_CAMERA = 4108
        const val ASK_NOTIFICATIONS = 4109
    }

    private var direct: WifiDirect? = null

    /** What to do once the user has answered about Wi-Fi Direct. */
    private var directAfterAsking: Pair<() -> Unit, () -> Unit>? = null

    private var voice: VoiceNotes? = null

    private var call: CallAudio? = null

    /** A call waiting for the user to allow the microphone. */
    private var callAfterAsking: MethodChannel.Result? = null

    private var callCamera: CallCamera? = null

    /** A video call waiting for the user to allow the camera. */
    private var cameraAfterAsking: MethodChannel.Result? = null

    /** The recording waiting for the user to allow the microphone. */
    private var recordingAfterAsking: Pair<String, MethodChannel.Result>? = null

    /// The Dart call waiting for the user to choose a file.
    private var picking: MethodChannel.Result? = null

    private var nfc: NfcTap? = null

    private var locator: Locator? = null

    /** The Dart call waiting for the user to say whether the app may know where the phone is. */
    private var locatingAfterAsking: MethodChannel.Result? = null

    /** True once the user has been asked about location and said no. */
    private var refusedLocation = false

    // Kept for the whole run of the app, not per screen: see Background.
    private var radio: BleRadio? by Background::radio
    private var radioEvents: EventChannel.EventSink? by Background::radioEvents

    /** What the background notice says. Given by the app, in its own words. */
    private var noticeTitle: String by Background::noticeTitle
    private var noticeText: String by Background::noticeText

    /** The Dart call waiting for the user to answer a system question. */
    private var asking: MethodChannel.Result? = null

    /** True once the user has been asked for the permissions and said no. */
    private var refusedOnce = false

    /** The Dart call waiting for the user to allow notifications. */
    private var noticesAfterAsking: MethodChannel.Result? = null

    // One engine for the whole run of the app, not one per screen, so the
    // app goes on when its screen closes if the user lets it.
    override fun provideFlutterEngine(context: Context): FlutterEngine = Background.engine(context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Photos to send, with the phone's own camera app.
        flutterEngine.plugins.add(PhotoCamera())

        // Must match the channel name in lib/core/device_platform.dart.
        MethodChannel(messenger, "dnet/platform")
            .setMethodCallHandler { call, result ->
                try {
                    val dataDir = File(filesDir, "dnet")
                    when (call.method) {
                        "screenshots" -> {
                            // Off unless the user allows them. Also keeps
                            // the app's screen out of the recent-apps list.
                            if (call.argument<Boolean>("allowed") == true) {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                )
                            }
                            result.success(null)
                        }
                        "share" -> {
                            // Android's own sheet. The user picks where the
                            // text goes; the app is not told.
                            val send = Intent(Intent.ACTION_SEND)
                                .setType("text/plain")
                                .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                            startActivity(Intent.createChooser(send, null))
                            result.success(true)
                        }
                        "openLink" -> {
                            // A web link the user chose to open, after the
                            // app showed where it goes. The browser they
                            // use opens it; nothing else is accepted.
                            val link = Uri.parse(call.argument<String>("url") ?: "")
                            if (link.scheme == "http" || link.scheme == "https") {
                                try {
                                    startActivity(
                                        Intent(Intent.ACTION_VIEW, link)
                                            .addCategory(Intent.CATEGORY_BROWSABLE),
                                    )
                                    result.success(true)
                                } catch (e: ActivityNotFoundException) {
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        }
                        "pickFile" -> pickFile(result)
                        // Ordinary files, so other apps can open them.
                        // Removed with the app, and by Wipe everything.
                        "receivedDir" -> result.success(
                            (getExternalFilesDir("received") ?: File(filesDir, "received")).absolutePath,
                        )
                        "dataDir" -> result.success(dataDir.absolutePath)
                        "masterKey" -> result.success(
                            MasterKey(dataDir).loadOrCreate(
                                fresh = call.argument<Boolean>("fresh") == true,
                            ),
                        )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // The message is for logs. The app shows its own words.
                    result.error("key_guard", e.message, null)
                }
            }

        // Must match the channel name in lib/core/device_voice.dart.
        val voice = VoiceNotes(applicationContext)
        this.voice = voice
        MethodChannel(messenger, "dnet/voice").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> startRecording(voice, call.argument<String>("path")!!, result)
                    "stop" -> result.success(voice.stop())
                    "cancel" -> {
                        voice.cancel()
                        result.success(null)
                    }
                    "play" -> result.success(voice.play(call.argument<String>("path")!!))
                    "stopPlaying" -> {
                        voice.stopPlaying()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("voice", e.message, null)
            }
        }

        // Must match the channel name in lib/calls/call_audio.dart.
        val callChannel = MethodChannel(messenger, "dnet/call")
        val call = CallAudio(applicationContext) { block -> callChannel.invokeMethod("heard", block) }
        this.call = call
        callChannel.setMethodCallHandler { request, result ->
            try {
                when (request.method) {
                    "start" -> startCall(call, result)
                    "play" -> {
                        (request.arguments as? ByteArray)?.let { call.play(it) }
                        result.success(null)
                    }
                    "loudspeaker" -> {
                        call.loudspeaker(request.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    "stop" -> {
                        call.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("call", e.message, null)
            }
        }

        // Must match the channel name in lib/calls/call_camera.dart.
        val cameraChannel = MethodChannel(messenger, "dnet/camera")
        val callCamera = CallCamera(applicationContext) { jpeg, turns ->
            cameraChannel.invokeMethod("picture", mapOf("jpeg" to jpeg, "turns" to turns))
        }
        this.callCamera = callCamera
        // Sharing the screen in a call: see ScreenShare.kt.
        ScreenShare.attach(this, messenger)
        cameraChannel.setMethodCallHandler { request, result ->
            try {
                when (request.method) {
                    "start" -> startCamera(callCamera, result)
                    "stop" -> {
                        callCamera.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("camera", e.message, null)
            }
        }

        // Must match the channel name in lib/core/nfc_tap.dart.
        val nfcChannel = MethodChannel(messenger, "dnet/nfc")
        fun nfc(): NfcTap = nfc ?: NfcTap(
            this,
            { link -> nfcChannel.invokeMethod("read", link) },
            { nfcChannel.invokeMethod("given", null) },
        ).also { nfc = it }
        nfcChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "available" -> result.success(NfcTap.available(this))
                    "enabled" -> result.success(NfcTap.available(this) && nfc().enabled())
                    "start" -> {
                        nfc().start(call.argument<String>("link")!!)
                        result.success(true)
                    }
                    "stop" -> {
                        nfc?.stop()
                        result.success(null)
                    }
                    "settings" -> {
                        startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("nfc", e.message, null)
            }
        }

        // Must match the channel name in lib/core/device_location.dart.
        val locator = Locator(applicationContext)
        this.locator = locator
        MethodChannel(messenger, "dnet/location").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "find" -> locate(locator, result)
                    "settings" -> {
                        // Location switched off for the whole phone, or
                        // refused to the app for good.
                        val page = if (locator.allowed()) {
                            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                        }
                        startActivity(page)
                        result.success(null)
                    }
                    "openMap" -> {
                        // Whatever map app the user has. The app itself
                        // never looks the place up.
                        val lat = call.argument<Double>("lat")!!
                        val lon = call.argument<Double>("lon")!!
                        val place = Uri.parse("geo:$lat,$lon?q=$lat,$lon")
                        val opened = try {
                            startActivity(Intent(Intent.ACTION_VIEW, place))
                            true
                        } catch (e: ActivityNotFoundException) {
                            false
                        }
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("location", e.message, null)
            }
        }

        // Must match the channel name in lib/radio/direct_wifi.dart.
        val direct = WifiDirect(applicationContext)
        this.direct = direct
        MethodChannel(messenger, "dnet/direct").setMethodCallHandler { call, result ->
            // Android may answer more than once. Dart is told once.
            var answered = false
            fun answer(value: Any?) {
                if (!answered) {
                    answered = true
                    result.success(value)
                }
            }
            try {
                val network = call.argument<String>("network")
                val pass = call.argument<String>("pass")
                when (call.method) {
                    "host" -> whenWifiDirectAllowed(
                        direct,
                        { direct.host(network!!, pass!!, call.argument<String>("band")) { answer(it) } },
                        { answer(false) },
                    )
                    "join" -> whenWifiDirectAllowed(
                        direct,
                        { direct.join(network!!, pass!!) { answer(it) } },
                        { answer(null) },
                    )
                    "leave" -> direct.leave { answer(null) }
                    "quieter_band" -> answer(direct.quieterBand())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (!answered) {
                    answered = true
                    result.error("direct", e.message, null)
                }
            }
        }

        // Both must match the names in lib/radio/channel_radio.dart.
        EventChannel(messenger, "dnet/radio/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    radioEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    radioEvents = null
                }
            },
        )
        val app = applicationContext
        val radio = Background.radio ?: BleRadio(app) { event ->
            // While the radio is working, a notice keeps Android from
            // shutting the app down when it is not on screen.
            if (event["t"] == "state") {
                if (event["state"] == "on") {
                    LinkService.start(app, Background.noticeTitle, Background.noticeText)
                } else {
                    LinkService.stop(app)
                }
            }
            Background.radioEvents?.success(event)
        }
        this.radio = radio
        setUpNotices(flutterEngine)
        setUpRadioLink(messenger)
        MethodChannel(messenger, "dnet/radio").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        noticeTitle = call.argument<String>("notice_title") ?: ""
                        noticeText = call.argument<String>("notice_text") ?: ""
                        radio.start()
                        hearLocalNetwork(true)
                        result.success(null)
                    }
                    "stop" -> {
                        radio.stop()
                        hearLocalNetwork(false)
                        LinkService.stop(applicationContext)
                        result.success(null)
                    }
                    "send" -> {
                        radio.send(call.argument<Int>("link")!!, call.argument<List<ByteArray>>("frames")!!)
                        result.success(null)
                    }
                    "drop" -> {
                        radio.drop(call.argument<Int>("link")!!)
                        result.success(null)
                    }
                    "ask" -> ask(radio, result)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("radio", e.message, null)
            }
        }
    }

    /**
     * A LoRa radio on a USB cable or over Bluetooth LE. The Dart side
     * (lib/radio/lora/byte_link.dart) opens one link at a time and only
     * moves bytes through it; what they mean is Dart's business.
     */
    private var radioSerial: RadioSerial? by Background::radioSerial
    private var radioBle: RadioBle? by Background::radioBle
    private var radioLinkEvents: EventChannel.EventSink? by Background::radioLinkEvents

    private fun setUpRadioLink(messenger: io.flutter.plugin.common.BinaryMessenger) {
        // Both must match the names in lib/radio/lora/byte_link.dart.
        EventChannel(messenger, "dnet/radio_link/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    radioLinkEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    radioLinkEvents = null
                }
            },
        )
        MethodChannel(messenger, "dnet/radio_link").setMethodCallHandler { call, result ->
            try {
                val kind = call.argument<String>("kind") ?: ""
                when (call.method) {
                    "list" -> when (kind) {
                        "serial" -> result.success(serial().list())
                        "ble" -> ble().scan { result.success(it) }
                        else -> result.success(emptyList<Any>())
                    }
                    "open" -> {
                        val address = call.argument<String>("address") ?: ""
                        var answered = false
                        val answer = { ok: Boolean, why: String? ->
                            if (!answered) {
                                answered = true
                                if (ok) result.success(true) else result.error("open", why, null)
                            }
                        }
                        when (kind) {
                            "serial" -> serial().open(address, answer)
                            "ble" -> {
                                if (!ble().available()) {
                                    result.error("permanent", "this phone has no Bluetooth LE", null)
                                } else {
                                    ble().open(address, answer)
                                }
                            }
                            else -> result.error("permanent", "unknown kind of link", null)
                        }
                    }
                    "write" -> {
                        val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                        val ok = when (kind) {
                            "serial" -> radioSerial?.write(data) ?: false
                            "ble" -> radioBle?.write(data) ?: false
                            else -> false
                        }
                        if (ok) result.success(null) else result.error("write", "the link is closed", null)
                    }
                    "close" -> {
                        when (kind) {
                            "serial" -> radioSerial?.close(null)
                            "ble" -> radioBle?.close(null)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("radio_link", e.message, null)
            }
        }
    }

    /** The phone's own notifications; see Notices and lib/data/notices.dart. */
    private fun setUpNotices(engine: FlutterEngine) {
        val notices = Notices(applicationContext)
        // Must match the channel in lib/core/device_notices.dart.
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dnet/notices")
        Background.noticeChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "allowed" -> result.success(notices.allowed())
                    "ask" -> askNotifications(notices, result)
                    "show" -> {
                        notices.show(
                            call.argument<String>("key") ?: "",
                            call.argument<String>("kind") ?: "",
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        notices.cancel(call.argument<String>("key") ?: "")
                        result.success(null)
                    }
                    "cancelAll" -> {
                        notices.cancelAll()
                        result.success(null)
                    }
                    "keepRunning" -> {
                        Background.keepRunning = call.argument<Boolean>("on") == true
                        result.success(null)
                    }
                    "words" -> {
                        call.argument<String>("messages")?.let { Notices.messagesName = it }
                        call.argument<String>("calls")?.let { Notices.callsName = it }
                        result.success(null)
                    }
                    "launchKey" -> {
                        result.success(Background.launchKey)
                        Background.launchKey = null
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("notices", e.message, null)
            }
        }
        takeNotice(intent, running = engine.dartExecutor.isExecutingDart)
    }

    /**
     * Android 13 and later ask the user before an app may show
     * notifications. Earlier versions allow them unless switched off.
     */
    private fun askNotifications(notices: Notices, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || notices.allowed() || noticesAfterAsking != null) {
            result.success(notices.allowed())
            return
        }
        noticesAfterAsking = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), ASK_NOTIFICATIONS)
    }

    /**
     * If [intent] came from a tapped notice, tells the app which: at once
     * if it is running, or when it asks, if it is only starting.
     */
    private fun takeNotice(intent: Intent?, running: Boolean) {
        val key = intent?.getStringExtra(Notices.EXTRA_KEY) ?: return
        intent.removeExtra(Notices.EXTRA_KEY)
        val channel = Background.noticeChannel
        if (running && channel != null) {
            channel.invokeMethod("opened", key)
        } else {
            Background.launchKey = key
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeNotice(intent, running = true)
    }

    // Back from the first screen puts the app away rather than closing
    // it, while the user lets it go on in the background.
    override fun popSystemNavigator(): Boolean {
        if (Background.keepRunning) {
            moveTaskToBack(true)
            return true
        }
        return super.popSystemNavigator()
    }

    private fun serial(): RadioSerial = radioSerial ?: RadioSerial(applicationContext).also {
        it.onData = { bytes -> radioLinkEvents?.success(bytes) }
        it.onClosed = { why -> radioLinkEvents?.error("closed", why, null) }
        radioSerial = it
    }

    private fun ble(): RadioBle = radioBle ?: RadioBle(applicationContext).also {
        it.onData = { bytes -> radioLinkEvents?.success(bytes) }
        it.onClosed = { why -> radioLinkEvents?.error("closed", why, null) }
        radioBle = it
    }

    /**
     * Puts to the user whichever question stands between them and a working
     * radio. The answer is always theirs to give: this only opens the
     * system's own dialog or settings page.
     */
    private fun ask(radio: BleRadio, result: MethodChannel.Result) {
        if (asking != null) {
            result.success(false)
            return
        }
        when (radio.obstacle()) {
            "on" -> result.success(true)
            "noPermission" -> {
                val permissions = BleRadio.permissions()
                val mayAsk = !refusedOnce || permissions.any { shouldShowRequestPermissionRationale(it) }
                if (mayAsk) {
                    asking = result
                    requestPermissions(permissions, ASK_PERMISSIONS)
                } else {
                    // Android will not show the question again after "don't
                    // allow". The app's page in Settings is the only way.
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)),
                    )
                    result.success(false)
                }
            }
            "bluetoothOff" -> {
                asking = result
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), ASK_BLUETOOTH_ON)
            }
            "locationOff" -> {
                startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                result.success(false)
            }
            else -> result.success(false)
        }
    }

    private var networkLock: WifiManager.MulticastLock? by Background::networkLock

    /**
     * Android drops "who is there?" packets from the local network unless
     * an app holds this lock. Held only while the radio is running.
     */
    private fun hearLocalNetwork(on: Boolean) {
        runCatching {
            if (on && networkLock == null) {
                val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                networkLock = wifi.createMulticastLock("dnet").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } else if (!on) {
                networkLock?.release()
                networkLock = null
            }
        }
    }

    /**
     * Wi-Fi Direct needs the user's say-so. They are asked the first time
     * it is wanted, which is when a big file is about to move, and only
     * while the app is on screen: a question cannot be put from the
     * background. Without a yes, the file goes over Bluetooth as before.
     */
    private fun whenWifiDirectAllowed(direct: WifiDirect, run: () -> Unit, refuse: () -> Unit) {
        if (direct.allowed()) return run()
        if (directAfterAsking != null || !hasWindowFocus()) return refuse()
        directAfterAsking = Pair(run, refuse)
        requestPermissions(WifiDirect.permissions(), ASK_WIFI_DIRECT)
    }

    /**
     * Starts a voice message. The first time, Android asks the user whether
     * the app may use the microphone, and recording starts only if they say
     * yes. It is asked for here, when they press the button, and never
     * before.
     */
    private fun startRecording(voice: VoiceNotes, path: String, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(voice.start(path))
            return
        }
        if (recordingAfterAsking != null) {
            result.success(false)
            return
        }
        recordingAfterAsking = Pair(path, result)
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), ASK_MICROPHONE)
    }

    /**
     * Finds where the phone is, for a place the user is about to send. The
     * first time, Android asks the user whether the app may know; it is
     * asked here, when they choose to send one, and never before.
     */
    private fun locate(locator: Locator, result: MethodChannel.Result) {
        if (locatingAfterAsking != null) {
            result.success(mapOf("state" to "busy"))
            return
        }
        if (locator.allowed()) {
            found(locator, result)
            return
        }
        val mayAsk = !refusedLocation ||
            Locator.permissions().any { shouldShowRequestPermissionRationale(it) }
        if (!mayAsk) {
            // Android will not ask again after "don't allow".
            result.success(mapOf("state" to "denied"))
            return
        }
        locatingAfterAsking = result
        requestPermissions(Locator.permissions(), ASK_LOCATION)
    }

    private fun found(locator: Locator, result: MethodChannel.Result) {
        if (!locator.enabled()) {
            result.success(mapOf("state" to "off"))
            return
        }
        locator.find { place ->
            result.success(
                if (place == null) {
                    mapOf("state" to "none")
                } else {
                    mapOf(
                        "state" to "ok",
                        "lat" to place.latitude,
                        "lon" to place.longitude,
                        "accuracy" to if (place.hasAccuracy()) place.accuracy.toDouble() else 0.0,
                    )
                },
            )
        }
    }

    /**
     * Shows Android's own file chooser. The app sees only the one file the
     * user picks, and asks for no storage permission.
     */
    private fun pickFile(result: MethodChannel.Result) {
        if (picking != null) {
            result.success(null)
            return
        }
        picking = result
        val choose = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        @Suppress("DEPRECATION")
        startActivityForResult(choose, PICK_FILE)
    }

    /**
     * Android hands over a reference to the chosen file, not a path. The
     * core reads by path, so the file is copied into the app's own cache.
     * Done off the main thread: it may be large.
     */
    private fun copyPicked(uri: Uri) {
        val result = picking ?: return
        picking = null
        Thread {
            val path = runCatching {
                var name = "file"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { row ->
                    if (row.moveToFirst()) row.getString(0)?.let { name = it }
                }
                // Only the last part, so a name cannot place the copy
                // anywhere but this folder.
                name = name.substringAfterLast('/').substringAfterLast('\\').ifBlank { "file" }
                val folder = File(cacheDir, "outgoing").apply { mkdirs() }
                // Copies left from earlier sends are no longer needed.
                val weekAgo = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
                folder.listFiles()?.filter { it.lastModified() < weekAgo }?.forEach { it.delete() }
                val copy = File(folder, name)
                contentResolver.openInputStream(uri)!!.use { from ->
                    copy.outputStream().use { to -> from.copyTo(to) }
                }
                copy.absolutePath
            }.getOrNull()
            runOnUiThread { result.success(path) }
        }.start()
    }

    /**
     * Starts the microphone and speaker for a call. The first time, Android
     * asks the user whether the app may use the microphone; with a no, the
     * user still hears the call but is not heard.
     */
    private fun startCall(call: CallAudio, result: MethodChannel.Result) {
        fun started(mayRecord: Boolean) {
            val (mic, speaker) = call.start(mayRecord)
            result.success(mapOf("mic" to mic, "speaker" to speaker))
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            return started(true)
        }
        if (callAfterAsking != null) return started(false)
        callAfterAsking = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), ASK_CALL_MICROPHONE)
    }

    /**
     * Opens the camera for a video call. The first time, Android asks the
     * user whether the app may use it; with a no, the call goes on without
     * the user's picture.
     */
    private fun startCamera(camera: CallCamera, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            camera.start { result.success(it) }
            return
        }
        if (cameraAfterAsking != null) return result.success(false)
        cameraAfterAsking = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), ASK_CALL_CAMERA)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ASK_NOTIFICATIONS) {
            val result = noticesAfterAsking ?: return
            noticesAfterAsking = null
            result.success(Notices(applicationContext).allowed())
            return
        }
        if (requestCode == ASK_CALL_CAMERA) {
            val result = cameraAfterAsking ?: return
            cameraAfterAsking = null
            val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val camera = callCamera
            if (allowed && camera != null) camera.start { result.success(it) } else result.success(false)
            return
        }
        if (requestCode == ASK_CALL_MICROPHONE) {
            val result = callAfterAsking ?: return
            callAfterAsking = null
            val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val (mic, speaker) = call?.start(allowed) ?: Pair(false, false)
            result.success(mapOf("mic" to mic, "speaker" to speaker))
            return
        }
        if (requestCode == ASK_MICROPHONE) {
            val (path, result) = recordingAfterAsking ?: return
            recordingAfterAsking = null
            val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            result.success(allowed && voice?.start(path) == true)
            return
        }
        if (requestCode == ASK_LOCATION) {
            val result = locatingAfterAsking ?: return
            locatingAfterAsking = null
            val locator = locator
            if (locator != null && locator.allowed()) {
                found(locator, result)
            } else {
                refusedLocation = true
                result.success(mapOf("state" to "denied"))
            }
            return
        }
        if (requestCode == ASK_WIFI_DIRECT) {
            val (run, refuse) = directAfterAsking ?: return
            directAfterAsking = null
            if (direct?.allowed() == true) run() else refuse()
            return
        }
        if (requestCode != ASK_PERMISSIONS) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) refusedOnce = true
        asking?.success(granted)
        asking = null
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (ScreenShare.answered(requestCode, resultCode, data)) return
        if (requestCode == PICK_FILE) {
            val chosen = data?.data
            if (resultCode == RESULT_OK && chosen != null) {
                copyPicked(chosen)
            } else {
                picking?.success(null)
                picking = null
            }
            return
        }
        if (requestCode != ASK_BLUETOOTH_ON) return
        asking?.success(resultCode == RESULT_OK)
        asking = null
    }

    override fun onPause() {
        nfc?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        nfc?.resume()
    }

    override fun onDestroy() {
        nfc?.stop()
        nfc = null
        // The radios, the long-range link and the notice go on when the
        // user lets the app run in the background; otherwise they stop
        // with the screen, as they always did.
        val stays = Background.keepRunning
        if (!stays) {
            radioSerial?.dispose()
            radioSerial = null
            radioBle?.dispose()
            radioBle = null
            LinkService.stop(applicationContext)
            hearLocalNetwork(false)
            radio?.stop()
            radio = null
        }
        // A group is not left standing once the app is gone.
        direct?.leave {}
        direct = null
        voice?.close()
        voice = null
        call?.stop()
        call = null
        callCamera?.stop()
        callCamera = null
        // Nothing goes on being shared once the app is closed.
        ScreenShare.stop(this)
        noticesAfterAsking?.success(false)
        noticesAfterAsking = null
        super.onDestroy()
        // Closed for good: the engine goes too, and the next start is
        // a fresh one.
        if (!stays && isFinishing) Background.release()
    }
}
