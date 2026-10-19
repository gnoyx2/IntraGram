package com.yonghun0310.intragram

import android.media.AudioAttributes
import android.media.MediaDataSource
import android.media.MediaPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// 받은 음성(WAV 바이트)을 메모리의 MediaDataSource로 바로 재생함 (파일·캐시·로컬 HTTP 없음)
// 바이트는 dispose 때 0으로 덮고 놓아 줌
class VoicePlayerChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "intragram/voice")
    private val players = HashMap<String, MediaPlayer>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error("args", "missing id", null)
            return
        }
        when (call.method) {
            "load" -> load(id, call.argument<ByteArray>("bytes"), result)
            "play" -> {
                val player = players[id]
                if (call.argument<Boolean>("rewind") == true) player?.seekTo(0)
                player?.start()
                result.success(null)
            }
            "pause" -> {
                players[id]?.takeIf { it.isPlaying }?.pause()
                result.success(null)
            }
            "position" -> result.success(players[id]?.currentPosition ?: 0)
            "dispose" -> {
                players.remove(id)?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun load(id: String, bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null) {
            result.error("args", "missing bytes", null)
            return
        }
        val player = MediaPlayer()
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            player.setDataSource(MemoryAudio(bytes))
            player.prepare()
            player.setOnCompletionListener { channel.invokeMethod("completed", id) }
            players[id] = player
            result.success(player.duration)
        } catch (e: Exception) {
            player.release()
            result.error("load", e.message, null)
        }
    }

    private class MemoryAudio(private val data: ByteArray) : MediaDataSource() {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
            if (position >= data.size) return -1
            val count = minOf(size.toLong(), data.size - position).toInt()
            System.arraycopy(data, position.toInt(), buffer, offset, count)
            return count
        }

        override fun getSize(): Long = data.size.toLong()

        override fun close() = data.fill(0)
    }
}
