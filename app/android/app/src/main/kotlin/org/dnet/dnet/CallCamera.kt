package org.dnet.dnet

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executor
import kotlin.math.abs

/**
 * The camera during a video call.
 *
 * Takes small pictures from the front camera, a few a second, and squeezes
 * each into a JPEG small enough for one frame on a fast link. It says how
 * many quarter turns each needs to stand upright, as the camera sits
 * sideways in most phones. Nothing is written to disk. Sealing and sending
 * the pictures are the core's work and the app's.
 *
 * Not yet verified on devices.
 */
class CallCamera(private val context: Context, private val picture: (ByteArray, Int) -> Unit) {
    private companion object {
        /** The largest picture worth handing over: see call_camera.dart. */
        const val MOST_BYTES = 15 * 1024 - 1

        /** About eight pictures a second. */
        const val EVERY_MS = 120L
    }

    private val main = Handler(Looper.getMainLooper())
    private var thread: HandlerThread? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var lastAt = 0L

    /** Which opening this is, so a camera stopped in the meantime stays quiet. */
    @Volatile
    private var turn = 0

    /**
     * Opens the camera. [done] hears once whether it could be. The caller
     * has checked the camera permission.
     */
    @SuppressLint("MissingPermission")
    fun start(done: (Boolean) -> Unit) {
        stop()
        val mine = ++turn
        var told = false
        fun tell(worked: Boolean) {
            main.post {
                if (!told) {
                    told = true
                    done(worked)
                }
            }
        }
        try {
            val cameras = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cameras.cameraIdList.firstOrNull {
                cameras.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
            } ?: cameras.cameraIdList.firstOrNull()
            if (id == null) {
                tell(false)
                return
            }
            val traits = cameras.getCameraCharacteristics(id)
            val sensor = traits.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val sizes = traits.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(ImageFormat.YUV_420_888)
            val size = sizes?.minByOrNull { abs(it.width - 320) + abs(it.height - 240) }
            if (size == null) {
                tell(false)
                return
            }
            val worker = HandlerThread("call-camera").apply { start() }
            thread = worker
            val handler = Handler(worker.looper)
            val images = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
            reader = images
            images.setOnImageAvailableListener({ from ->
                val image = from.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastAt >= EVERY_MS && mine == turn) {
                        lastAt = now
                        val jpeg = squeeze(image)
                        if (jpeg != null) main.post { if (mine == turn) picture(jpeg, sensor / 90) }
                    }
                } finally {
                    image.close()
                }
            }, handler)
            val onWorker = Executor { handler.post(it) }
            cameras.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    if (mine != turn) {
                        camera.close()
                        return
                    }
                    device = camera
                    val ready = object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(made: CameraCaptureSession) {
                            session = made
                            try {
                                val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                request.addTarget(images.surface)
                                made.setRepeatingRequest(request.build(), null, handler)
                                tell(true)
                            } catch (e: Exception) {
                                tell(false)
                            }
                        }

                        override fun onConfigureFailed(made: CameraCaptureSession) {
                            tell(false)
                        }
                    }
                    camera.createCaptureSession(
                        SessionConfiguration(
                            SessionConfiguration.SESSION_REGULAR,
                            listOf(OutputConfiguration(images.surface)),
                            onWorker,
                            ready,
                        ),
                    )
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    if (device == camera) device = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    if (device == camera) device = null
                    tell(false)
                }
            }, handler)
        } catch (e: Exception) {
            // In use by another app, or not allowed.
            stop()
            tell(false)
        }
    }

    /** Turns NV21 out of the camera's YUV, then JPEG small enough to send. */
    private fun squeeze(image: Image): ByteArray? {
        val width = image.width
        val height = image.height
        val nv21 = ByteArray(width * height * 3 / 2)
        val (y, u, v) = Triple(image.planes[0], image.planes[1], image.planes[2])
        var at = 0
        val luma = y.buffer
        for (row in 0 until height) {
            luma.position(row * y.rowStride)
            luma.get(nv21, at, width)
            at += width
        }
        val (blue, red) = Pair(u.buffer, v.buffer)
        for (row in 0 until height / 2) {
            for (column in 0 until width / 2) {
                nv21[at++] = red.get(row * v.rowStride + column * v.pixelStride)
                nv21[at++] = blue.get(row * u.rowStride + column * u.pixelStride)
            }
        }
        val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        for (quality in intArrayOf(55, 40, 28)) {
            val out = ByteArrayOutputStream()
            yuv.compressToJpeg(Rect(0, 0, width, height), quality, out)
            if (out.size() <= MOST_BYTES) return out.toByteArray()
        }
        return null
    }

    /** Closes the camera. Nothing is kept. */
    fun stop() {
        turn++
        runCatching { session?.close() }
        session = null
        runCatching { device?.close() }
        device = null
        runCatching { reader?.close() }
        reader = null
        thread?.quitSafely()
        thread = null
    }
}
