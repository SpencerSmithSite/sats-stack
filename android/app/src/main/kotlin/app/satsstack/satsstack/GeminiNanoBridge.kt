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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
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
                // unlocked bootloader, where the API refuses outright — but
                // also when AICore is busy or still starting. Reported as an
                // error rather than "unavailable", which the Dart side keeps for
                // the session: a transient failure used to hide Nano until the
                // app was restarted.
                "error" to
                    "Could not reach Gemini Nano just now: ${e.message}"
            }
            main.post { result.success(mapOf("reason" to reason, "detail" to detail)) }
        }
    }

    /**
     * Streams one generation at a time.
     *
     * **Cancellation.** A cancelled generation used to keep talking: the
     * coroutine unwound by throwing `CancellationException`, which the
     * catch-all reported as `generation_failed`. And a new request started at
     * once, while the model could still be busy with the one just cancelled.
     * Now each generation holds a token, every emission is dropped unless that
     * token is still current (checked on the main thread, where `onCancel`
     * also runs, so the two cannot race), cancellation is rethrown rather than
     * reported, and a new generation joins the cancelled one before starting.
     * The same shape as `FoundationModelsBridge.swift`, where the bug was
     * reproduced: an answer asked for straight after a cancelled one arrived
     * empty.
     */
    private class GenerationStreamHandler : EventChannel.StreamHandler {
        /** One scope for the handler's life, so a generation can be joined. */
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private var job: Job? = null

        /** Which generation may emit. Main thread only. */
        private var current: Any? = null

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

            val token = Any()
            current = token
            val previous = job
            previous?.cancel()

            fun emit(block: (EventChannel.EventSink) -> Unit) {
                main.post { if (current === token) block(sink) }
            }

            job = scope.launch {
                // The model answers one request at a time; starting before the
                // cancelled one has unwound races it.
                previous?.join()
                try {
                    model.generateContentStream(prompt).collect { chunk ->
                        // ML Kit emits deltas rather than the whole answer so
                        // far — the opposite of Apple's framework — so this is
                        // forwarded as-is with no diffing.
                        val text = chunk.candidates.firstOrNull()?.text.orEmpty()
                        if (text.isNotEmpty()) emit { it.success(text) }
                    }
                    emit { it.endOfStream() }
                } catch (e: CancellationException) {
                    // A cancel is the caller's choice, not a failure.
                    throw e
                } catch (e: Throwable) {
                    emit {
                        it.error(
                            "generation_failed",
                            e.message ?: "Gemini Nano failed to answer.",
                            null,
                        )
                        it.endOfStream()
                    }
                }
            }
        }

        /**
         * Dart cancelling its subscription — the user leaving the chat screen
         * mid-answer — must stop the work, not leave it running. The job is
         * kept, cancelled, so the next generation can join it.
         */
        override fun onCancel(arguments: Any?) {
            current = null
            job?.cancel()
        }
    }

    /**
     * Streams the AICore download as a percentage, or -1 when it cannot be
     * expressed as one.
     *
     * `DownloadStarted` carries the size of the download and each
     * `DownloadProgress` the bytes so far, so this is a real percentage. It
     * used to emit -1 for every progress event, on the belief that there was
     * no total — the bar was indeterminate for the whole download. -1 remains
     * for a start that reports no size.
     */
    private class DownloadStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            val sink = events ?: return
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            job = scope.launch {
                var total = 0L
                try {
                    model.download().collect { status ->
                        if (!isActive) return@collect
                        when (status) {
                            is DownloadStatus.DownloadStarted -> {
                                total = status.bytesToDownload
                                main.post { sink.success(0) }
                            }
                            is DownloadStatus.DownloadProgress -> {
                                val percent =
                                    if (total > 0) {
                                        (status.totalBytesDownloaded * 100 / total)
                                            .coerceIn(0L, 99L)
                                            .toInt()
                                    } else {
                                        -1
                                    }
                                main.post { sink.success(percent) }
                            }
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
                } catch (e: CancellationException) {
                    // Dart stopped listening; the sink is gone. Not a failure.
                    throw e
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
