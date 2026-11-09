package org.dnet.dnet

import android.app.Activity
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicReference
import kotlin.random.Random

/**
 * Tapping two phones together to swap DNet links over NFC.
 *
 * Android dropped phone-to-phone NFC ("Beam") in Android 10, so each phone
 * takes turns: for a short random while it reads, and for another it is
 * read, by [NfcLinkService] answering as a card. Two phones held back to
 * back soon land on opposite turns, and each reads the other.
 *
 * Only the link the user is offering moves, the same text as Copy link.
 * Nothing is offered while the tap screen is closed.
 */
class NfcTap(
    private val activity: Activity,
    private val onRead: (String) -> Unit,
    private val onGiven: () -> Unit,
) {
    companion object {
        /** What [NfcLinkService] hands a reader. Null: nothing is offered. */
        val offered = AtomicReference<ByteArray?>(null)

        /** Told when a reader has had all of [offered]. */
        @Volatile
        var given: (() -> Unit)? = null

        /** F0, then "DNETLK". Must match res/xml/nfc_link_aid.xml. */
        val AID = byteArrayOf(
            0xF0.toByte(), 0x44, 0x4E, 0x45, 0x54, 0x4C, 0x4B,
        )

        /** The most read in one exchange, well under what any phone takes. */
        const val CHUNK = 240

        /** The longest link accepted. A DNet link is a few hundred bytes. */
        const val MOST = 4096

        /** Whether this phone can both read and be read. */
        fun available(activity: Activity): Boolean =
            NfcAdapter.getDefaultAdapter(activity) != null &&
                activity.packageManager.hasSystemFeature(
                    PackageManager.FEATURE_NFC_HOST_CARD_EMULATION,
                )
    }

    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private val main = Handler(Looper.getMainLooper())
    private var running = false
    private var paused = false
    private var reading = false

    /** Set while a read is under way, so the turns do not cut it off. */
    @Volatile
    private var busy = false

    fun enabled(): Boolean = adapter?.isEnabled == true

    fun start(link: String) {
        offered.set(link.toByteArray(Charsets.UTF_8))
        given = { main.post { if (running) onGiven() } }
        running = true
        main.removeCallbacksAndMessages(null)
        turn()
    }

    fun stop() {
        running = false
        main.removeCallbacksAndMessages(null)
        offered.set(null)
        given = null
        readerOff()
    }

    /** The app went off screen. Reading needs it on screen. */
    fun pause() {
        paused = true
        main.removeCallbacksAndMessages(null)
        readerOff()
    }

    fun resume() {
        paused = false
        if (running) turn()
    }

    private fun turn() {
        if (!running || paused) return
        if (!busy) {
            if (reading) readerOff() else readerOn()
        }
        main.postDelayed(::turn, Random.nextLong(250, 750))
    }

    private fun readerOn() {
        val adapter = adapter ?: return
        try {
            adapter.enableReaderMode(
                activity,
                ::onTag,
                NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK or
                    NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
                null,
            )
            reading = true
        } catch (_: Exception) {
            reading = false
        }
    }

    private fun readerOff() {
        if (!reading) return
        try {
            adapter?.disableReaderMode(activity)
        } catch (_: Exception) {
        }
        reading = false
    }

    /** On the NFC thread Android calls back on. */
    private fun onTag(tag: Tag) {
        val iso = IsoDep.get(tag) ?: return
        busy = true
        try {
            iso.connect()
            iso.timeout = 2000
            val select = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, AID.size.toByte()) +
                AID + byteArrayOf(0x00)
            val head = iso.transceive(select)
            if (!ok(head) || head.size != 4) return
            val size = ((head[0].toInt() and 0xFF) shl 8) or (head[1].toInt() and 0xFF)
            if (size <= 0 || size > MOST) return
            val out = ByteArrayOutputStream(size)
            while (out.size() < size) {
                val at = out.size()
                val ask = minOf(CHUNK, size - at)
                val read = byteArrayOf(
                    0x00, 0xB0.toByte(), (at shr 8).toByte(), (at and 0xFF).toByte(), ask.toByte(),
                )
                val part = iso.transceive(read)
                if (!ok(part) || part.size - 2 != ask) return
                out.write(part, 0, ask)
            }
            val link = String(out.toByteArray(), Charsets.UTF_8)
            main.post { if (running) onRead(link) }
        } catch (_: Exception) {
            // Moved apart too soon. The next touch tries again.
        } finally {
            busy = false
            try {
                iso.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun ok(answer: ByteArray) = answer.size >= 2 &&
        answer[answer.size - 2] == 0x90.toByte() &&
        answer[answer.size - 1] == 0x00.toByte()
}
