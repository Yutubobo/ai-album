import AVFoundation
import Speech

/// 语音输入。优先用系统的设备端识别，走不通再退回在线识别，并在界面上说明。
///
/// 中文普通话的识别模型 iOS 就内置在系统里，所以"说一句话找照片"这条路
/// 不需要任何第三方语音服务。
@MainActor
final class SpeechInput: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isListening = false
    @Published private(set) var usesOnDevice = false
    @Published private(set) var message: String?
    @Published var transcript = ""

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 申请语音识别与麦克风权限，全部通过才置为可用。
    func prepare() async {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            message = "语音识别权限被拒绝，可以在系统设置里打开；也可以直接用键盘上的麦克风。"
            isReady = false
            return
        }

        let microphoneStatus = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                continuation.resume(returning: true)
            case .denied:
                continuation.resume(returning: false)
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            @unknown default:
                continuation.resume(returning: false)
            }
        }
        guard microphoneStatus else {
            message = "麦克风权限被拒绝，改用手机键盘自带的听写也能说话搜索。"
            isReady = false
            return
        }

        let candidate = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
        guard let candidate, candidate.isAvailable else {
            message = "这台设备的中文语音识别暂时不可用，可以用键盘听写代替。"
            isReady = false
            return
        }
        recognizer = candidate
        usesOnDevice = candidate.supportsOnDeviceRecognition
        isReady = true
        message = usesOnDevice ? "语音识别在本机完成，不联网。" : "语音识别需要联网，识别到的文字只用于搜索。"
    }

    func start() {
        guard isReady, let recognizer else { return }
        guard !isListening else { return }

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            message = "音频输入未准备好，再按一次试试。"
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            message = "麦克风启动失败：\(error.localizedDescription)"
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcript = text
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isListening || task != nil else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        task?.finish()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    /// 把听到的话交回搜索框。
    func commit() -> String {
        stop()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
