package app.satsstack.satsstack

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        GeminiNanoBridge.register(messenger)
    }

    // The Recents screen shows a thumbnail of the app as it was left: the
    // dashboard's balances, the stack, transactions, the AI chat (audit P-1).
    // Hidden there, while screenshots the user takes inside the app still work.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    // Before Android 13 there is no switch for the thumbnail alone, so the
    // window is marked secure only while the app is in the background — the
    // thumbnail comes out blank, and screenshots work again on return.
    override fun onPause() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
