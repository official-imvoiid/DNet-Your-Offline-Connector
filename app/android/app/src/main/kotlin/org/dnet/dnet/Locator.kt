package org.dnet.dnet

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Where the phone is, for a user who chose to send it. Uses Android's own
 * location service, so it works with no Google services and, from GPS,
 * with no internet. Nothing is looked up until the user asks, and nothing
 * is kept.
 *
 * Not yet verified on devices.
 */
class Locator(private val context: Context) {
    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val main = Handler(Looper.getMainLooper())

    companion object {
        /** A fix this recent is where the phone is now. */
        const val RECENT_MS = 2 * 60 * 1000L

        /** How long to wait for a fix before saying there is none. */
        const val WAIT_MS = 30 * 1000L

        fun permissions() = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
    }

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** The user let the app know where the phone is, exactly or roughly. */
    fun allowed() = granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
        granted(Manifest.permission.ACCESS_COARSE_LOCATION)

    /** Location is switched on for the phone as a whole. */
    fun enabled() = manager.isLocationEnabled

    /** The ways this phone has of telling, best first. */
    private fun providers(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= 31 &&
            manager.hasProvider(LocationManager.FUSED_PROVIDER) &&
            manager.isProviderEnabled(LocationManager.FUSED_PROVIDER)
        ) {
            add(LocationManager.FUSED_PROVIDER)
        }
        // GPS needs the exact permission, not the rough one.
        if (granted(Manifest.permission.ACCESS_FINE_LOCATION) &&
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        ) {
            add(LocationManager.GPS_PROVIDER)
        }
        if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            add(LocationManager.NETWORK_PROVIDER)
        }
    }

    /**
     * Works out where the phone is and calls [done] once, on the main
     * thread: with the place, or with null if nothing could tell in time.
     * Only call this once [allowed] is true.
     */
    @Suppress("MissingPermission")
    fun find(done: (Location?) -> Unit) {
        val providers = providers()
        val now = SystemClock.elapsedRealtimeNanos()
        val recent = providers
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { now - it.elapsedRealtimeNanos < RECENT_MS * 1_000_000 }
            .minByOrNull { if (it.hasAccuracy()) it.accuracy else Float.MAX_VALUE }
        if (recent != null || providers.isEmpty()) {
            done(recent)
            return
        }
        var answered = false
        var empty = 0
        val cancel = CancellationSignal()
        val listeners = mutableListOf<LocationListener>()
        fun answer(location: Location?) {
            if (answered) return
            answered = true
            cancel.cancel()
            listeners.forEach { manager.removeUpdates(it) }
            main.removeCallbacksAndMessages(this)
            done(location)
        }
        // Whichever way answers first. Indoors, GPS may never answer.
        fun heard(location: Location?) {
            if (location != null) {
                answer(location)
            } else if (++empty == providers.size) {
                answer(null)
            }
        }
        for (provider in providers) {
            runCatching {
                if (Build.VERSION.SDK_INT >= 30) {
                    manager.getCurrentLocation(provider, cancel, context.mainExecutor) { heard(it) }
                } else {
                    // Every method written out: before Android 11 they had
                    // no defaults, and one left out would crash when called.
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) = heard(location)

                        @Deprecated("Deprecated in Java")
                        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                        override fun onProviderEnabled(provider: String) {}

                        override fun onProviderDisabled(provider: String) = heard(null)
                    }
                    listeners += listener
                    @Suppress("DEPRECATION")
                    manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                }
            }.onFailure { heard(null) }
        }
        main.postAtTime({ answer(null) }, this, SystemClock.uptimeMillis() + WAIT_MS)
    }
}
