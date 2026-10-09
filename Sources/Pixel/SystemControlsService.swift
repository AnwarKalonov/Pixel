import AppKit
@preconcurrency import AVFoundation
import Foundation
import SwiftUI

@MainActor
public final class SystemControlsService: ObservableObject {
    public static let shared = SystemControlsService()

    // MARK: - Audio Volume State
    @Published public var volume: Double = 50.0
    @Published public var isMuted: Bool = false

    // MARK: - Display Brightness State
    @Published public var brightness: Double = 70.0

    // MARK: - Media State
    @Published public var isPlaying: Bool = false
    @Published public var trackTitle: String = "No music playing"
    @Published public var trackArtist: String = ""
    @Published public var activePlayer: String = "Music"
    @Published public var albumArt: NSImage? = nil

    // MARK: - Camera Mirror State
    @Published public var isCameraActive: Bool = false
    @Published public var cameraError: String = ""
    public let captureSession = AVCaptureSession()
    private var isSessionConfigured = false

    private var refreshTimer: Timer?

    public init() {
        refreshVolume()
        refreshMedia()
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMedia()
            }
        }
    }

    // MARK: - Safe Command Execution (Process / osascript - never crashes the host process)
    nonisolated private func runCLIAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence any OSA terminology errors
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Async System Volume Control
    public func refreshVolume() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let volScript = "output volume of (get volume settings)"
            let muteScript = "output muted of (get volume settings)"

            let volStr = self.runCLIAppleScript(volScript)
            let muteStr = self.runCLIAppleScript(muteScript)?.lowercased()

            let vol = volStr.flatMap { Double($0) } ?? 50.0
            let muted = muteStr == "true"

            DispatchQueue.main.async {
                self.volume = vol
                self.isMuted = muted
            }
        }
    }

    public func setVolume(_ newVolume: Double) {
        self.volume = newVolume
        let intVol = max(0, min(100, Int(newVolume)))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runCLIAppleScript("set volume output volume \(intVol)")
        }
        if isMuted && newVolume > 0 {
            setMuted(false)
        }
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runCLIAppleScript("set volume output muted \(muted ? "true" : "false")")
        }
    }

    public func setBrightness(_ newBrightness: Double) {
        let clamped = max(0, min(100, newBrightness))
        self.brightness = clamped
        // Use osascript to set brightness via display preferences
        let level = clamped / 100.0
        let script = """
        tell application "System Events"
            try
                set value of slider 1 of group 1 of tab group 1 of window 1 of application process "System Preferences" to \(level)
            end try
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Try using brightness CLI tool if available
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }


    // MARK: - Resilient Media Player Control (Spotify, Apple Music, YouTube Music Desktop & Web)
    public func refreshMedia() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 1. YouTube Music Desktop / Pear Player Check (via HTTP or Local API)
            if let ytInfo = self.checkYouTubeMusicLocalAPI() {
                DispatchQueue.main.async {
                    self.activePlayer = "YouTube Music"
                    self.isPlaying = ytInfo.isPlaying
                    self.trackTitle = ytInfo.title
                    self.trackArtist = ytInfo.artist
                }
                return
            }

            // 2. Spotify Native App Check
            let spotifyCheck = "application \"Spotify\" is running"
            if self.runCLIAppleScript(spotifyCheck) == "true" {
                let query = """
                tell application "Spotify"
                    try
                        set s to player state as string
                        set t to name of current track
                        set a to artist of current track
                        return s & "|||" & t & "|||" & a
                    on error
                        return ""
                    end try
                end tell
                """
                if let result = self.runCLIAppleScript(query), result.contains("|||") {
                    let parts = result.components(separatedBy: "|||")
                    if parts.count >= 3 {
                        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                        let isPlay = parts[0].lowercased() == "playing"
                        if !title.isEmpty {
                            DispatchQueue.main.async {
                                self.activePlayer = "Spotify"
                                self.isPlaying = isPlay
                                self.trackTitle = title
                                self.trackArtist = artist
                            }
                            return
                        }
                    }
                }
            }

            // 3. Apple Music Native App Check
            let musicCheck = "application \"Music\" is running"
            if self.runCLIAppleScript(musicCheck) == "true" {
                let query = """
                tell application "Music"
                    try
                        set s to player state as string
                        set t to name of current track
                        set a to artist of current track
                        return s & "|||" & t & "|||" & a
                    on error
                        return ""
                    end try
                end tell
                """
                if let result = self.runCLIAppleScript(query), result.contains("|||") {
                    let parts = result.components(separatedBy: "|||")
                    if parts.count >= 3 {
                        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                        let isPlay = parts[0].lowercased() == "playing"
                        if !title.isEmpty {
                            DispatchQueue.main.async {
                                self.activePlayer = "Apple Music"
                                self.isPlaying = isPlay
                                self.trackTitle = title
                                self.trackArtist = artist
                            }
                            return
                        }
                    }
                }
            }

            // 4. Browser YouTube Music Tab Check (Chrome / Brave / Edge / Safari)
            if let webMedia = self.checkBrowserMediaTabs() {
                DispatchQueue.main.async {
                    self.activePlayer = webMedia.player
                    self.isPlaying = webMedia.isPlaying
                    self.trackTitle = webMedia.title
                    self.trackArtist = webMedia.artist
                }
                return
            }

            // Default idle state
            DispatchQueue.main.async {
                self.isPlaying = false
                self.trackTitle = "No music playing"
                self.trackArtist = "Spotify · Apple Music · YouTube"
            }
        }
    }

    public func togglePlayPause() {
        let player = activePlayer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if player == "YouTube Music" {
                self.sendYouTubeMusicCommand("toggle-play")
            } else if player == "Spotify" {
                _ = self.runCLIAppleScript("tell application \"Spotify\" to playpause")
            } else {
                _ = self.runCLIAppleScript("tell application \"Music\" to playpause")
            }
            DispatchQueue.main.async {
                self.refreshMedia()
            }
        }
    }

    public func nextTrack() {
        let player = activePlayer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if player == "YouTube Music" {
                self.sendYouTubeMusicCommand("next")
            } else if player == "Spotify" {
                _ = self.runCLIAppleScript("tell application \"Spotify\" to next track")
            } else {
                _ = self.runCLIAppleScript("tell application \"Music\" to next track")
            }
            DispatchQueue.main.async {
                self.refreshMedia()
            }
        }
    }

    public func previousTrack() {
        let player = activePlayer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if player == "YouTube Music" {
                self.sendYouTubeMusicCommand("previous")
            } else if player == "Spotify" {
                _ = self.runCLIAppleScript("tell application \"Spotify\" to previous track")
            } else {
                _ = self.runCLIAppleScript("tell application \"Music\" to previous track")
            }
            DispatchQueue.main.async {
                self.refreshMedia()
            }
        }
    }

    // MARK: - YouTube Music Companion / Local Endpoint Support
    private struct MediaInfo {
        let player: String
        let title: String
        let artist: String
        let isPlaying: Bool
    }

    nonisolated private func checkYouTubeMusicLocalAPI() -> MediaInfo? {
        guard let url = URL(string: "http://localhost:26538/query") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.4
        let sema = DispatchSemaphore(value: 0)
        var info: MediaInfo? = nil

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { sema.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let player = json["player"] as? [String: Any],
                  let track = json["track"] as? [String: Any] else {
                return
            }
            let title = track["title"] as? String ?? "YouTube Music"
            let artist = track["author"] as? String ?? ""
            let isPaused = player["isPaused"] as? Bool ?? true
            info = MediaInfo(player: "YouTube Music", title: title, artist: artist, isPlaying: !isPaused)
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 0.5)
        return info
    }

    nonisolated private func sendYouTubeMusicCommand(_ endpoint: String) {
        guard let url = URL(string: "http://localhost:26538/\(endpoint)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.0
        let task = URLSession.shared.dataTask(with: request)
        task.resume()
    }

    nonisolated private func checkBrowserMediaTabs() -> MediaInfo? {
        // Safe query against Chrome if running
        let chromeScript = """
        tell application "System Events"
            if exists (process "Google Chrome") then
                tell application "Google Chrome"
                    try
                        repeat with w in windows
                            repeat with t in tabs of w
                                set u to URL of t
                                if u contains "music.youtube.com" then
                                    return "YTM|||" & (title of t as text)
                                else if u contains "youtube.com/watch" then
                                    return "YT|||" & (title of t as text)
                                end if
                            end repeat
                        end repeat
                    end try
                end tell
            end if
        end tell
        return ""
        """
        if let res = runCLIAppleScript(chromeScript), res.contains("|||") {
            let parts = res.components(separatedBy: "|||")
            let rawTitle = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanTitle = rawTitle.replacingOccurrences(of: " - YouTube Music", with: "")
                                     .replacingOccurrences(of: " - YouTube", with: "")
            if !cleanTitle.isEmpty {
                return MediaInfo(
                    player: parts[0] == "YTM" ? "YouTube Music" : "YouTube",
                    title: cleanTitle,
                    artist: "Browser Audio",
                    isPlaying: true
                )
            }
        }
        return nil
    }

    // MARK: - Safe Camera Mirror
    public func toggleCamera() {
        if isCameraActive {
            stopCamera()
        } else {
            startCamera()
        }
    }

    public func startCamera() {
        guard !isCameraActive else { return }
        self.cameraError = ""

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureAndRunCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndRunCamera()
                    } else {
                        self?.cameraError = "Camera access denied. Enable in System Settings → Privacy."
                    }
                }
            }
        case .denied, .restricted:
            self.cameraError = "Camera access denied. Enable in System Settings → Privacy & Security."
        @unknown default:
            self.cameraError = "Camera unavailable."
        }
    }

    public func stopCamera() {
        guard isCameraActive else { return }
        let session = self.captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        self.isCameraActive = false
    }

    private func configureAndRunCamera() {
        if !isSessionConfigured {
            setupCaptureSession()
        }

        let session = self.captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning {
                session.startRunning()
            }
        }
        self.isCameraActive = true
    }

    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        if let device = AVCaptureDevice.default(for: .video) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
            } catch {
                self.cameraError = "Could not initialize camera: \(error.localizedDescription)"
            }
        } else {
            self.cameraError = "No video camera detected."
        }

        captureSession.commitConfiguration()
        isSessionConfigured = true
    }
}

// MARK: - Camera Preview NSViewRepresentable
public struct CameraPreviewView: NSViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public class PreviewNSView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }

    public func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView(session: session)
        return view
    }

    public func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer.frame = nsView.bounds
    }
}
