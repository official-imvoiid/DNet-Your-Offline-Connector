package org.dnet.dnet

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/**
 * The microphone and the speaker, for voice messages.
 *
 * Records an AAC sound file (.m4a) and plays one back. That is all it
 * does. A recording is an ordinary file: sending it, and sealing it for
 * the person it is for, is the core's work.
 *
 * Not yet verified on devices.
 */
class VoiceNotes(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var recordingTo: File? = null
    private var player: MediaPlayer? = null

    /** Starts recording into the file at [path]. False if it cannot. */
    fun start(path: String): Boolean {
        cancel()
        val file = File(path)
        return try {
            file.parentFile?.mkdirs()
            @Suppress("DEPRECATION")
            val made = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
            made.setAudioSource(MediaRecorder.AudioSource.MIC)
            made.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            made.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            // Small, because a voice message goes over Bluetooth. Clear
            // enough for speech.
            made.setAudioChannels(1)
            made.setAudioSamplingRate(16000)
            made.setAudioEncodingBitRate(32000)
            made.setOutputFile(file.absolutePath)
            made.prepare()
            made.start()
            recorder = made
            recordingTo = file
            true
        } catch (e: Exception) {
            file.delete()
            false
        }
    }

    /** Stops, keeping what was recorded. False if there is nothing to keep. */
    fun stop(): Boolean {
        val made = recorder ?: return false
        val file = recordingTo
        recorder = null
        recordingTo = null
        return try {
            // Throws if it was stopped before any sound was taken in.
            made.stop()
            true
        } catch (e: RuntimeException) {
            file?.delete()
            false
        } finally {
            made.release()
        }
    }

    /** Stops and throws away what was recorded. */
    fun cancel() {
        val file = recordingTo
        stop()
        file?.delete()
    }

    /** Plays the sound file at [path] from its start. False if it cannot. */
    fun play(path: String): Boolean {
        stopPlaying()
        return try {
            val made = MediaPlayer()
            made.setDataSource(path)
            made.setOnCompletionListener {
                it.release()
                if (player === it) player = null
            }
            made.prepare()
            made.start()
            player = made
            true
        } catch (e: Exception) {
            false
        }
    }

    fun stopPlaying() {
        val made = player ?: return
        player = null
        runCatching { made.stop() }
        made.release()
    }

    fun close() {
        cancel()
        stopPlaying()
    }
}
