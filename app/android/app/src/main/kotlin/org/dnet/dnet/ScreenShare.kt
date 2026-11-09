package org.dnet.dnet

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * Sharing the screen during a call.
 *
 * Nothing is looked at until the user says yes to Android's own question,
 * which names the app and, on newer Android, lets them pick one app
 * instead of the whole screen. While sharing, a notice says so, with a
 * button to stop; sharing also stops when the call ends or the app is
 * closed. Pictures are kept in memory only, and only as long as needed to
 * send them.
 *
 * The screen goes out in pieces, as on a PC (`screen.rs`): the picture is
 * cut into squares and only squares that changed since they were last sent
 * are squeezed into JPEG, as fast as the app allows. Sealing and sending
 * them are the core's work and the app's.
 *
 * Not yet verified on devices.
 */
object ScreenShare {
    private const val ASK_SCREEN = 4120

    // Must match lib/calls/screen_share.dart.
    private const val CHANNEL = "dnet/screen"

    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null

    /** The Dart call waiting for the user to answer Android's question. */
    private var asking: MethodChannel.Result? = null

    /** The user's yes, waiting for the notice to go up before it is used. */
    private var allowed: Pair<Int, Intent>? = null
    private var notice = Triple("", "", "")
    private var widest = 1080

    /** False once the app says stop: a yes that comes after that is not used. */
    @Volatile
    private var wanted = false

    private var capture: Capture? = null

    /** "off", "starting", "on", or "ended" (stopped from the notice, or by Android). */
    @Volatile
    var state = "off"
        private set

