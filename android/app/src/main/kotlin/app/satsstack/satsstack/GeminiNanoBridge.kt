package app.satsstack.satsstack

import android.os.Handler
import android.os.Looper
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Bridges Gemini Nano, through ML Kit's GenAI Prompt API, to Dart.
 *
 * The Android counterpart to `FoundationModelsBridge.swift`, and deliberately
 * shaped the same way: one method channel answering "can you run right now, and
 * if not why", and one event channel streaming an answer. The Dart side treats
 * both platforms identically apart from the extra download step below.
 *
 * Three things differ from Apple's, and each is why this is not a copy:
 *
 * 1. **The weights are not present by default.** Apple ships its model with the
 *    OS; Nano's arrive through AICore on request. So there is a third channel
 *    for the download, and `DOWNLOADABLE` is a distinct state from
 *    `UNAVAILABLE` — one is a tap away, the other is never happening on this
 *    hardware, and collapsing them would tell a user with a supported phone
 *    that their phone is unsupported.
 * 2. **Everything is a coroutine.** `checkStatus` is a suspend function and both
 *    generation and download return `Flow`, so each entry point owns a scope and
 *    cancels it when Dart stops listening.
 * 3. **Sinks must be touched from the main thread.** The flows collect on
 *    `Dispatchers.IO`, so every `success`/`error`/`endOfStream` call is posted
 *    back to the main looper. Calling a sink off-thread is the kind of bug that
 *    works in testing and crashes in the field.
 */
object GeminiNanoBridge {
    private const val METHOD_CHANNEL = "app.satsstack/gemini_nano"
    private const val STREAM_CHANNEL = "app.satsstack/gemini_nano_stream"
    private const val DOWNLOAD_CHANNEL = "app.satsstack/gemini_nano_download"

    private val main = Handler(Looper.getMainLooper())

    /**
     * One client for the process.
     *
     * Created lazily and kept: construction is not free, and the availability
     * check, the download and every generation all go through the same object.
     */
    private val model: GenerativeModel by lazy { Generation.getClient() }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> availability(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, STREAM_CHANNEL).setStreamHandler(GenerationStreamHandler())
        EventChannel(messenger, DOWNLOAD_CHANNEL).setStreamHandler(DownloadStreamHandler())
    }

    /**
     * `{reason, detail}` — the same contract the Swift bridge uses, so the Dart
     * side maps both with one shape.
     *
     * `detail` is phrased as something the user can act on. "Unavailable" is
     * final and should not read like a setting they failed to find; a pending
     * download is not a failure at all and must not be worded as one.
     */
    private fun availability(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val (reason, detail) = try {
                when (model.checkStatus()) {
                    FeatureStatus.AVAILABLE ->
                        "available" to "Gemini Nano is ready on this device."
                    FeatureStatus.DOWNLOADABLE ->
                        "downloadable" to
                            "Gemini Nano is supported here but not downloaded yet. " +
                            "It is a one-time download handled by Android."
                    FeatureStatus.DOWNLOADING ->
                        "downloading" to
                            "Android is downloading Gemini Nano. This finishes on " +
                            "its own — try again shortly."
                    FeatureStatus.UNAVAILABLE ->
                        "unavailable" to
                            "This device cannot run Gemini Nano. It needs a recent " +
                            "flagship phone with AICore."
                    else -> "unknown" to
                        "Gemini Nano reported a state this version of Sats Stack " +
                        "does not recognise."
                }
            } catch (e: Throwable) {
                // Thrown on devices with no AICore at all, and on those with an
                // unlocked bootloader, where the API refuses outright. Neither
                // is an error worth surfacing as a crash — the backend simply is
                // not on offer.
                "unavailable" to
                    "Gemini Nano is not available on this device: ${e.message}"
            }
            main.post { result.success(mapOf("reason" to reason, "detail" to detail)) }
        }
    }

    /** Streams one generation at a time. */
    private class GenerationStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            val sink = events ?: return
            @Suppress("UNCHECKED_CAST")
            val args = arguments as? Map<String, Any?>
            val prompt = args?.get("prompt") as? String
            if (prompt.isNullOrEmpty()) {
                main.post {
                    sink.error("bad_arguments", "prompt is required", null)
                    sink.endOfStream()
                }
                return
            }

            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            job = scope.launch {
                try {
                    model.generateContentStream(prompt).collect { chunk ->
                        if (!isActive) return@collect
                        // ML Kit emits deltas rather than the whole answer so
                        // far — the opposite of Apple's framework — so this is
                        // forwarded as-is with no diffing.
                        val text = chunk.candidates.firstOrNull()?.text.orEmpty()
                        if (text.isNotEmpty()) main.post { sink.success(text) }
                    }
                    main.post { sink.endOfStream() }
                } catch (e: Throwable) {
                    main.post {
                        sink.error(
                            "generation_failed",
                            e.message ?: "Gemini Nano failed to answer.",
                            null,
                        )
                        sink.endOfStream()
                    }
                }
            }
        }

        /**
         * Dart cancelling its subscription — the user leaving the chat screen
         * mid-answer — must stop the work, not leave it running.
         */
        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
        }
    }

    /**
     * Streams the AICore download as a percentage, or -1 when it cannot be
     * expressed as one.
     *
     * `DownloadProgress` reports bytes downloaded with no total, so there is
     * genuinely no percentage to compute mid-flight. Emitting -1 lets the UI
     * show an indeterminate spinner; emitting 0 instead would render as a bar
     * that sits at zero for the whole download and looks broken.
     */
    private class DownloadStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            val sink = events ?: return
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            job = scope.launch {
                try {
                    model.download().collect { status ->
                        if (!isActive) return@collect
                        when (status) {
                            is DownloadStatus.DownloadStarted -> main.post { sink.success(0) }
                            is DownloadStatus.DownloadProgress -> main.post { sink.success(-1) }
                            is DownloadStatus.DownloadCompleted -> main.post { sink.success(100) }
                            is DownloadStatus.DownloadFailed -> main.post {
                                sink.error(
                                    "download_failed",
                                    status.e.message ?: "The Gemini Nano download failed.",
                                    null,
                                )
                            }
                            else -> Unit
                        }
                    }
                    main.post { sink.endOfStream() }
                } catch (e: Throwable) {
                    main.post {
                        sink.error(
                            "download_failed",
                            e.message ?: "The Gemini Nano download failed.",
                            null,
                        )
                        sink.endOfStream()
                    }
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
        }
    }
}
