package org.dnet.dnet

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * A Meshtastic radio over Bluetooth LE. Meshtastic exposes one service
 * with three characteristics: the app writes whole `ToRadio` messages to
 * one, reads whole `FromRadio` messages from another until it reads an
 * empty one, and is told by a notification on the third that there is
 * something new to read.
 *
 * The app only moves bytes through this; what they mean is Dart's
 * business. Everything of DNet's that crosses this link is sealed and
 * signed by the core before it gets here, so the device's own pairing is
 * not what keeps it private.
 *
 * Not yet verified on devices.
 */
class RadioBle(private val context: Context) {
    companion object {
        /** Meshtastic's service and characteristics. */
        val SERVICE: UUID = UUID.fromString("6ba1b218-15a8-461f-9fa8-5dcae273eafd")
        val TO_RADIO: UUID = UUID.fromString("f75c76d2-129e-4dad-a1dd-7866124401e7")
        val FROM_RADIO: UUID = UUID.fromString("2c55e69e-4993-11ed-b878-0242ac120002")
        val FROM_NUM: UUID = UUID.fromString("ed9da18c-a800-4f66-a670-aa7547e34453")
        private val CLIENT_CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        /** Meshtastic messages are at most 512 bytes; the MTU asked for
         * leaves room for the attribute header. */
        private const val MTU = 517
        private const val SCAN_MS = 8000L
    }

    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var gatt: BluetoothGatt? = null
    private var toRadio: BluetoothGattCharacteristic? = null
    private var fromRadio: BluetoothGattCharacteristic? = null
    private var ready = false
    private var opening: ((Boolean, String?) -> Unit)? = null

    /** Writes wait their turn: one GATT operation at a time. */
    private val writes = ConcurrentLinkedQueue<ByteArray>()
    private var busy = false
    private var reading = false
    private var readAgain = false

    var onData: ((ByteArray) -> Unit)? = null
    var onClosed: ((String) -> Unit)? = null

    /** Whether this phone can do this at all. */
    fun available(): Boolean = adapter != null

    /**
     * Looks for Meshtastic devices for a few seconds and gives [done] what
     * it found: address and name each.
     */
    fun scan(done: (List<Map<String, Any?>>) -> Unit) {
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null || adapter?.isEnabled != true) {
            done(emptyList())
            return
        }
        val found = LinkedHashMap<String, Map<String, Any?>>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                found[device.address] = mapOf(
                    "address" to device.address,
                    "name" to (result.scanRecord?.deviceName ?: safeName(device) ?: device.address),
                    "rssi" to result.rssi,
                )
            }
        }
        try {
            scanner.startScan(
                listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
                callback,
            )
        } catch (_: SecurityException) {
            done(emptyList())
            return
        }
        main.postDelayed({
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
            }
            done(found.values.toList())
        }, SCAN_MS)
    }

    private fun safeName(device: BluetoothDevice): String? = try {
        device.name
    } catch (_: SecurityException) {
        null
    }

    /** Connects to [address], finds the service and turns notifications on. */
    fun open(address: String, done: (Boolean, String?) -> Unit) {
        close(null)
        val adapter = adapter
        if (adapter == null || !adapter.isEnabled) {
            done(false, "Bluetooth is off")
            return
        }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (_: IllegalArgumentException) {
            done(false, "that is not a Bluetooth address")
            return
        }
        opening = done
        try {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        } catch (_: SecurityException) {
            opening = null
            done(false, "the app may not use Bluetooth")
        }
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    if (!g.requestMtu(MTU)) g.discoverServices()
                } else {
                    val wasReady = ready
                    failOpen("could not connect (status $status)")
                    close(if (wasReady) "the radio went out of range" else null)
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            main.post { g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                val service = g.getService(SERVICE)
                val to = service?.getCharacteristic(TO_RADIO)
                val from = service?.getCharacteristic(FROM_RADIO)
                val num = service?.getCharacteristic(FROM_NUM)
                if (service == null || to == null || from == null || num == null) {
                    failOpen("this device is not a Meshtastic radio")
                    close(null)
                    return@post
                }
                toRadio = to
                fromRadio = from
                g.setCharacteristicNotification(num, true)
                val descriptor = num.getDescriptor(CLIENT_CONFIG)
                if (descriptor != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        g.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    } else {
                        @Suppress("DEPRECATION")
                        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        @Suppress("DEPRECATION")
                        g.writeDescriptor(descriptor)
                    }
                } else {
                    becomeReady()
                }
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post { becomeReady() }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (c.uuid == FROM_NUM) main.post { drain() }
        }

        @Deprecated("Deprecated in Android 13")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (c.uuid == FROM_NUM) main.post { drain() }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            main.post { readDone(value, status) }
        }

        @Deprecated("Deprecated in Android 13")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            @Suppress("DEPRECATION")
            val value = c.value ?: ByteArray(0)
            main.post { readDone(value, status) }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post {
                busy = false
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    close("the radio refused a write")
                    return@post
                }
                next()
            }
        }
    }

    private fun becomeReady() {
        if (ready) return
        ready = true
        val done = opening
        opening = null
        done?.invoke(true, null)
        // Whatever the radio already has for us.
        drain()
    }

    private fun failOpen(why: String) {
        val done = opening
        opening = null
        done?.invoke(false, why)
    }

    /** Reads fromRadio until it comes back empty. */
    private fun drain() {
        if (!ready) return
        if (reading || busy) {
            readAgain = true
            return
        }
        val g = gatt ?: return
        val from = fromRadio ?: return
        reading = true
        if (!g.readCharacteristic(from)) {
            reading = false
            readAgain = true
        }
    }

    private fun readDone(value: ByteArray, status: Int) {
        reading = false
        if (status != BluetoothGatt.GATT_SUCCESS) {
            next()
            return
        }
        if (value.isNotEmpty()) {
            onData?.invoke(value)
            drain()
            return
        }
        readAgain = false
        next()
    }

    /** Queues one whole ToRadio message. */
    fun write(bytes: ByteArray): Boolean {
        if (!ready) return false
        writes.add(bytes)
        next()
        return true
    }

    private fun next() {
        if (busy || reading) return
        val g = gatt ?: return
        val to = toRadio ?: return
        val bytes = writes.poll()
        if (bytes == null) {
            if (readAgain) drain()
            return
        }
        busy = true
        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(to, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            to.value = bytes
            to.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            g.writeCharacteristic(to)
        }
        if (!ok) {
            busy = false
            close("the radio would not take a write")
        }
    }

    fun close(why: String?) {
        val g = gatt ?: return
        gatt = null
        val wasReady = ready
        ready = false
        toRadio = null
        fromRadio = null
        writes.clear()
        busy = false
        reading = false
        try {
            g.disconnect()
            g.close()
        } catch (_: Exception) {
        }
        if (why != null && wasReady) onClosed?.invoke(why)
    }

    fun dispose() = close(null)
}
