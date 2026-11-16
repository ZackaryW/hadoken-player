package com.donfreddy.troona

import android.os.SystemClock
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.hadoken.player/media_access").setMethodCallHandler { call, result ->
            if (call.method == "canRead") {
                val uri = call.argument<String>("uri")
                val readable = try {
                    uri != null && contentResolver.openAssetFileDescriptor(Uri.parse(uri), "r")?.use { true } == true
                } catch (_: Exception) { false }
                result.success(readable)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.hadoken.player/elapsed_clock").setMethodCallHandler { call, result ->
            if (call.method == "elapsedRealtime") {
                result.success(SystemClock.elapsedRealtime())
            } else {
                result.notImplemented()
            }
        }
    }
}
