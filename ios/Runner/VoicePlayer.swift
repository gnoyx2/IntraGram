import AVFoundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

// 받은 음성(WAV 바이트)을 메모리에서 바로 재생함. AVPlayer + 로컬 HTTP 프록시와 달리
// tmp/MediaCache 같은 캐시 파일을 만들지 않음. 바이트는 dispose 때 플레이어와 함께 놓아 줌
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private var players: [String: AVAudioPlayer] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "intragram/voice", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
      result(FlutterError(code: "args", message: "missing id", details: nil))
      return
    }
    switch call.method {
    case "load":
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "args", message: "missing bytes", details: nil))
        return
      }
      do {
        let player = try AVAudioPlayer(data: bytes.data, fileTypeHint: AVFileType.wav.rawValue)
        player.delegate = self
        player.prepareToPlay()
        players[id] = player
        result(Int(player.duration * 1000))
      } catch {
        result(FlutterError(code: "load", message: error.localizedDescription, details: nil))
      }
    case "play":
      guard let player = players[id] else {
        result(nil)
        return
      }
      #if os(iOS)
      // 무음 스위치와 상관없이 스피커로 들리게 함 (녹음 중엔 녹음기가 세션을 다시 잡음)
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try? AVAudioSession.sharedInstance().setActive(true)
      #endif
      if args["rewind"] as? Bool == true { player.currentTime = 0 }
      player.play()
      result(nil)
    case "pause":
      players[id]?.pause()
      result(nil)
    case "position":
      result(Int((players[id]?.currentTime ?? 0) * 1000))
    case "dispose":
      players[id]?.stop()
      players[id] = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard let id = players.first(where: { $0.value === player })?.key else { return }
    channel.invokeMethod("completed", arguments: id)
  }
}
