import Foundation
import Speech
import AVFoundation

/// 语音识别任务被用户取消时的 NSError 错误码（对应 macOS 的 SFSpeechRecognitionError.Code.canceled）
private let SpeechRecognitionCancelledCode = 216

/**
 * 语音输入管理器。
 *
 * 基于 SFSpeechRecognizer + AVAudioEngine 实现实时语音转写，
 * 通过 AsyncStream 持续回传识别文本（每次均为全量转写结果）；
 * 转写结束后可调用 DeepSeek 对识别文本进行错字矫正。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class VoiceInputManager {
    /// 当前是否正在录音识别
    private(set) var isRecording = false
    /// 当前是否正在 AI 矫正识别文本
    private(set) var isCorrecting = false
    /// 最近一次错误描述，用于界面提示
    private(set) var lastError: String?

    /// 设置存储，用于读取 LLM 模型配置
    private let settings: SettingsStore

    /// 中文语音识别器
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<String>.Continuation?

    /**
     * 初始化语音输入管理器。
     *
     * @param settings 设置存储（读取 LLM 模型配置）
     * @author xiangwei
     */
    init(settings: SettingsStore) {
        self.settings = settings
    }

    /**
     * 检查当前设备是否支持语音识别且已授权。
     *
     * @return 是否可直接开始识别
     * @author xiangwei
     */
    func checkAvailability() async -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }
        let status = await requestAuthorization()
        guard status == .authorized else { return false }
        return await requestMicrophonePermission()
    }

    /**
     * 请求语音识别授权（首次调用会弹出系统授权框）。
     *
     * 方法声明为 nonisolated：continuation 不关联 MainActor，
     * 授权回调（TCC 后台线程）可直接 resume，不会触发 iOS 26 的隔离断言崩溃。
     *
     * @return 授权状态
     * @author xiangwei
     */
    nonisolated func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /**
     * 请求麦克风权限（首次调用会弹出系统授权框）。
     *
     * @return 是否已授权
     * @author xiangwei
     */
    private func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /**
     * 开始实时语音识别，返回识别文本流。
     *
     * 流中的文本为全量转写结果（含中间结果），调用方直接赋值到输入框即可。
     *
     * @return 识别文本流
     * @throws VoiceInputError 设备不支持或权限被拒绝
     * @author xiangwei
     */
    func startRecognition() async throws -> AsyncStream<String> {
        // 若上一次会话未收尾，先清理
        stopRecognition()

        guard let recognizer, recognizer.isAvailable else {
            lastError = VoiceInputError.unavailable.localizedDescription
            throw VoiceInputError.unavailable
        }

        // 语音识别授权
        let speechStatus = await requestAuthorization()
        guard speechStatus == .authorized else {
            lastError = VoiceInputError.speechPermissionDenied.localizedDescription
            throw VoiceInputError.speechPermissionDenied
        }

        // 麦克风授权
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            lastError = VoiceInputError.microphonePermissionDenied.localizedDescription
            throw VoiceInputError.microphonePermissionDenied
        }

        // 配置录音音频会话
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // 创建识别请求，允许返回中间结果
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // 识别任务：回调在后台线程，切回主线程更新状态
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        // 启动录音引擎，将音频缓冲实时喂给识别请求
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        // 防御：硬件格式无效（采样率或声道数为 0）时，直接 installTap 会触发
        // IsFormatSampleRateAndChannelCountValid 断言崩溃，改用 48kHz 单声道标准格式兜底
        let tapFormat: AVAudioFormat
        if hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 {
            tapFormat = hwFormat
        } else if let fallback = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) {
            tapFormat = fallback
        } else {
            throw VoiceInputError.audioEngineUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { buffer, _ in
            // 音频线程回调：追加缓冲（SFSpeechAudioBufferRecognitionRequest.append 线程安全）
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // 解除已安装的 tap 并停用会话，避免资源泄漏影响下次录音
            inputNode.removeTap(onBus: 0)
            engine.stop()
            cleanup()
            lastError = error.localizedDescription
            throw error
        }
        audioEngine = engine
        isRecording = true
        lastError = nil

        // 先创建 continuation，再返回流，避免调用方延迟消费时丢失
        let (stream, streamContinuation) = AsyncStream<String>.makeStream()
        self.continuation = streamContinuation
        return stream
    }

    /**
     * 停止录音识别，结束文本流。
     *
     * @author xiangwei
     */
    func stopRecognition() {
        guard isRecording else { return }
        // 结束音频输入，触发最终识别回调
        recognitionRequest?.endAudio()
        // 立即收尾并结束文本流
        continuation?.finish()
        cleanup()
    }

    /**
     * 调用 DeepSeek 矫正语音识别文本中的错字。
     *
     * 通过流式接口收集完整响应；未配置 API Key 或矫正失败时返回原文，
     * 保证语音输入在无 AI 配置时依然可用。
     *
     * @param text 语音识别文本
     * @return 矫正后的文本
     * @author xiangwei
     */
    func correctSpeechText(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isCorrecting = true
        defer { isCorrecting = false }

        let apiKey = KeychainHelper.shared.readAPIKey() ?? ""
        guard !apiKey.isEmpty else { return trimmed }

        let stream = LLMProvider.chat(
            model: settings.llmModel,
            apiKey: apiKey,
            messages: [
                .system("你是中文语音识别结果纠错助手。用户输入的内容来自语音转写，可能存在同音字、错别字或识别错误。请纠正错别字和识别错误，保持原文意思、语气和口语化风格不变，不增删信息，不解释原因。直接输出纠正后的完整文本，不要添加任何前缀、引号或说明。"),
                .user(trimmed)
            ],
            tools: nil,
            stream: true,
            traceId: UUID().uuidString,
            roundIndex: 0,
            thinkingEnabled: false,
            reasoningEffort: "low"
        )

        var corrected = ""
        for try await event in stream {
            if case .chunk(let chunk) = event {
                corrected += chunk
            }
        }
        let result = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? trimmed : result
    }

    /**
     * 处理识别任务回调（主线程）。
     *
     * @author xiangwei
     */
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            continuation?.yield(result.bestTranscription.formattedString)
            if result.isFinal {
                continuation?.finish()
                cleanup()
                return
            }
        }
        if let error {
            // 用户主动停止触发的取消不视为错误
            if (error as NSError).code != SpeechRecognitionCancelledCode {
                lastError = error.localizedDescription
            }
            continuation?.finish()
            cleanup()
        }
    }

    /**
     * 清理录音引擎与识别任务（幂等，可在主线程安全重复调用）。
     *
     * @author xiangwei
     */
    private func cleanup() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        // 停用音频会话，让其他音频（如音乐）恢复播放
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/**
 * 语音输入错误类型。
 *
 * @author xiangwei
 */
enum VoiceInputError: LocalizedError {
    /// 设备不支持语音识别
    case unavailable
    /// 语音识别权限被拒绝
    case speechPermissionDenied
    /// 麦克风权限被拒绝
    case microphonePermissionDenied
    /// 录音引擎初始化失败
    case audioEngineUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前设备不支持语音识别，请改用文字输入。"
        case .speechPermissionDenied:
            return "请在系统设置中允许「笔笔」使用语音识别。"
        case .microphonePermissionDenied:
            return "请在系统设置中允许「笔笔」访问麦克风。"
        case .audioEngineUnavailable:
            return "录音引擎暂时不可用，请稍后重试。"
        }
    }
}
