package com.yonghun0310.intragram

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

// intragram/file_source 채널: 모바일 문서·사진 선택을 캐시 사본 없이 RAM으로 흘려 넘김.
// ACTION_OPEN_DOCUMENT + ContentResolver.openInputStream이라 앱 캐시 폴더를 아예 안 거침.
// URI·권한은 프로세스 RAM에만 두고 persistable permission은 안 씀 (이번 세션 첨부용이라 프로세스가 사는 동안이면 충분)
// 계약: pick(imagesOnly) -> [{id,name,size}], open(sourceId) -> readerId, read(readerId, maxBytes) -> bytes|null(EOF),
// close(readerId), release(sourceId), releaseAll(). read는 Dart가 다음 조각을 달라고 할 때만 불려서 버퍼가 끝없이 안 쌓임
class MemoryFileSource(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME).also {
        it.setMethodCallHandler(this)
    }
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    private data class Source(val uri: Uri, val name: String, val size: Long)

    private val sources = mutableMapOf<String, Source>()
    private val readers = mutableMapOf<String, InputStream>()
    private var pendingPick: MethodChannel.Result? = null

    // releaseAll()마다 오름. 그 순간 도는 pick·open은(콜백이 아직 안 옴) 시작할 때 잡은 값과 나중에 비교해서
    // 다르면 방금 얻은 소스·스트림을 등록 안 하고 바로 버림
    private var generation = 0
    private var pendingPickGeneration = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(call.argument<Boolean>("imagesOnly") == true, result)
            "open" -> open(call.argument<String>("sourceId"), result)
            "read" -> read(
                call.argument<String>("readerId"),
                call.argument<Int>("maxBytes") ?: DEFAULT_CHUNK_BYTES,
                result,
            )
            "close" -> close(call.argument<String>("readerId"), result)
            "release" -> release(call.argument<String>("sourceId"), result)
            "releaseAll" -> releaseAll(result)
            else -> result.notImplemented()
        }
    }

    private fun pick(imagesOnly: Boolean, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "another pick is already in progress", null)
            return
        }
        pendingPick = result
        pendingPickGeneration = generation
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (imagesOnly) "image/*" else "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            // 클라우드 전용(기기에 안 받은) 문서는 목록에서 미리 거름: 첨부가 네트워크 다운로드를 일으키면 안 됨
            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Exception) {
            pendingPick = null
            result.error("launch_failed", e.message, null)
        }
    }

    // MainActivity.onActivityResult가 호출함. 이 채널 요청이면 true를 반환함
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val pickGeneration = pendingPickGeneration
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Any>())
            return true
        }
        if (pickGeneration != generation) {
            // 이 pick 도중에 releaseAll이 돎: 새 source를 등록 안 하고 빈 결과로 끝냄
            result.success(emptyList<Any>())
            return true
        }

        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let { uris.add(it) }
        }

        val metadata = uris.mapNotNull { describe(it) }.map { (id, source) ->
            mapOf("id" to id, "name" to source.name, "size" to source.size)
        }
        result.success(metadata)
        return true
    }

    // 스트림은 아직 안 엶 (이름·크기만 커서로 조회)
    private fun describe(uri: Uri): Pair<String, Source>? {
        var name = uri.lastPathSegment ?: "file"
        var size = -1L
        activity.contentResolver.query(uri, null, null, null, null)?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIdx >= 0) cursor.getString(nameIdx)?.let { name = it }
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
            }
        }
        // 크기를 못 구하면(클라우드 전용 등) 조용히 건너뜀: 네트워크 다운로드를 일으키는 대신 이 파일만 목록에서 빠짐
        if (size < 0) return null
        val id = UUID.randomUUID().toString()
        val source = Source(uri, name, size)
        sources[id] = source
        return id to source
    }

    private fun open(sourceId: String?, result: MethodChannel.Result) {
        val source = sources[sourceId]
        if (source == null) {
            result.error("unknown_source", "source $sourceId not found", null)
            return
        }
        val openGeneration = generation
        io.execute {
            val stream = try {
                activity.contentResolver.openInputStream(source.uri)
            } catch (e: Exception) {
                null
            }
            main.post {
                if (openGeneration != generation) {
                    // open 도중에 releaseAll이 돎: 방금 연 스트림은 등록 안 하고 바로 닫음
                    try {
                        stream?.close()
                    } catch (e: Exception) {
                        // 닫기 실패는 무시함
                    }
                    result.error("released", "source was released during open", null)
                } else if (stream == null) {
                    result.error("open_failed", "could not open $sourceId", null)
                } else {
                    val readerId = UUID.randomUUID().toString()
                    readers[readerId] = stream
                    result.success(readerId)
                }
            }
        }
    }

    private fun read(readerId: String?, maxBytes: Int, result: MethodChannel.Result) {
        val stream = readers[readerId]
        if (stream == null) {
            result.error("unknown_reader", "reader $readerId not found", null)
            return
        }
        io.execute {
            val buffer = ByteArray(maxBytes)
            val n = try {
                stream.read(buffer)
            } catch (e: Exception) {
                -2
            }
            main.post {
                when {
                    n == -2 -> result.error("read_failed", "read error on $readerId", null)
                    n <= 0 -> result.success(null) // EOF
                    n == maxBytes -> result.success(buffer)
                    else -> result.success(buffer.copyOf(n))
                }
            }
        }
    }

    private fun close(readerId: String?, result: MethodChannel.Result) {
        readers.remove(readerId)?.let { stream ->
            io.execute {
                try {
                    stream.close()
                } catch (e: Exception) {
                    // 닫기 실패는 무시함
                }
            }
        }
        result.success(null)
    }

    private fun release(sourceId: String?, result: MethodChannel.Result) {
        sources.remove(sourceId)
        result.success(null)
    }

    private fun releaseAll(result: MethodChannel.Result) {
        generation++
        sources.clear()
        val open = readers.values.toList()
        readers.clear()
        io.execute {
            open.forEach {
                try {
                    it.close()
                } catch (e: Exception) {
                    // 닫기 실패는 무시함
                }
            }
        }
        result.success(null)
    }

    companion object {
        private const val CHANNEL_NAME = "intragram/file_source"
        private const val REQUEST_CODE = 61319
        private const val DEFAULT_CHUNK_BYTES = 256 * 1024
    }
}
