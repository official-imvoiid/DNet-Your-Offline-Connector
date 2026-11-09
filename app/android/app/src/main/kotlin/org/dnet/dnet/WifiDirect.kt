package org.dnet.dnet

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Wi-Fi Direct: a small Wi-Fi network this phone makes for another device
 * to join, or joins when another device made it. It needs no router, no
 * hotspot and no internet, and the phone stays on whatever Wi-Fi it was
 * already using.
 *
 * The group is only a road. This class does not know who joins or what is
 * sent: the app gives the group a name and password it made up, tells them
 * to one person over a link that is already sealed, and everything that
 * then travels on the group is sealed by the core as it is over Bluetooth.
 *
 * Joining by name and password, as here, needs no "connect?" question on
 * either phone. Android has allowed it since Android 10.
 *
 * Not yet verified on devices.
 */
class WifiDirect(private val context: Context) {
    companion object {
        /** How long a group gets to form before the attempt is given up. */
        private const val WAIT_MS = 30_000L
        private const val LOOK_EVERY_MS = 500L

        /**
         * What Android wants the user to have allowed. Android 13 and later
         * have a permission for exactly this. Earlier versions file Wi-Fi
         * Direct under Location, and Android 12 will only ask for precise
         * location together with approximate. The app does not read the
         * phone's location on any version.
         */
        fun permissions(): Array<String> = when {
            Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
            Build.VERSION.SDK_INT >= 31 -> arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            )
            else -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var channel: WifiP2pManager.Channel? = null

    /** Goes up with every new attempt, so an older one stops waiting. */
    private var attempt = 0

    /** Whether the user has allowed it. Approximate location is not enough. */
    fun allowed(): Boolean =
        context.checkSelfPermission(permissions()[0]) == PackageManager.PERMISSION_GRANTED

    private fun channel(): WifiP2pManager.Channel? {
        val manager = manager ?: return null
        channel?.let { return it }
        // Android says so here if it drops the connection to its Wi-Fi
        // Direct service. The next attempt asks for a new one.
        return manager.initialize(context, Looper.getMainLooper()) { channel = null }.also { channel = it }
    }

    /**
     * [band] is "2.4" or "5" for a group this phone makes on that band, or
     * null to let Android choose. A phone joining looks on every band.
     */
    private fun group(network: String, pass: String, band: String? = null): WifiP2pConfig =
        WifiP2pConfig.Builder()
            .setNetworkName(network)
            .setPassphrase(pass)
            // Made for this once, and not kept by Android afterwards.
            .enablePersistentMode(false)
            .setGroupOperatingBand(
                when (band) {
                    "2.4" -> WifiP2pConfig.GROUP_OWNER_BAND_2GHZ
                    "5" -> WifiP2pConfig.GROUP_OWNER_BAND_5GHZ
                    else -> WifiP2pConfig.GROUP_OWNER_BAND_AUTO
                },
            )
            .build()

    /**
     * Which band is the quieter here, "2.4" or "5": the one with fewer
     * Wi-Fi networks heard in the phone's last look around, a loud one
     * counting double. Null if the phone has no 5 GHz, or will not say
     * what it heard: Android shares that only with an app allowed
     * precise location, which from Android 13 this app does not ask for.
     */
    fun quieterBand(): String? {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return null
        if (!wifi.is5GHzBandSupported) return null
        val heard: List<ScanResult> = try {
            wifi.scanResults
        } catch (e: SecurityException) {
            return null
        } ?: return null
        if (heard.isEmpty()) return null
        var low = 0
        var high = 0
        for (network in heard) {
            val weight = if (network.level > -70) 2 else 1
            when (network.frequency) {
                in 2400..2500 -> low += weight
                in 4900..5900 -> high += weight
            }
        }
        return if (high <= low) "5" else "2.4"
    }

    /** Carries on whether or not the step before it had anything to do. */
    private fun then(next: () -> Unit) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = next()
        override fun onFailure(reason: Int) = next()
    }

    /**
     * Makes a group with this name and password for another device to
     * join. Says false if it could not: Wi-Fi is off, it is not allowed,
     * or the phone cannot do it.
     */
    @SuppressLint("MissingPermission")
    fun host(network: String, pass: String, band: String?, done: (Boolean) -> Unit) {
        val manager = manager
        val channel = channel()
        if (manager == null || channel == null || !allowed()) return done(false)
        val mine = ++attempt
        // A group left over from before would be in the way of a new one.
        manager.removeGroup(
            channel,
            then {
                try {
                    manager.createGroup(
                        channel,
                        group(network, pass, band),
                        object : WifiP2pManager.ActionListener {
                            override fun onSuccess() =
                                await(mine, deadline(), { if (it.groupFormed && it.isGroupOwner) true else null }) {
                                    done(it == true)
                                }

                            override fun onFailure(reason: Int) = done(false)
                        },
                    )
                } catch (e: RuntimeException) {
                    // A name or password Android will not take, or the
                    // permission went away in between.
                    done(false)
                }
            },
        )
    }

    /**
     * Joins the group with this name and password. Says the address of
     * the device that made it, on the group's own network, or null if the
     * group could not be joined in time.
     */
    @SuppressLint("MissingPermission")
    fun join(network: String, pass: String, done: (String?) -> Unit) {
        val manager = manager
        val channel = channel()
        if (manager == null || channel == null || !allowed()) return done(null)
        val mine = ++attempt
        manager.removeGroup(
            channel,
            then {
                try {
                    manager.connect(
                        channel,
                        group(network, pass),
                        object : WifiP2pManager.ActionListener {
                            override fun onSuccess() =
                                await(
                                    mine,
                                    deadline(),
                                    { if (it.groupFormed && !it.isGroupOwner) it.groupOwnerAddress?.hostAddress else null },
                                ) { address ->
                                    if (address == null && mine == attempt) manager.cancelConnect(channel, null)
                                    done(address)
                                }

                            override fun onFailure(reason: Int) = done(null)
                        },
                    )
                } catch (e: RuntimeException) {
                    done(null)
                }
            },
        )
    }

    /** Gives up whatever group this phone made or joined. */
    fun leave(done: () -> Unit) {
        attempt++
        val manager = manager
        val channel = channel
        if (manager == null || channel == null) return done()
        manager.cancelConnect(channel, null)
        manager.removeGroup(channel, then(done))
    }

    private fun deadline() = System.currentTimeMillis() + WAIT_MS

    /**
     * Asks Android about the group every half second until [read] finds
     * what it is waiting for, the time runs out, or a newer attempt has
     * taken over. Android reports the group a moment after agreeing to
     * make or join it.
     */
    private fun <T : Any> await(mine: Int, until: Long, read: (WifiP2pInfo) -> T?, done: (T?) -> Unit) {
        val manager = manager
        val channel = channel
        if (mine != attempt || manager == null || channel == null) return done(null)
        manager.requestConnectionInfo(channel) { info ->
            val found = info?.let(read)
            when {
                mine != attempt -> done(null)
                found != null -> done(found)
                System.currentTimeMillis() >= until -> done(null)
                else -> main.postDelayed({ await(mine, until, read, done) }, LOOK_EVERY_MS)
            }
        }
    }
}
