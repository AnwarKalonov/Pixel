import AppKit
import Foundation
import ScreenCaptureKit
@preconcurrency import Vision

struct ScreenSense {
    struct Shot {
        var jpeg: Data
        var ocr: String
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
            let ocr = await recognize(cgImage)
            return Shot(
                jpeg: jpeg,
                ocr: ocr,
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

    private func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }
}
