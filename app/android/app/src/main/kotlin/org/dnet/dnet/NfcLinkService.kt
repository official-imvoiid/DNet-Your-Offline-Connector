package org.dnet.dnet

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * The other half of [NfcTap]: answers a phone reading this one with the
 * link the user is offering, in pieces. Says "not here" whenever the tap
 * screen is closed, so a reader passing by gets nothing.
 */
class NfcLinkService : HostApduService() {
    private companion object {
        val OK = byteArrayOf(0x90.toByte(), 0x00)
        val NOT_HERE = byteArrayOf(0x6A, 0x82.toByte())
        val WRONG = byteArrayOf(0x6D, 0x00)
        val OUT_OF_RANGE = byteArrayOf(0x6B, 0x00)
    }

    override fun processCommandApdu(apdu: ByteArray, extras: Bundle?): ByteArray {
        val link = NfcTap.offered.get() ?: return NOT_HERE
        if (apdu.size < 4) return WRONG
        return when (apdu[1]) {
            // SELECT, for the one id this service has: how long the link is.
            0xA4.toByte() -> byteArrayOf((link.size shr 8).toByte(), link.size.toByte()) + OK
            // READ BINARY: the piece from the offset asked for.
            0xB0.toByte() -> {
                if (apdu.size < 5) return WRONG
                val at = ((apdu[2].toInt() and 0xFF) shl 8) or (apdu[3].toInt() and 0xFF)
                val ask = (apdu[4].toInt() and 0xFF).let { if (it == 0) 256 else it }
                if (at >= link.size) return OUT_OF_RANGE
                val end = minOf(link.size, at + ask)
                if (end == link.size) NfcTap.given?.invoke()
                link.copyOfRange(at, end) + OK
            }
            else -> WRONG
        }
    }

    override fun onDeactivated(reason: Int) {}
}
