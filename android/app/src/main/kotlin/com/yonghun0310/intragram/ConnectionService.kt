package com.yonghun0310.intragram

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

// 앱이 백그라운드에 있는 동안 서버와 피어 링크를 살려 두는 포그라운드 서비스 (낮은 우선순위 지속 알림 하나).
// 소켓은 Dart 엔진이 쥐고 있고 이 서비스는 OS가 그 프로세스를 안 죽이게 붙잡기만 함.
// MainActivity가 intragram/foreground 채널로 켜고 끔 (설정에서 옵트인, 기본 꺼짐)
class ConnectionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.connection_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                )
            channel.description = getString(R.string.connection_channel_description)
            manager.createNotificationChannel(channel)
        }

        // 알림을 누르면 떠 있는 MainActivity를 앞으로 가져오고 없으면 새로 띄움
        val openApp =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_IMMUTABLE,
            )

        val notification: Notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(getString(R.string.connection_title))
                .setContentText(getString(R.string.connection_text))
                // 상태 표시줄은 알파만 써서 흰색으로 칠함. 컬러 런처 아이콘은 흰 네모·덩어리로 보임
                .setSmallIcon(R.drawable.ic_stat_intragram)
                .setContentIntent(openApp)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // 프로세스가 죽으면 소켓을 쥔 Dart 엔진도 없어서 다시 띄워 봐야 연결 안 된 알림만 남음: 재시작 안 함
        return START_NOT_STICKY
    }

    // Android 15+(API 35)에서 시간 제한이 있는 타입(dataSync 등)에만 불림. 지금 타입(remoteMessaging)엔 제한이 없지만
    // 타입이 바뀌어도 START_STICKY 무한 재시작으로 제한을 피하지 않고, 멈춘 뒤 onTimedOut으로 Dart에 알려서
    // 백그라운드 연결 유지가 꺼진 걸 설정에 보여 줌
    // https://developer.android.com/develop/background-work/services/fgs/timeout
    override fun onTimeout(startId: Int, fgsType: Int) {
        onTimedOut?.invoke()
        stopSelf(startId)
    }

    companion object {
        private const val CHANNEL_ID = "connection"
        private const val NOTIFICATION_ID = 42

        // MainActivity가 등록함. onTimeout에서 Dart에 알리는 통로
        var onTimedOut: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, ConnectionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ConnectionService::class.java))
        }
    }
}
