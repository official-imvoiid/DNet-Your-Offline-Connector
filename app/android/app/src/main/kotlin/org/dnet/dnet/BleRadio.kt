package org.dnet.dnet

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import java.util.UUID

/**
 * Finds other DNet devices over Bluetooth Low Energy and moves frames
 * between them.
 *
 * Every device does both halves at once: it advertises a service so others
 * can find it and connect, and it scans for that same service and connects
 * to whoever it finds. Whichever side connects, the result is the same: a
 * numbered link that frames can be sent on in both directions.
 *
 * This class knows nothing about who is at the other end and cannot read
 * what it carries. Proving identity, cutting messages into frames and all
 * encryption happen in the Rust core. The advertisement holds one fixed
 * number that means "DNet is running here" and nothing about the user. The
 * device's name is left out on purpose.
 *
 * It is kept in [Background] for the whole run of the app, so it goes on
 * after the screen is closed when the user lets the app run in the
 * background, with [LinkService]'s notice saying so.
 *
 * Not yet verified on devices.
 */
@SuppressLint("MissingPermission") // Checked in start(), before anything else is called.
class BleRadio(
    private val context: Context,
    /** Receives each event as a map. Always called on the main thread. */
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        // Must match radio_windows/src/lib.rs.
        val SERVICE: UUID = UUID.fromString("d0e7a1c0-5b1e-4f6a-9c3d-7e2b8a4f1d01")

        /** Frames to this device are written here. */
        val RX: UUID = UUID.fromString("d0e7a1c0-5b1e-4f6a-9c3d-7e2b8a4f1d02")

        /** Frames from this device are notified here. */
        val TX: UUID = UUID.fromString("d0e7a1c0-5b1e-4f6a-9c3d-7e2b8a4f1d03")

        /** The standard switch a device writes to ask for notifications. */
        val CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        /** Bluetooth carries at most this much in one write or notification. */
        private const val MAX_FRAME = 512
        private const val SMALLEST_MTU = 23

        /** Connections this device will start itself, leaving room for others to connect in. */
        private const val MAX_OUTGOING = 4
        private const val RETRY_AFTER_MS = 5_000L

        /** How long a device gets to finish connecting before it is given up. */
        private const val CONNECT_WAIT_MS = 30_000L
        private const val LEAVE_ALONE_MS = 5 * 60_000L

        /** How long a frame may wait for the radio before the link is given up. */
        private const val MAX_SEND_TRIES = 40
        private const val SEND_RETRY_MS = 50L

        /** How often a link's signal strength is passed on. */
        private const val SIGNAL_EVERY_MS = 2_000L

        fun permissions(): Array<String> =
            if (Build.VERSION.SDK_INT >= 31) {
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                )
            } else {
                // Android 10 and 11 file Bluetooth scanning under Location.
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
    }

    /** One link, whichever side started it. */
    private abstract inner class Link(val id: Int, val address: String) {
        val waiting = ArrayDeque<ByteArray>()
        var sending = false
        var tries = 0
        var retrying = false
        var up = false

        /** When this link's signal strength was last passed on. */
        var signalledAt = 0L

        /** Hands one frame to the radio. False means "not now, try again". */
        abstract fun write(frame: ByteArray): Boolean
        abstract fun close()
    }

    /** A link this device started, by connecting to one it found. */
    private inner class Outgoing(id: Int, address: String) : Link(id, address) {
        var gatt: BluetoothGatt? = null
        var rx: BluetoothGattCharacteristic? = null
        var mtu = SMALLEST_MTU

        @Suppress("DEPRECATION")
        override fun write(frame: ByteArray): Boolean {
            val gatt = gatt ?: return false
            val rx = rx ?: return false
            return if (Build.VERSION.SDK_INT >= 33) {
                gatt.writeCharacteristic(rx, frame, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                rx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                rx.value = frame
                gatt.writeCharacteristic(rx)
            }
        }

        override fun close() {
            gatt?.disconnect()
            gatt?.close()
            gatt = null
        }
    }

    /** A link another device started, by connecting to this one. */
    private inner class Incoming(id: Int, val device: BluetoothDevice) : Link(id, device.address) {
        @Suppress("DEPRECATION")
        override fun write(frame: ByteArray): Boolean {
            val server = server ?: return false
            val tx = tx ?: return false
            return if (Build.VERSION.SDK_INT >= 33) {
                server.notifyCharacteristicChanged(device, tx, false, frame) == BluetoothStatusCodes.SUCCESS
            } else {
                tx.value = frame
                server.notifyCharacteristicChanged(device, tx, false)
            }
        }

        override fun close() {
            server?.cancelConnection(device)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? get() = manager?.adapter

    /** True from start() to stop(), even while Bluetooth itself is off. */
    private var wanted = false
    private var running = false
    private var watchingAdapter = false

    private var server: BluetoothGattServer? = null
    private var tx: BluetoothGattCharacteristic? = null

    private var nextLink = 1
    private val links = HashMap<Int, Link>()
    private val outgoing = HashMap<String, Outgoing>()
    private val incoming = HashMap<String, Incoming>()

    /** The frame size each connected device has agreed to, by address. */
    private val mtus = HashMap<String, Int>()

    /** Addresses not to connect to again until the given time. */
    private val notBefore = HashMap<String, Long>()

    // Starting and stopping

    fun start() {
        wanted = true
        if (!watchingAdapter) {
            context.registerReceiver(adapterWatcher, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
            watchingAdapter = true
        }
        bringUp()
    }

    fun stop() {
        wanted = false
        if (watchingAdapter) {
            context.unregisterReceiver(adapterWatcher)
            watchingAdapter = false
        }
        tearDown()
    }

    /** What stops the radio from running, or "on" if nothing does. */
    fun obstacle(): String {
        val adapter = adapter
        if (adapter == null || !context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return "unsupported"
        }
        if (permissions().any { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
            return "noPermission"
        }
        if (!adapter.isEnabled) return "bluetoothOff"
        if (Build.VERSION.SDK_INT < 31) {
            val location = context.getSystemService(LocationManager::class.java)
            if (location?.isLocationEnabled != true) return "locationOff"
        }
        return "on"
    }

    private fun bringUp() {
        if (running) return
        val state = obstacle()
        if (state != "on") {
            emit(mapOf("t" to "state", "state" to state))
            return
        }
        val adapter = adapter ?: return
        val opened = manager?.openGattServer(context, serverCallback)
        if (opened == null) {
            emit(mapOf("t" to "state", "state" to "unsupported"))
            return
        }
        server = opened
        running = true

        val receive = BluetoothGattCharacteristic(
            RX,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        val send = BluetoothGattCharacteristic(
            TX,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            0,
        )
        send.addDescriptor(
            BluetoothGattDescriptor(
                CONFIG,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        tx = send
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(receive)
        service.addCharacteristic(send)
        // Advertising starts in onServiceAdded, once there is something to
        // connect to.
        opened.addService(service)

        adapter.bluetoothLeScanner?.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build(),
            scanCallback,
        )
        emit(mapOf("t" to "state", "state" to "on"))
    }

    private fun tearDown() {
        if (!running) return
        running = false
        val adapter = adapter
        // These throw if Bluetooth has just been switched off. There is
        // nothing left to stop in that case.
        runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        for (link in links.values.toList()) {
            runCatching { link.close() }
            if (link.up) emit(mapOf("t" to "down", "link" to link.id))
        }
        links.clear()
        outgoing.clear()
        incoming.clear()
        mtus.clear()
        runCatching { server?.close() }
        server = null
        tx = null
        main.removeCallbacksAndMessages(null)
    }

    private val adapterWatcher = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    tearDown()
                    if (wanted) emit(mapOf("t" to "state", "state" to "bluetoothOff"))
                }
                BluetoothAdapter.STATE_ON -> if (wanted) bringUp()
            }
        }
    }

    // Sending

    fun send(linkId: Int, frames: List<ByteArray>) {
        val link = links[linkId] ?: return
        link.waiting.addAll(frames)
        pump(link)
    }

    /** Ends one link and leaves that device alone for a while. */
    fun drop(linkId: Int) {
        val link = links[linkId] ?: return
        notBefore[link.address] = SystemClock.elapsedRealtime() + LEAVE_ALONE_MS
        forget(link, close = true)
    }

    /**
     * Sends the next waiting frame, if the radio is free. Bluetooth takes
     * one frame at a time and says when it is ready for the next.
     */
    private fun pump(link: Link) {
        if (link.sending || !link.up || links[link.id] !== link) return
        val frame = link.waiting.firstOrNull() ?: return
        if (link.write(frame)) {
            link.waiting.removeFirst()
            link.sending = true
            link.tries = 0
        } else if (++link.tries > MAX_SEND_TRIES) {
            forget(link, close = true)
        } else if (!link.retrying) {
            link.retrying = true
            main.postDelayed({
                link.retrying = false
                pump(link)
            }, SEND_RETRY_MS)
        }
    }

    private fun sent(link: Link, ok: Boolean) {
        link.sending = false
        if (ok) {
            // The app holds back what is less urgent until there is room,
            // so it is told each time a frame has gone.
            if (link.up) emit(mapOf("t" to "sent", "link" to link.id, "n" to 1))
            pump(link)
        } else {
            forget(link, close = true)
        }
    }

    private fun forget(link: Link, close: Boolean) {
        if (links.remove(link.id) == null) return
        when (link) {
            is Outgoing -> if (outgoing[link.address] === link) outgoing.remove(link.address)
            is Incoming -> if (incoming[link.address] === link) incoming.remove(link.address)
        }
        if (close) runCatching { link.close() } else if (link is Outgoing) runCatching { link.gatt?.close() }
        if (link.up) emit(mapOf("t" to "down", "link" to link.id))
        link.up = false
    }

    private fun raise(link: Link, mtu: Int) {
        if (link.up || links[link.id] !== link) return
        link.up = true
        // Three bytes of every packet are Bluetooth's own.
        emit(mapOf("t" to "up", "link" to link.id, "max" to (mtu - 3).coerceIn(SMALLEST_MTU - 3, MAX_FRAME)))
    }

    // Being found: the half that others connect to

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            // Some phones cannot advertise. This one can still find others
            // and connect to them, so the radio stays on.
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            main.post {
                if (!running || status != BluetoothGatt.GATT_SUCCESS) return@post
                adapter?.bluetoothLeAdvertiser?.startAdvertising(
                    AdvertiseSettings.Builder()
                        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                        .setConnectable(true)
                        .setTimeout(0)
                        .build(),
                    AdvertiseData.Builder()
                        // The phone's name often has its owner's name in it.
                        .setIncludeDeviceName(false)
                        .setIncludeTxPowerLevel(false)
                        .addServiceUuid(ParcelUuid(SERVICE))
                        .build(),
                    advertiseCallback,
                )
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    mtus.remove(device.address)
                    incoming[device.address]?.let { forget(it, close = false) }
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            main.post { mtus[device.address] = mtu }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            main.post {
                // A frame always fits in one write. Anything sent in pieces
                // is not from DNet.
                val whole = characteristic.uuid == RX && !preparedWrite && offset == 0 && value != null
                if (responseNeeded) {
                    server?.sendResponse(
                        device,
                        requestId,
                        if (whole) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                        0,
                        null,
                    )
                }
                val link = incoming[device.address]
                if (whole && link != null && link.up) {
                    emit(mapOf("t" to "frame", "link" to link.id, "data" to value))
                }
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            main.post {
                val on = incoming.containsKey(device.address)
                server?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    0,
                    if (on) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE,
                )
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            main.post {
                val ours = descriptor.uuid == CONFIG && descriptor.characteristic.uuid == TX && !preparedWrite
                if (responseNeeded) {
                    server?.sendResponse(
                        device,
                        requestId,
                        if (ours) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                        0,
                        null,
                    )
                }
                if (!ours || !running) return@post
                // Asking for notifications is how the other device says it
                // is ready. That is the moment the link exists.
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    if (incoming.containsKey(device.address)) return@post
                    val link = Incoming(nextLink++, device)
                    links[link.id] = link
                    incoming[device.address] = link
                    raise(link, mtus[device.address] ?: SMALLEST_MTU)
                } else {
                    incoming[device.address]?.let { forget(it, close = false) }
                }
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                incoming[device.address]?.let { sent(it, status == BluetoothGatt.GATT_SUCCESS) }
            }
        }
    }

    // Finding others: the half that connects out

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            main.post {
                heard(result.device.address, result.rssi)
                found(result.device)
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            main.post {
                results.forEach {
                    heard(it.device.address, it.rssi)
                    found(it.device)
                }
            }
        }
    }

    /**
     * Passes on how strongly a device this one is linked to is heard, in
     * dBm: a rough guide to how near it is, which says nothing about which
     * way. Scanning goes on while linked, so each advert it hears gives a
     * reading; one every couple of seconds is plenty.
     *
     * A guess not yet tried on a phone: that the address an advert comes
     * from is the one the link was made with. A phone that changes its
     * address while linked gives no readings, and the app then draws it
     * at a steady spot as before.
     */
    private fun heard(address: String, rssi: Int) {
        val link = outgoing[address] ?: incoming[address] ?: return
        if (!link.up) return
        val now = SystemClock.elapsedRealtime()
        if (now - link.signalledAt < SIGNAL_EVERY_MS) return
        link.signalledAt = now
        emit(mapOf("t" to "signal", "link" to link.id, "rssi" to rssi))
    }

    private fun found(device: BluetoothDevice) {
        val address = device.address
        if (!running || outgoing.containsKey(address) || incoming.containsKey(address)) return
        if (outgoing.size >= MAX_OUTGOING) return
        if (SystemClock.elapsedRealtime() < (notBefore[address] ?: 0L)) return

        val link = Outgoing(nextLink++, address)
        links[link.id] = link
        outgoing[address] = link
        link.gatt = device.connectGatt(context, false, clientCallback(link), BluetoothDevice.TRANSPORT_LE)
        if (link.gatt == null) {
            lost(link)
            return
        }
        // Some phones never answer and never say they failed.
        main.postDelayed({
            if (!link.up && links[link.id] === link) {
                link.close()
                lost(link)
            }
        }, CONNECT_WAIT_MS)
    }

    /** The connection failed or ended. Try that device again, but not at once. */
    private fun lost(link: Outgoing) {
        val until = SystemClock.elapsedRealtime() + RETRY_AFTER_MS
        if ((notBefore[link.address] ?: 0L) < until) notBefore[link.address] = until
        forget(link, close = false)
    }

    private fun clientCallback(link: Outgoing) = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                    // Ask for the largest frames first. Everything after
                    // waits for the answer.
                    if (!gatt.requestMtu(MAX_FRAME + 5)) gatt.discoverServices()
                } else {
                    lost(link)
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) link.mtu = mtu
                if (!link.up && link.rx == null) gatt.discoverServices()
            }
        }

        @Suppress("DEPRECATION")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            main.post {
                val service = gatt.getService(SERVICE)
                val rx = service?.getCharacteristic(RX)
                val tx = service?.getCharacteristic(TX)
                val config = tx?.getDescriptor(CONFIG)
                if (status != BluetoothGatt.GATT_SUCCESS || rx == null || tx == null || config == null) {
                    // It advertised DNet's number but is not DNet.
                    notBefore[link.address] = SystemClock.elapsedRealtime() + LEAVE_ALONE_MS
                    forget(link, close = true)
                    return@post
                }
                link.rx = rx
                gatt.setCharacteristicNotification(tx, true)
                val asked = if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeDescriptor(config, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ==
                        BluetoothStatusCodes.SUCCESS
                } else {
                    config.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(config)
                }
                if (!asked) lost(link)
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) raise(link, link.mtu) else lost(link)
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            main.post { sent(link, status == BluetoothGatt.GATT_SUCCESS) }
        }

        // Android 13 and later.
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            arrived(characteristic.uuid, value)
        }

        // Android 12 and earlier.
        @Deprecated("Replaced by the version that is handed the value.")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            // Copied now: the next notification overwrites it.
            arrived(characteristic.uuid, characteristic.value?.copyOf() ?: return)
        }

        private fun arrived(from: UUID, value: ByteArray) {
            if (from != TX) return
            main.post {
                // The other side may speak the moment it sees us ready,
                // which can be just before we hear that we are.
                raise(link, link.mtu)
                if (link.up) emit(mapOf("t" to "frame", "link" to link.id, "data" to value))
            }
        }
    }
}
