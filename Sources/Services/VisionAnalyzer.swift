import CoreGraphics
import Vision

struct VisionResult {
    /// 按行拼接的识别文字。
    let text: String
    /// 场景与物体标签（英文标识），保留原文让中英文都能搜。
    let labels: [String]
    /// 最高的一档文字置信度，用来判断这张图到底有没有被读清楚。
    let topConfidence: Float
}

/// 端侧 OCR 与场景标签。调用的是 iPhone 自己"实况文本"背后的同一套引擎，
/// 不联网、不上传，A13 之后的机器都能跑。
enum VisionAnalyzer {

    static func analyze(_ image: CGImage) async -> VisionResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<VisionResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: image, options: [:])

                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                textRequest.usesLanguageCorrection = true
                // 保留默认 recognitionLevel = accurate：中文识别精度优先，
                // 速度靠分批扫描和可中断保证，不靠降档。

                let classifyRequest = VNClassifyImageRequest()

                do {
                    try handler.perform([textRequest, classifyRequest])
                } catch {
                    continuation.resume(returning: VisionResult(text: "", labels: [], topConfidence: 0))
                    return
                }

                let observations = (textRequest.results as? [VNRecognizedTextObservation]) ?? []
                var lines = [String]()
                lines.reserveCapacity(observations.count)
                var topConfidence: Float = 0
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    topConfidence = max(topConfidence, candidate.confidence)
                    let value = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { lines.append(value) }
                }

                let classifications = (classifyRequest.results as? [VNClassificationObservation]) ?? []
                let labels = classifications
                    .filter { $0.confidence >= 0.10 }
                    .prefix(16)
                    .map { $0.identifier }

                continuation.resume(returning: VisionResult(text: lines.joined(separator: "\n"),
                                                            labels: Array(labels),
                                                            topConfidence: topConfidence))
            }
        }
    }
}
