App Link: (https://lantas-pixel.netlify.app/))

---

## What is Pixel?

Pixel is an open-source, on-device AI assistant designed specifically for macOS. Living natively within the MacBook display notch, Pixel uses an expressive eye animation system to signal background reasoning, task execution, and visual tracking.

Unlike traditional chat interfaces, Pixel maintains real-time context of your active display, allowing it to execute multi-step workflows, control desktop applications, index your local file system, and auto-generate meeting documentation as you work.

---

## Features

### Notch-Native Interface

* Sits unobtrusively inside the physical camera notch on Apple Silicon MacBooks.
* Expressive state machine updates eye movements to visually communicate focus, reading, indexing, and executing states.

### Screen Perception & Control

* Reads screen content using native OCR and computer vision pipelines to parse application UI, text, and layout coordinates.
* Programmatically interacts with elements via Accessibility APIs—clicking, typing, scrolling, and arranging windows autonomously.

### Deep File Search & Indexing

* Performs fast local semantic and keyword searches across documents, code repositories, and user directories.
* Zero-cloud dependency for indexing—all vector embeddings and search metadata reside locally on disk.

### Automated Meeting Intelligence

* Detects active video calls across Zoom, Google Meet, Microsoft Teams, and FaceTime.
* Transcribes system audio in real time, cross-references shared visual slides, and writes structured meeting notes with direct action items.

---

## Prerequisites

* **macOS:** 12.0 (Monterey) or higher (*macOS 14+ Sonoma or 15+ Sequoia recommended for notch integration*).
* **Architecture:** Apple Silicon (M1/M2/M3/M4) required for hardware-accelerated local vision inference.
* **Dependencies:** Xcode Command Line Tools, Swift 5.9+, Node.js 18+ (for UI tools).

---

## Quick Start

### 1. Installation

Clone the repository and build the release binary:

```bash
git clone https://github.com/your-username/pixel.git
cd pixel
swift build -c release

```

Alternatively, install via Homebrew Cask:

```bash
brew tap your-username/pixel
brew install --cask pixel

```

### 2. Granting System Permissions

Pixel requires specific macOS system authorizations to perform on-screen actions and file indexing. Go to **System Settings > Privacy & Security** and enable:

| Permission | Reason for Access |
| --- | --- |
| **Accessibility** | Issue synthetic keystrokes, click UI elements, and manage application windows. |
| **Screen Recording** | Capture screen frames for OCR, layout parsing, and visual assistant context. |
| **Microphone** | Capture audio input for voice commands and real-time meeting transcription. |
| **Full Disk Access** | Build local vector indices for instant file and document searches. |

---

## Usage

Launch Pixel using the compiled binary or shortcut:

```bash
.build/release/Pixel

```

* **Toggle Overlay:** Press `Option + Space` or hover your cursor directly over the notch.
* **Command Examples:**
* *"Summarize the document currently open on my right display."*
* *"Find the PDF invoice from last week and move it to my Downloads folder."*
* *"Take notes during this call and send the summary to my notes app."*
* *"Open Terminal and run the test suite for this project."*



---

## Architecture

```
                       +-----------------------+
                       |   Notch UI Renderer   |
                       | (SwiftUI / Canvas 2D) |
                       +-----------+-----------+
                                   |
         +-------------------------+-------------------------+
         |                         |                         |
         v                         v                         v
+------------------+     +-------------------+     +-------------------+
|  Vision & Screen |     |  System Action    |     | Local Vector &    |
|   Parser Engine  |     | Orchestrator (AX) |     | File Search Index |
+------------------+     +-------------------+     +-------------------+

```

---

## Configuration

Settings are stored in `~/.pixel/config.json`. You can modify these values directly or via the settings panel:

```json
{
  "notch": {
    "eye_animations": true,
    "adaptive_theme": true
  },
  "privacy": {
    "on_device_only": true,
    "excluded_apps": ["1Password", "Keychain Access", "Bitwarden"]
  },
  "search": {
    "indexed_directories": ["~/Documents", "~/Desktop", "~/Developer"]
  }
}

```

---

## Privacy & Security

* **Local Execution:** Vision processing, speech recognition, and local file searches are executed entirely on your hardware using Apple Silicon's Neural Engine.
* **Sensitive App Isolation:** Pixel automatically pauses screen capture when focusing on password managers, banking applications, or user-blacklisted software.

---

## Contributing

Pull requests are welcome. For major structural changes, please open an issue first to discuss what you would like to change.

1. Fork the Repository
2. Create your Feature Branch (`git checkout -b feature/NewFeature`)
3. Commit your Changes (`git commit -m 'Add NewFeature'`)
4. Push to the Branch (`git push origin feature/NewFeature`)
5. Open a Pull Request

---

## License

Distributed under the [MIT License](https://www.google.com/search?q=LICENSE).
