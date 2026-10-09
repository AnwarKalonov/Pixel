import AppKit
import Foundation
import ScreenCaptureKit
@preconcurrency import Vision

struct ScreenSense {
    struct WordBox {
        var text: String
        var rect: CGRect // AppKit coordinates on NSScreen.main
        var confidence: Float
    }

    struct Shot {
        var jpeg: Data
        var ocr: String
        var words: [WordBox]
        var imageSize: CGSize
        var displayID: CGDirectDisplayID
        var screenFrame: CGRect

        func point(normalized n: CGPoint) -> CGPoint {
            let px = screenFrame.minX + CGFloat(n.x) * screenFrame.width
            let pyFromTop = CGFloat(n.y) * screenFrame.height
            return CGPoint(x: px, y: screenFrame.maxY - pyFromTop)
        }

        func rect(normalized n: CGRect) -> CGRect {
            let origin = point(normalized: n.origin)
            let size = CGSize(width: n.width * screenFrame.width, height: n.height * screenFrame.height)
            return CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        }

        func findText(_ target: String) -> WordBox? {
            let clean = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = words.first(where: { $0.text.lowercased() == clean }) {
                return exact
            }
            return words.first(where: { $0.text.lowercased().contains(clean) })
        }
    }

    @MainActor
    func capture() async -> Shot? {
        guard let screen = NSScreen.main else { return nil }
        let displayID = screen.displayID
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.capturesAudio = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let jpeg = jpegData(from: cgImage, maxWidth: 1280)
            let (ocr, words) = await recognizeWords(cgImage, screenFrame: screen.frame)
            return Shot(
                jpeg: jpeg,
                ocr: ocr,
                words: words,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height),
                displayID: display.displayID,
                screenFrame: screen.frame
            )
        } catch {
            return nil
        }
    }

    private func jpegData(from image: CGImage, maxWidth: CGFloat) -> Data {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxWidth / width)
        let size = NSSize(width: width * scale, height: height * scale)
        let bitmap = NSImage(cgImage: image, size: size)
        guard let tiff = bitmap.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.62])
        else {
            return Data()
        }
        return data
    }

    private func recognizeWords(_ image: CGImage, screenFrame: CGRect) async -> (String, [WordBox]) {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [String] = []
                var boxes: [WordBox] = []

                for obs in observations {
                    guard let topCandidate = obs.topCandidates(1).first else { continue }
                    lines.append(topCandidate.string)

                    // Convert Vision normalized bounding box (origin bottom-left [0,1]) to AppKit screen coordinates
                    let box = obs.boundingBox
                    let x = screenFrame.minX + box.origin.x * screenFrame.width
                    let y = screenFrame.minY + box.origin.y * screenFrame.height
                    let w = box.width * screenFrame.width
                    let h = box.height * screenFrame.height
                    let appKitRect = CGRect(x: x, y: y, width: w, height: h)

                    boxes.append(WordBox(text: topCandidate.string, rect: appKitRect, confidence: topCandidate.confidence))
                }
                continuation.resume(returning: (lines.joined(separator: "\n"), boxes))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: ("", []))
                }
            }
        }
    }
}

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }
}
