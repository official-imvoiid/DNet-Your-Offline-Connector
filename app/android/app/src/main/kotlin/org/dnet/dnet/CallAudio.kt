package org.dnet.dnet

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * The microphone and the speaker during a call.
 *
 * Sound moves as it is spoken, not as a file: the microphone hands over a
 * fiftieth of a second at a time, 16-bit samples, 16,000 a second, one
 * channel, and the speaker plays whatever the app gives it as soon as it
 * can. Squeezing the sound, sealing it and sending it are the core's work
 * and the app's; this only listens and plays.
 *
 * The microphone is opened the way calls open it, so the phone takes the
 * echo of the speaker out of it and quietens the room where it can.
 *
 * Not yet verified on devices.
 */
class CallAudio(context: Context, private val heard: (ByteArray) -> Unit) {
    private companion object {
        const val RATE = 16000
        const val BLOCK_BYTES = RATE / 50 * 2

        /** Blocks waiting to be played, at most. Older ones go. */
        const val KEEP_PLAYING = 6
    }

    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var running = false
    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var echo: AcousticEchoCanceler? = null
    private var noise: NoiseSuppressor? = null
    private var threads = listOf<Thread>()
    private val toPlay = ArrayBlockingQueue<ByteArray>(KEEP_PLAYING)
    private var modeBefore = AudioManager.MODE_NORMAL

    /**
     * Starts the speaker, and the microphone if [mayRecord]: the user has
     * allowed it. Says which of the two work.
     */
    fun start(mayRecord: Boolean): Pair<Boolean, Boolean> {
        stop()
        running = true
        modeBefore = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        loudspeaker(false)
        val speaker = startSpeaker()
        val mic = mayRecord && startMicrophone()
        return Pair(mic, speaker)
    }

    private fun startMicrophone(): Boolean = try {
        val least = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val made = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(least, BLOCK_BYTES * 4),
        )
        if (made.state != AudioRecord.STATE_INITIALIZED) {
            made.release()
            false
        } else {
            if (AcousticEchoCanceler.isAvailable()) {
                echo = AcousticEchoCanceler.create(made.audioSessionId)?.apply { enabled = true }
            }
            if (NoiseSuppressor.isAvailable()) {
                noise = NoiseSuppressor.create(made.audioSessionId)?.apply { enabled = true }
            }
            made.startRecording()
            record = made
            val listening = Thread {
                val block = ByteArray(BLOCK_BYTES)
                while (running) {
                    var got = 0
                    while (running && got < block.size) {
                        val read = made.read(block, got, block.size - got)
                        if (read <= 0) break
                        got += read
                    }
                    if (got < block.size) {
                        if (!running) break
                        Thread.sleep(5)
                        continue
                    }
                    val copy = block.copyOf()
                    main.post { if (running) heard(copy) }
                }
            }
            listening.priority = Thread.MAX_PRIORITY
            listening.start()
            threads = threads + listening
            true
        }
    } catch (e: Exception) {
        // No permission, or the microphone is in use elsewhere.
        false
    }

    private fun startSpeaker(): Boolean = try {
        val least = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val made = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(least, BLOCK_BYTES * 4))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        made.play()
        track = made
        val speaking = Thread {
            val silence = ByteArray(BLOCK_BYTES)
            while (running) {
                // Nothing to play is silence, not a stop: the speaker is
                // kept fed so it does not start and stop with each pause.
                val block = toPlay.poll(20, TimeUnit.MILLISECONDS) ?: silence
                if (made.write(block, 0, block.size) < 0) break
            }
        }
        speaking.priority = Thread.MAX_PRIORITY
        speaking.start()
        threads = threads + speaking
        true
    } catch (e: Exception) {
        false
    }

    /** Queues one block for the speaker. */
    fun play(block: ByteArray) {
        if (!running) return
        while (!toPlay.offer(block)) toPlay.poll()
    }

    /** Sends the sound to the loudspeaker, or back to the earpiece. */
    fun loudspeaker(on: Boolean) {
        runCatching {
            if (Build.VERSION.SDK_INT >= 31) {
                val wanted = if (on) AudioDeviceInfo.TYPE_BUILTIN_SPEAKER else AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                val device = audio.availableCommunicationDevices.firstOrNull { it.type == wanted }
                if (device != null) audio.setCommunicationDevice(device) else audio.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = on
            }
        }
    }

    /** Stops both. Nothing is kept. */
    fun stop() {
        if (!running && record == null && track == null) return
        running = false
        for (thread in threads) runCatching { thread.join(200) }
        threads = listOf()
        runCatching { record?.stop() }
        record?.release()
        record = null
        echo?.release()
        echo = null
        noise?.release()
        noise = null
        runCatching { track?.stop() }
        track?.release()
        track = null
        toPlay.clear()
        runCatching {
            if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice()
            audio.mode = modeBefore
        }
    }
}
