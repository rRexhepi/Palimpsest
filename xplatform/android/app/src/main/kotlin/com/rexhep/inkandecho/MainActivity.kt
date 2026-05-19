package com.rexhep.inkandecho

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends `AudioServiceActivity` so `audio_service` / `just_audio_background`
// retain their lifecycle wiring, and registers the
// `inkandecho/native_decoder` channel that the Dart side calls into for
// audio decoding (the replacement for ffmpeg-kit on this platform).
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NativeAudioDecoder.CHANNEL)
            .setMethodCallHandler { call, result -> NativeAudioDecoder.handle(call, result) }
    }
}
