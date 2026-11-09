package org.dnet.dnet

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Takes a photo to send, with the phone's own camera app.
 *
 * The camera app writes the photo straight into the app's cache, beside
 * files picked to send, through a link that lets it write that one file
 * and nothing else. The app asks for no storage permission. Answers Dart
 * with what happened: "taken" with the path, or "cancelled", "denied",
 * "none" (no camera app) or "busy".
 *
 * Not yet verified on devices.
 */
class PhotoCamera :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private companion object {
        const val TAKE_PHOTO = 4120
        const val ASK_CAMERA = 4121
    }

    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null

    /** The Dart call waiting for the photo, and the file it goes into. */
    private var waiting: Pair<MethodChannel.Result, File>? = null

    override fun onAttachedToEngine(engine: FlutterPlugin.FlutterPluginBinding) {
        // Must match the channel name in lib/screens/camera_screen.dart.
        val channel = MethodChannel(engine.binaryMessenger, "dnet/photo")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "take") take(result) else result.notImplemented()
        }
        this.channel = channel
    }

    override fun onDetachedFromEngine(engine: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
    }

    private fun take(result: MethodChannel.Result) {
        val activity = binding?.activity
        if (activity == null || waiting != null) {
            result.success(mapOf("state" to "busy"))
            return
        }
        val folder = File(activity.cacheDir, "outgoing").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date())
        val file = File(folder, "photo-$stamp.jpg")
        waiting = Pair(result, file)
        // The app lists the camera among its permissions, so Android lets
        // it ask the camera app for a photo only once the user allows it.
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            open(activity, file)
        } else {
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), ASK_CAMERA)
        }
    }

    private fun open(activity: Activity, file: File) {
        val uri = try {
            FileProvider.getUriForFile(activity, "${activity.packageName}.photos", file)
        } catch (e: IllegalArgumentException) {
            return finish("failed")
        }
        val shoot = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            .putExtra(MediaStore.EXTRA_OUTPUT, uri)
            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(shoot, TAKE_PHOTO)
        } catch (e: ActivityNotFoundException) {
            finish("none")
        }
    }

    /** Answers Dart. Anything but a photo taken leaves no file behind. */
    private fun finish(state: String) {
        val (result, file) = waiting ?: return
        waiting = null
        if (state == "taken") {
            result.success(mapOf("state" to state, "path" to file.absolutePath))
        } else {
            file.delete()
            result.success(mapOf("state" to state))
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != ASK_CAMERA) return false
        val activity = binding?.activity
        val file = waiting?.second
        val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (allowed && activity != null && file != null) open(activity, file) else finish("denied")
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != TAKE_PHOTO) return false
        val file = waiting?.second
        // Some camera apps say OK and write nothing; that is no photo.
        finish(if (resultCode == Activity.RESULT_OK && file != null && file.length() > 0) "taken" else "cancelled")
        return true
    }
}
