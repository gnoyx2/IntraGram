package com.yonghun0310.intragram

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// MethodChannel 다섯 개를 붙임
//  - intragram/screenshot: Android 14(API 34)+에서만 registerScreenCaptureCallback으로 스크린샷을 감지함
//    (DETECT_SCREEN_CAPTURE 권한). 그 밑은 아무 일도 안 하고, iOS와 달리 막지는 못하고 알리기만 함
//  - intragram/foreground: ConnectionService를 켜고 꺼서 백그라운드에서도 피어 링크를 살려 둠 (설정에서 옵트인)
//  - intragram/privacy: 민감 표시 클립보드 복사, 클립보드 비우기(clearIfOwn은 우리 복사본일 때만), 앱 정보 화면 열기
//  - intragram/file_source: 고른 문서·사진의 바이트를 메모리에서 넘김
//  - intragram/voice: 받은 음성을 메모리에서 재생 (VoicePlayerChannel)
// FLAG_SECURE는 늘 켬 (최근 앱 썸네일·스크린샷·화면 녹화에 대화가 안 남게, 끄는 설정 없음). 최근 앱 스냅샷 끄기(API 33+)도 따로 켬
class MainActivity : FlutterActivity() {
    private companion object {
        const val SENSITIVE_CLIP_LABEL = "IntraGram"
        const val LOCAL_NETWORK_PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
        const val LOCAL_NETWORK_REQUEST = 37017
    }

    private var screenshotChannel: MethodChannel? = null
    private var foregroundChannel: MethodChannel? = null
    private var memoryFileSource: MemoryFileSource? = null
    private var voicePlayer: VoicePlayerChannel? = null
    private val localNetworkResults = mutableListOf<MethodChannel.Result>()

    @get:RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private val screenCaptureCallback by lazy {
        Activity.ScreenCaptureCallback {
            screenshotChannel?.invokeMethod("onScreenshot", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter가 MediaQuery로 시스템 바·키보드 안전 영역을 처리함 (Android 15+ 강제 모드와 동일)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "intragram/privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLocalNetworkPermission" -> result.success(localNetworkGranted())
                "requestLocalNetworkPermission" -> {
                    if (localNetworkGranted()) {
                        result.success(true)
                    } else {
                        localNetworkResults.add(result)
                        if (localNetworkResults.size == 1) {
                            requestPermissions(arrayOf(LOCAL_NETWORK_PERMISSION), LOCAL_NETWORK_REQUEST)
                        }
                    }
                }
                "copySensitive" -> {
                    copySensitive(call.arguments as? String ?: "")
                    result.success(null)
                }
                "clearClipboard" -> {
                    clearClipboard()
                    result.success(null)
                }
                "clearIfOwn" -> result.success(clearIfOwn())
                // 설명(MIME)만 봐서 Android 12+ 클립보드 접근 알림이 안 뜸 (파일 붙여넣기는 데스크톱만)
                "clipboardKinds" -> {
                    val description = getSystemService(ClipboardManager::class.java)
                        .primaryClipDescription
                    result.success(
                        mapOf(
                            "image" to (description?.hasMimeType("image/*") == true),
                            "files" to false,
                        ),
                    )
                }
                // 거부한 권한(마이크·카메라·알림)을 다시 켤 수 있게 앱 정보 화면을 엶
                "openAppSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", packageName, null),
                    )
                    result.success(
                        try {
                            startActivity(intent)
                            true
                        } catch (e: ActivityNotFoundException) {
                            false
                        },
                    )
                }
                else -> result.notImplemented()
            }
        }
        screenshotChannel = MethodChannel(messenger, "intragram/screenshot")
        memoryFileSource = MemoryFileSource(this, messenger)
        voicePlayer = VoicePlayerChannel(messenger)
        val channel = MethodChannel(messenger, "intragram/foreground")
        foregroundChannel = channel
        // 서비스가 스스로 멈추면(FGS 누적 시간 제한, Android 15+) Dart에 알림: 백그라운드 연결 유지가 실제론 안 도는데
        // 켜진 것처럼 보이면 안 됨
        ConnectionService.onTimedOut = { runOnUiThread { channel.invokeMethod("onTimeout", null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        ConnectionService.start(this)
                        result.success(null)
                    } catch (e: IllegalStateException) {
                        // 백그라운드에서 포그라운드 서비스 시작 제한(Android 12+, ForegroundServiceStartNotAllowedException 포함) 등:
                        // 앱을 죽이지 않고 Dart에 실패로 알림
                        result.error("foreground_start_failed", e.message, null)
                    } catch (e: SecurityException) {
                        result.error("foreground_start_failed", e.message, null)
                    }
                }
                "stop" -> {
                    ConnectionService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (memoryFileSource?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    // 문자열·정수만 써서 compileSdk 36에서도 빌드됨. target 36 이하는 OS가 LAN을 이미 허용함
    private fun localNetworkGranted(): Boolean =
        if (Build.VERSION.SDK_INT >= 37 && applicationInfo.targetSdkVersion >= 37) {
            checkSelfPermission(LOCAL_NETWORK_PERMISSION) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCAL_NETWORK_REQUEST) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val results = localNetworkResults.toList()
        localNetworkResults.clear()
        results.forEach { it.success(granted) }
    }

    override fun onDestroy() {
        localNetworkResults.forEach { it.success(false) }
        localNetworkResults.clear()
        super.onDestroy()
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerScreenCaptureCallback(mainExecutor, screenCaptureCallback)
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            unregisterScreenCaptureCallback(screenCaptureCallback)
        }
        super.onStop()
    }

    // API 33+는 클립보드 미리보기 토스트/키보드 제안에 내용이 안 뜸
    // 라벨은 clearIfOwn이 내용을 안 읽고 우리 복사본인지 알아보는 표식
    private fun copySensitive(text: String) {
        val clip = ClipData.newPlainText(SENSITIVE_CLIP_LABEL, text)
        clip.description.extras = PersistableBundle().apply {
            val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ClipDescription.EXTRA_IS_SENSITIVE
            } else {
                "android.content.extra.IS_SENSITIVE"
            }
            putBoolean(key, true)
        }
        getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }

    // 설명(라벨)만 봐서 다른 앱 내용 접근 토스트가 안 뜸. 백그라운드(포커스 없음)면
    // Android 10+가 null을 줘서 확인 불가로 null을 돌려주고 Dart가 복귀 때 다시 부름
    private fun clearIfOwn(): Boolean? {
        val clipboard = getSystemService(ClipboardManager::class.java)
        val description = clipboard.primaryClipDescription ?: return null
        if (description.label?.toString() != SENSITIVE_CLIP_LABEL) return false
        clearClipboard()
        return true
    }

    private fun clearClipboard() {
        val clipboard = getSystemService(ClipboardManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    }
}
