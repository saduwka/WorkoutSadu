import Foundation
import Speech
import AVFAudio

@Observable
final class SpeechRecognizer {
    var isRecording = false
    var transcript = ""
    var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micGranted else { return false }

        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        return speechStatus == .authorized
    }

    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание речи недоступно"
            return
        }

        transcript = ""
        error = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Ошибка аудиосессии"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        recognitionTask?.cancel()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in self.transcript = text }
            }
            if let err {
                let nsErr = err as NSError
                let isNormalCancel = nsErr.domain == "kLSRErrorDomain" && nsErr.code == 301
                let isNoSpeech = nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110
                if !isNormalCancel && !isNoSpeech {
                    Task { @MainActor in self.error = err.localizedDescription }
                }
            }
        }

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            self.error = "Ошибка запуска записи"
            stopRecording()
        }
    }

    func stopRecording() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
