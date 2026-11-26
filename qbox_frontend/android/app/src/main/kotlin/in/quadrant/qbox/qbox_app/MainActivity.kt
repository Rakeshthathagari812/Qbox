package `in`.quadrant.qbox.qbox_app

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qbox/settings").setMethodCallHandler { call, result ->
            when (call.method) {
                // QBOX's own page in the phone's settings (battery, notifications).
                "appSettings" -> result.success(
                    open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                )
                // Where voices (Telugu, Hindi...) are added.
                "voiceSettings" -> result.success(
                    open(Intent("com.android.settings.TTS_SETTINGS")) ||
                        open(Intent("android.speech.tts.engine.INSTALL_TTS_DATA"))
                )
                // How loud the phone speaks, 0 to 100.
                "mediaVolume" -> {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val most = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (most == 0) 0 else audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / most)
                }
                // Which build this is, for the update check.
                "appBuild" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toInt() else info.versionCode
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun open(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }
}
