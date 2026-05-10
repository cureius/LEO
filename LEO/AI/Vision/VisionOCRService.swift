import Vision
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "vision-ocr")

// MARK: - On-device OCR using Apple Vision framework

/// Extracts text from images on-device — free, private, no API tokens consumed.
/// Used as the first pass before sending to Claude so only text (not pixels) goes to the API.
actor VisionOCRService {

    static let shared = VisionOCRService()

    /// Recognise text in JPEG data. Returns the extracted string, or nil if nothing readable found.
    func recognizeText(from imageData: Data) async -> String? {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            logger.warning("OCR: could not decode image data")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    logger.warning("OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                // Join lines top-to-bottom (Vision returns bounding boxes in image coords)
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY } // top of image first
                    .compactMap { $0.topCandidates(1).first?.string }

                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                logger.info("OCR extracted \(text.split(separator: "\n").count) lines, \(text.split(separator: " ").count) words")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            request.recognitionLevel = .accurate          // slower but far better for handwriting
            request.usesLanguageCorrection = true          // fix common misspellings
            request.recognitionLanguages = ["en-US"]       // extend if needed

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.warning("OCR handler error: \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }
}
