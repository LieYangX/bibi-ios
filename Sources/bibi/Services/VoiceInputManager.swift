import Foundation
import Speech

/// 语音输入管理器（暂用占位 - 需 iOS 26 SpeechAnalyzer API 完善）
@Observable
final class VoiceInputManager {
    func checkAvailability() async -> Bool { false }
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus { .denied }
    func startRecognition() async throws -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
    func stopRecognition() {}
}
