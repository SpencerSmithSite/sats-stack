package app.satsstack.satsstack

import android.app.ActivityManager
import android.content.Context
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Physical memory and free disk, so the downloadable-model catalogue can be
 * sized to the device rather than to marketing figures.
 *
 * Dart cannot read either portably, and two methods here are cheaper than a
 * dependency. Only Android and iOS need this: on macOS, Windows and Linux the
 * Dart side shells out to `sysctl`, `df` and PowerShell directly.
 */
object DeviceBridge {
    private const val CHANNEL = "app.satsstack/device"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "totalMemoryMb" -> {
                    val manager =
                        context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo()
                    manager.getMemoryInfo(info)
                    // `totalMem` is what the OS reports as installed, not what
                    // is free right now: the question is what the device can
                    // ever hold, not what it happens to have spare while a
                    // settings screen is open.
                    //
                    // Note this comes back materially under the advertised
                    // figure — a "4 GB" phone reports about 3,967 MB, because
                    // the kernel reserves the rest. The catalogue's thresholds
                    // are set against this number, not the marketing one.
                    result.success((info.totalMem / (1024L * 1024L)).toInt())
                }
                "freeDiskMb" -> {
                    // Measured on the directory the model is actually written
                    // to, not on the root volume: adopted storage and separate
                    // data partitions make those different numbers on plenty of
                    // devices.
                    val stat = StatFs(context.filesDir.absolutePath)
                    val free = stat.availableBlocksLong * stat.blockSizeLong
                    result.success((free / (1024L * 1024L)).toInt())
                }
                else -> result.notImplemented()
            }
        }
    }
}
