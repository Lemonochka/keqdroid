package com.keqdroid.keqdroid

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

// видео для шапок подписок: гифку разбирал процессор (~50% ядра Pixel 6a на потоке io),
// видео разбирает аппаратный декодер. Кадры гифки приходят из Flutter, кодирует MediaCodec
class CardMedia(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val encoders = HashMap<Int, FrameEncoder>()
    private var nextId = 1

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val path = call.argument<String>("path")!!
                val width = call.argument<Int>("width")!!
                val height = call.argument<Int>("height")!!
                val fps = call.argument<Int>("fps")!!
                val id = nextId++
                background(result) {
                    val encoder = FrameEncoder(path, width, height, fps)
                    main.post { encoders[id] = encoder }
                    id
                }
            }
            "frame" -> {
                val encoder = encoders[call.argument<Int>("id")!!]
                    ?: return result.error("encoder", "unknown encoder", null)
                val rgba = call.argument<ByteArray>("rgba")!!
                val stride = call.argument<Int>("stride")!!
                val pts = call.argument<Number>("pts")!!.toLong()
                background(result) { encoder.frame(rgba, stride, pts); null }
            }
            "finish" -> {
                val encoder = encoders.remove(call.argument<Int>("id")!!)
                    ?: return result.error("encoder", "unknown encoder", null)
                background(result) { encoder.finish(); null }
            }
            "cancel" -> {
                val encoder = encoders.remove(call.argument<Int>("id")!!)
                background(result) { encoder?.release(); null }
            }
            "probe" -> {
                val path = call.argument<String>("path")!!
                background(result) { probe(path) }
            }
            "poster" -> {
                val path = call.argument<String>("path")!!
                val out = call.argument<String>("out")!!
                background(result) { poster(path, out) }
            }
            "transcode" -> transcode(call, result)
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("media", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun probe(path: String): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun int(key: Int) = retriever.extractMetadata(key)?.toIntOrNull() ?: 0
            val rotation = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val w = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val h = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val turned = rotation == 90 || rotation == 270
            return mapOf(
                "width" to if (turned) h else w,
                "height" to if (turned) w else h,
                "durationMs" to (retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                )?.toLongOrNull() ?: 0L),
                "hasVideo" to (retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO,
                ) == "yes"),
            )
        } finally {
            retriever.release()
        }
    }

    private fun poster(path: String, out: String): Boolean {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return false
            FileOutputStream(out).use { frame.compress(Bitmap.CompressFormat.PNG, 100, it) }
            frame.recycle()
            return true
        } finally {
            retriever.release()
        }
    }

    // Transformer живёт на потоке с Looper: запускаем и ждём ответа на главном
    private fun transcode(call: MethodCall, result: MethodChannel.Result) {
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        val maxMs = call.argument<Number>("maxMs")!!.toLong()
        val width = call.argument<Int>("width")!!
        val height = call.argument<Int>("height")!!
        val item = MediaItem.Builder()
            .setUri(android.net.Uri.fromFile(File(input)))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder().setEndPositionMs(maxMs).build(),
            )
            .build()
        val edited = EditedMediaItem.Builder(item)
            .setRemoveAudio(true)
            .setEffects(
                Effects(
                    emptyList(),
                    listOf(
                        Presentation.createForWidthAndHeight(
                            width,
                            height,
                            Presentation.LAYOUT_SCALE_TO_FIT,
                        ),
                    ),
                ),
            )
            .build()
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    result.success(true)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    File(output).delete()
                    result.error("media", exportException.message, null)
                }
            })
            .build()
        transformer.start(edited, output)
    }

    companion object {
        const val CHANNEL = "keqdis_media"
    }
}

private class FrameEncoder(path: String, private val width: Int, private val height: Int, fps: Int) {
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxing = false
    private var lastPts = 0L

    init {
        val bitrate = (width.toLong() * height * fps * 3 / 10).coerceIn(1_500_000L, 6_000_000L)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate.toInt())
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // ключевой кадр раз в секунду: повтор с начала не ждёт далёкого опорного кадра
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // цвета считаются по BT.601 ниже, без пометки плеер мог бы взять 709 и сдвинуть оттенки
            setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT601_NTSC)
            setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
            setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    fun frame(rgba: ByteArray, stride: Int, pts: Long) {
        val index = dequeueInput()
        val image = codec.getInputImage(index) ?: error("no input image")
        val y = image.planes[0]
        val u = image.planes[1]
        val v = image.planes[2]
        val yBuf = y.buffer
        for (row in 0 until height) {
            var src = row * stride
            val dst = row * y.rowStride
            for (col in 0 until width) {
                val r = rgba[src].toInt() and 0xff
                val g = rgba[src + 1].toInt() and 0xff
                val b = rgba[src + 2].toInt() and 0xff
                yBuf.put(dst + col * y.pixelStride, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                src += 4
            }
        }
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                var r = 0
                var g = 0
                var b = 0
                for (dy in 0..1) {
                    var src = (row * 2 + dy) * stride + col * 8
                    for (dx in 0..1) {
                        r += rgba[src].toInt() and 0xff
                        g += rgba[src + 1].toInt() and 0xff
                        b += rgba[src + 2].toInt() and 0xff
                        src += 4
                    }
                }
                r /= 4
                g /= 4
                b /= 4
                u.buffer.put(
                    row * u.rowStride + col * u.pixelStride,
                    (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte(),
                )
                v.buffer.put(
                    row * v.rowStride + col * v.pixelStride,
                    (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte(),
                )
            }
        }
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, pts, 0)
        lastPts = pts
        drain(false)
    }

    fun finish() {
        try {
            val index = dequeueInput()
            codec.queueInputBuffer(index, 0, 0, lastPts + 1, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            if (muxing) muxer.stop()
        } finally {
            release()
        }
    }

    fun release() {
        runCatching { codec.stop() }
        runCatching { codec.release() }
        runCatching { muxer.release() }
    }

    private fun dequeueInput(): Int {
        repeat(500) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(false)
        }
        error("encoder input stalled")
    }

    private fun drain(endOfStream: Boolean) {
        var idle = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++idle > 500) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxing = true
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)!!
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (!config && info.size > 0 && muxing) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }
}