    @Volatile
    private var rate = 300_000

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        this.activity = activity
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Android asks the user what to share itself.
                    "sources" -> result.success(listOf(mapOf("id" to "screen", "kind" to "screen")))
                    "start" -> {
                        notice = Triple(
                            call.argument<String>("title").orEmpty(),
                            call.argument<String>("text").orEmpty(),
                            call.argument<String>("stop").orEmpty(),
                        )
                        widest = call.argument<Int>("width") ?: widest
                        rate = call.argument<Int>("bytes") ?: rate
                        ask(result)
                    }
                    "rate" -> {
                        rate = (call.argument<Int>("bytes") ?: rate).coerceIn(8_000, 20_000_000)
                        result.success(null)
                    }
                    "refresh" -> {
                        capture?.refresh()
                        result.success(null)
                    }
                    "take" -> result.success(take())
                    "stop" -> {
                        stop(activity)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("screen", e.message, null)
            }
        }
    }

    private fun ask(result: MethodChannel.Result) {
        val activity = activity ?: return result.success(false)
        if (asking != null) return result.success(false)
        stop(activity)
        val manager = activity.getSystemService(MediaProjectionManager::class.java)
        asking = result
        wanted = true
        state = "starting"
        activity.startActivityForResult(manager.createScreenCaptureIntent(), ASK_SCREEN)
    }

    /** Hears the user's answer. True if the answer was to this. */
    fun answered(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != ASK_SCREEN) return false
        val activity = activity
        if (resultCode != Activity.RESULT_OK || data == null || activity == null || !wanted) {
            state = "off"
            reply(false)
            return true
        }
        // Android lets the yes be used only once a notice says the screen
        // is being shared: the service puts it up, then calls [noticeUp].
        allowed = Pair(resultCode, data)
        val started = runCatching {
            activity.startForegroundService(
                Intent(activity, ScreenShareService::class.java)
                    .putExtra(ScreenShareService.TITLE, notice.first)
                    .putExtra(ScreenShareService.TEXT, notice.second)
                    .putExtra(ScreenShareService.STOP_LABEL, notice.third),
            )
        }
        if (started.isFailure) {
            allowed = null
            state = "off"
            reply(false)
        }
        return true
    }

    /** The notice is up: sharing can begin. */
    internal fun noticeUp(service: Service) {
        val (code, data) = allowed ?: return
        allowed = null
        if (!wanted) {
            service.stopSelf()
            return
        }
        val worked = runCatching {
            val manager = service.getSystemService(MediaProjectionManager::class.java)
            val projection = manager.getMediaProjection(code, data) ?: error("no projection")
            capture = Capture(service, projection, widest)
        }.isSuccess
        state = if (worked) "on" else "off"
        if (!worked) service.stopSelf()
        main.post { reply(worked) }
    }

    /** The notice could not be put up. */
    internal fun noticeFailed() {
        allowed = null
        state = "off"
        main.post { reply(false) }
    }

    private fun reply(worked: Boolean) {
        asking?.success(worked)
        asking = null
    }

    /** Stopped from the notice, or by Android: the app hears on its next look. */
    internal fun ended() {
        capture?.close()
        capture = null
        if (state == "on") state = "ended"
    }

    fun stop(context: Context?) {
        wanted = false
        capture?.close()
        capture = null
        allowed = null
        state = "off"
        reply(false)
        context?.let { it.stopService(Intent(it, ScreenShareService::class.java)) }
    }

    private fun take(): Map<String, Any> {
        val pieces = capture?.drain().orEmpty().map {
            mapOf(
                "gen" to it.gen,
                "width" to it.width,
                "height" to it.height,
                "x" to it.x,
                "y" to it.y,
                "w" to it.w,
                "h" to it.h,
                "jpeg" to it.jpeg,
            )
        }
        return mapOf("state" to state, "pieces" to pieces)
    }

    internal val bytesPerSecond get() = rate

    /** One square, ready to send: see `screen.rs`. */
    class Piece(
        val gen: Int,
        val width: Int,
        val height: Int,
        val x: Int,
        val y: Int,
        val w: Int,
        val h: Int,
        val jpeg: ByteArray,
    )

    /** Mirrors the screen into memory and cuts it into squares, on a thread of its own. */
    private class Capture(context: Context, private val projection: MediaProjection, widest: Int) {
        private companion object {
            const val TILE = 192
            const val MOST_BYTES = 15 * 1024 - 32
            const val EVERY_MS = 200L
            const val BURST = 0.5
            val QUALITIES = intArrayOf(72, 55, 40)

            /** Changes with each sharing, so squares of an earlier one are never mixed in. */
            var nextGen = (Math.random() * 0xffff).toInt()
        }

        private val thread = HandlerThread("screen-share").apply { start() }
        private val handler = Handler(thread.looper)
        private val width: Int
        private val height: Int
        private val reader: ImageReader
        private val display: VirtualDisplay
        private val gen = nextGen++ and 0xffff
        private var lastAt = 0L
        private var allowance = 0.0

        /** The newest picture as it came, its pixels for comparing, and as a bitmap for squeezing. */
        private var bytes: ByteBuffer? = null
        private var pixels = IntArray(0)
        private var picture: Bitmap? = null
        private var fresh = false
        private var padded = 0
        private var sent = IntArray(0)
        private var now = IntArray(0)
        private val ready = ArrayList<Piece>()

        @Volatile
        private var refreshing = false

        @Volatile
        private var closed = false

        init {
            val metrics = context.resources.displayMetrics
            val scale = minOf(1.0, widest.toDouble() / metrics.widthPixels)
            width = (metrics.widthPixels * scale).toInt() / 2 * 2
            height = (metrics.heightPixels * scale).toInt() / 2 * 2
            // Android asks for word of a stop before anything is shown.
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    ended()
                }
            }, handler)
            reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            reader.setOnImageAvailableListener({ look() }, handler)
            display = projection.createVirtualDisplay(
                "dnet-share",
                width,
                height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                handler,
            ) ?: run {
                // Android would not mirror the screen: nothing is left running.
                reader.close()
                thread.quitSafely()
                error("the screen could not be mirrored")
            }
            val columns = (width + TILE - 1) / TILE
            val rows = (height + TILE - 1) / TILE
            sent = IntArray(columns * rows)
            now = IntArray(columns * rows)
            tick()
        }

        /** Spends what may go even when nothing new is drawn, so waiting squares go out. */
        private fun tick() {
            if (closed) return
            spend()
            handler.postDelayed({ tick() }, EVERY_MS)
        }

        fun refresh() {
            refreshing = true
        }

        private fun look() {
            val image = runCatching { reader.acquireLatestImage() }.getOrNull() ?: return
            try {
                val at = SystemClock.elapsedRealtime()
                if (closed || at - lastAt < EVERY_MS) return
                lastAt = at
                val plane = image.planes[0]
                val across = plane.rowStride / plane.pixelStride
                if (across != padded || bytes == null) {
                    padded = across
                    bytes = ByteBuffer.allocateDirect(padded * height * 4)
                    pixels = IntArray(padded * height)
                    picture?.recycle()
                    picture = Bitmap.createBitmap(padded, height, Bitmap.Config.ARGB_8888)
                }
                // The last row may come without its padding, so the copy
                // goes into a buffer of the full size.
                val copy = bytes!!
                val from = plane.buffer
                copy.clear()
                if (from.remaining() > copy.capacity()) from.limit(from.position() + copy.capacity())
                copy.put(from)
                copy.rewind()
                copy.asIntBuffer().get(pixels, 0, minOf(pixels.size, copy.capacity() / 4))
                fresh = true
                for (index in now.indices) {
                    val (x, y, w, h) = rect(index)
                    var hash = -0x7ee3623b
                    for (line in y until y + h) {
                        val start = line * padded + x
                        for (i in start until start + w) hash = (hash xor pixels[i]) * 0x01000193
                    }
                    // Never 0, which means "never sent".
                    now[index] = hash or 1
                }
            } finally {
                image.close()
            }
        }

        private fun rect(index: Int): IntArray {
            val columns = (width + TILE - 1) / TILE
            val x = index % columns * TILE
            val y = index / columns * TILE
            return intArrayOf(x, y, minOf(TILE, width - x), minOf(TILE, height - y))
        }

        private fun spend() {
            val full = picture ?: return
            if (fresh && sent.indices.any { sent[it] != now[it] }) {
                bytes?.let {
                    it.rewind()
                    full.copyPixelsFromBuffer(it)
                }
                fresh = false
            }
            if (refreshing) {
                refreshing = false
                sent.fill(0)
            }
            val rate = bytesPerSecond.toDouble()
            allowance = minOf(allowance + rate * EVERY_MS / 1000.0, rate * BURST)
            val made = ArrayList<Piece>()
            for (index in now.indices) {
                if (allowance <= 0) break
                if (sent[index] == now[index]) continue
                val (x, y, w, h) = rect(index)
                val pieces = squeeze(full, x, y, w, h)
                if (pieces.isEmpty()) continue
                allowance -= pieces.sumOf { it.jpeg.size }
                sent[index] = now[index]
                made.addAll(pieces)
            }
            if (made.isNotEmpty()) synchronized(ready) { ready.addAll(made) }
        }

        private fun squeeze(full: Bitmap, x: Int, y: Int, w: Int, h: Int): List<Piece> {
            val part = Bitmap.createBitmap(full, x, y, w, h)
            try {
                for (quality in QUALITIES) {
                    val out = ByteArrayOutputStream()
                    part.compress(Bitmap.CompressFormat.JPEG, quality, out)
                    if (out.size() <= MOST_BYTES) {
                        return listOf(Piece(gen, width, height, x, y, w, h, out.toByteArray()))
                    }
                }
            } finally {
                if (part !== full) part.recycle()
            }
            if (w < 16 || h < 16) return emptyList()
            val (hw, hh) = Pair(w / 2, h / 2)
            return squeeze(full, x, y, hw, hh) + squeeze(full, x + hw, y, w - hw, hh) +
                squeeze(full, x, y + hh, hw, h - hh) + squeeze(full, x + hw, y + hh, w - hw, h - hh)
        }

        fun drain(): List<Piece> = synchronized(ready) {
            val out = ArrayList(ready)
            ready.clear()
            out
        }

        fun close() {
            if (closed) return
            closed = true
            runCatching { display.release() }
            runCatching { projection.stop() }
            runCatching { reader.close() }
            handler.post {
                picture?.recycle()
                picture = null
                bytes = null
                pixels = IntArray(0)
                synchronized(ready) { ready.clear() }
            }
            thread.quitSafely()
        }
    }
}

/**
 * The notice Android requires while the screen is shared. It does nothing
 * itself; its Stop button stops the sharing.
 */
class ScreenShareService : Service() {
    companion object {
        const val TITLE = "title"
        const val TEXT = "text"
        const val STOP_LABEL = "stop"
        private const val STOP = "org.dnet.dnet.STOP_SHARING"
        private const val CHANNEL = "screen"
        private const val NOTICE = 42
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            ScreenShare.ended()
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(TITLE).orEmpty()
        val text = intent?.getStringExtra(TEXT).orEmpty()
        val stopLabel = intent?.getStringExtra(STOP_LABEL).orEmpty()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            // Low importance: no sound, no pop-up. The notice itself is enough.
            NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, ScreenShareService::class.java).setAction(STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notice = Notification.Builder(this, CHANNEL)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, stopLabel, stop).build())
            .build()
        val up = runCatching {
            startForeground(NOTICE, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        }
        if (up.isSuccess) {
            ScreenShare.noticeUp(this)
        } else {
            ScreenShare.noticeFailed()
            stopSelf()
        }
        // If Android stops the app, sharing is not started again behind the user's back.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        ScreenShare.ended()
        super.onDestroy()
    }
}
