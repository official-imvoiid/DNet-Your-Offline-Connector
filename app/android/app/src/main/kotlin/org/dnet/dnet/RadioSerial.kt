package org.dnet.dnet

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A LoRa radio on a USB serial cable (an OTG adapter on a phone), reached
 * through Android's USB host API with no third-party library. The three
 * kinds of serial bridge the common boards use are handled:
 *
 * - CDC-ACM (the ESP32-S3 boards' own USB, RAK WisBlock, nRF52 boards):
 *   a control interface and a data interface, data on bulk endpoints.
 * - Silicon Labs CP210x (many Heltec and LILYGO boards): one interface,
 *   bulk endpoints, the speed set with vendor requests.
 * - WCH CH340 / CH341 (the cheapest boards): one interface, bulk
 *   endpoints, the speed set with vendor requests.
 *
 * The app only moves bytes through this; what they mean is Dart's
 * business (`byte_link.dart`). Hot-plug: a device pulled out ends the
 * link, and Dart is told; one plugged in is listed next time Dart asks.
 *
 * Not yet verified on devices.
 */
class RadioSerial(private val context: Context) {
    companion object {
        private const val ACTION_PERMISSION = "org.dnet.dnet.USB_PERMISSION"
        private const val READ_BYTES = 4096

        /** USB class codes. */
        private const val CDC_DATA = 0x0A
        private const val CDC_COMM = 0x02

        /** Vendor ids of the bridges handled by their own requests. */
        private const val SILABS = 0x10C4
        private const val WCH = 0x1A86
        private const val BAUD = 115200
    }

    private val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())

    private var device: UsbDevice? = null
    private var connection: UsbDeviceConnection? = null
    private var claimed: List<UsbInterface> = emptyList()
    private var readEndpoint: UsbEndpoint? = null
    private var writeEndpoint: UsbEndpoint? = null
    private val running = AtomicBoolean(false)
    private var reader: Thread? = null

    /** Bytes that arrived, and the end of the link. */
    var onData: ((ByteArray) -> Unit)? = null
    var onClosed: ((String) -> Unit)? = null

    private val detached = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != UsbManager.ACTION_USB_DEVICE_DETACHED) return
            val gone = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE) ?: return
            if (gone.deviceName == device?.deviceName) close("the cable was pulled")
        }
    }
    private var watching = false

    /** The serial devices plugged in now, by their system names. */
    fun list(): List<Map<String, Any?>> = manager.deviceList.values
        .filter { looksSerial(it) }
        .map {
            mapOf(
                "address" to it.deviceName,
                "name" to (it.productName ?: "USB device ${it.vendorId}:${it.productId}"),
                "permission" to manager.hasPermission(it),
            )
        }

    private fun looksSerial(device: UsbDevice): Boolean {
        if (device.vendorId == SILABS || device.vendorId == WCH) return true
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == CDC_DATA || iface.interfaceClass == CDC_COMM) return true
        }
        return false
    }

    /**
     * Opens the device named [address]. Asks the user for permission
     * first if Android has not granted it; [done] is told whether the
     * device is open, with a reason if not.
     */
    fun open(address: String, done: (Boolean, String?) -> Unit) {
        close(null)
        val found = manager.deviceList.values.firstOrNull { it.deviceName == address }
        if (found == null) {
            done(false, "no USB device at $address: is it plugged in?")
            return
        }
        if (manager.hasPermission(found)) {
            done(openGranted(found), lastError)
            return
        }
        val filter = IntentFilter(ACTION_PERMISSION)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != ACTION_PERMISSION) return
                context.unregisterReceiver(this)
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (!granted) {
                    done(false, "permission to use the USB device was refused")
                    return
                }
                done(openGranted(found), lastError)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        val flags = PendingIntent.FLAG_IMMUTABLE
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_PERMISSION).setPackage(context.packageName),
            flags,
        )
        manager.requestPermission(found, pending)
    }

    private var lastError: String? = null

    private fun openGranted(found: UsbDevice): Boolean {
        lastError = null
        val conn = manager.openDevice(found)
        if (conn == null) {
            lastError = "Android would not open the device"
            return false
        }
        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        val taken = mutableListOf<UsbInterface>()
        for (i in 0 until found.interfaceCount) {
            val iface = found.getInterface(i)
            // The CDC control interface is claimed so the data one is ours
            // alone; the bulk endpoints live on the data (or only) one.
            if (!conn.claimInterface(iface, true)) continue
            taken.add(iface)
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                if (ep.direction == UsbConstants.USB_DIR_IN && inEp == null) inEp = ep
                if (ep.direction == UsbConstants.USB_DIR_OUT && outEp == null) outEp = ep
            }
        }
        if (inEp == null || outEp == null) {
            for (iface in taken) conn.releaseInterface(iface)
            conn.close()
            lastError = "the device has no serial endpoints"
            return false
        }
        if (!setSpeed(found, conn)) {
            for (iface in taken) conn.releaseInterface(iface)
            conn.close()
            lastError = "the device would not take the serial speed"
            return false
        }
        device = found
        connection = conn
        claimed = taken
        readEndpoint = inEp
        writeEndpoint = outEp
        running.set(true)
        startReading(conn, inEp)
        if (!watching) {
            val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(detached, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(detached, filter)
            }
            watching = true
        }
        return true
    }

    /** Sets 115200 8N1, by whichever way this bridge takes it. */
    private fun setSpeed(found: UsbDevice, conn: UsbDeviceConnection): Boolean {
        val out = UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_VENDOR or 0x01 // interface recipient
        return when (found.vendorId) {
            SILABS -> {
                // CP210x: IFC_ENABLE, then SET_BAUDRATE.
                conn.controlTransfer(out, 0x00, 0x0001, 0, null, 0, 1000) >= 0 &&
                    conn.controlTransfer(
                        out, 0x1E, 0, 0,
                        byteArrayOf(
                            (BAUD and 0xFF).toByte(), ((BAUD shr 8) and 0xFF).toByte(),
                            ((BAUD shr 16) and 0xFF).toByte(), ((BAUD shr 24) and 0xFF).toByte(),
                        ),
                        4, 1000,
                    ) >= 0
            }
            WCH -> {
                // CH340: init, then the divisor for 115200 (0x9C 0xC3 at
                // 12 MHz), then 8N1 line control.
                val vendorOut = UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_VENDOR
                conn.controlTransfer(vendorOut, 0xA1, 0, 0, null, 0, 1000) >= 0 &&
                    conn.controlTransfer(vendorOut, 0x9A, 0x1312, 0xCC83, null, 0, 1000) >= 0 &&
                    conn.controlTransfer(vendorOut, 0x9A, 0x2518, 0x00C3, null, 0, 1000) >= 0 &&
                    conn.controlTransfer(vendorOut, 0xA1, 0x501F, 0xD90A, null, 0, 1000) >= 0
            }
            else -> {
                // CDC-ACM: SET_LINE_CODING, then SET_CONTROL_LINE_STATE (DTR
                // and RTS up, which many boards need before they send).
                val classOut = UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_CLASS or 0x01
                val coding = byteArrayOf(
                    (BAUD and 0xFF).toByte(), ((BAUD shr 8) and 0xFF).toByte(),
                    ((BAUD shr 16) and 0xFF).toByte(), ((BAUD shr 24) and 0xFF).toByte(),
                    0, 0, 8,
                )
                // A board whose control interface refused is still used:
                // its own USB stack usually needs no line coding.
                conn.controlTransfer(classOut, 0x20, 0, 0, coding, coding.size, 1000)
                conn.controlTransfer(classOut, 0x22, 0x03, 0, null, 0, 1000)
                true
            }
        }
    }

    private fun startReading(conn: UsbDeviceConnection, endpoint: UsbEndpoint) {
        val thread = Thread {
            val buffer = ByteArray(READ_BYTES)
            while (running.get()) {
                val read = try {
                    conn.bulkTransfer(endpoint, buffer, buffer.size, 500)
                } catch (_: Exception) {
                    -1
                }
                if (read > 0) {
                    val copy = buffer.copyOf(read)
                    main.post { if (running.get()) onData?.invoke(copy) }
                } else if (read < 0 && device != null && !deviceStillThere()) {
                    main.post { close("the device went away") }
                    return@Thread
                }
            }
        }
        thread.isDaemon = true
        thread.name = "dnet-radio-serial"
        reader = thread
        thread.start()
    }

    private fun deviceStillThere(): Boolean =
        manager.deviceList.values.any { it.deviceName == device?.deviceName }

    /** Writes bytes, whole. False if the link is gone. */
    fun write(bytes: ByteArray): Boolean {
        val conn = connection ?: return false
        val endpoint = writeEndpoint ?: return false
        var at = 0
        while (at < bytes.size) {
            val chunk = minOf(endpoint.maxPacketSize, bytes.size - at)
            val sent = conn.bulkTransfer(endpoint, bytes.copyOfRange(at, at + chunk), chunk, 2000)
            if (sent < 0) {
                close("the device stopped taking data")
                return false
            }
            at += sent
        }
        return true
    }

    /** Closes the device. [why] is told to Dart when the device, not
     * Dart, ended things. */
    fun close(why: String?) {
        if (!running.getAndSet(false) && connection == null) return
        val conn = connection
        connection = null
        for (iface in claimed) {
            try {
                conn?.releaseInterface(iface)
            } catch (_: Exception) {
            }
        }
        claimed = emptyList()
        try {
            conn?.close()
        } catch (_: Exception) {
        }
        device = null
        readEndpoint = null
        writeEndpoint = null
        reader = null
        if (why != null) onClosed?.invoke(why)
    }

    fun dispose() {
        close(null)
        if (watching) {
            try {
                context.unregisterReceiver(detached)
            } catch (_: Exception) {
            }
            watching = false
        }
    }
}
