# Shiva MatchTool - Android App

AI-powered video copyright matching tool for Android. Compare short video clips against long movies or full recordings using Google Gemini AI and local 24 fps FFmpeg chunk analysis.

## Features
- **Accurate Forensic Matching**: Compare short edited video clips against full movie footage frame-by-frame.
- **Frame-by-Frame 24 fps Analysis**: Exact forensic prompts with timestamps and verbatim dialogue analysis via Google Gemini AI.
- **Local FFmpeg Processing**: On-device 1-minute video chunking and clip extraction.
- **CPU & Thermal Protection**: Automatically detects CPU cores and limits FFmpeg workers to a maximum of 5 threads, avoiding thermal throttling and crashes on modern 8+ core chipsets.
- **Interactive Verification Player**: Side-by-side and timestamp-synchronized 60fps video comparison player.
- **No Video Size Limit**: Supports long movies through progressive chunking and stream processing.
- **Persistent Local History**: Scan logs and detected matches saved on device.

## Requirements
- Android 6.0+ (API level 23 minimum, target API 34)
- Google Gemini API key (from Google AI Studio)
- Active internet connection (for Gemini API calls)

## Getting Started
1. Clone or download the repository.
2. Open the `/mobile` directory in Android Studio or VS Code with the Flutter extension.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Build and run on an Android device or emulator:
   ```bash
   flutter run
   ```
5. Enter your Google Gemini API key in **Settings**.

## Production Build
```bash
flutter build apk --release
```
The resulting APK will be in `build/app/outputs/flutter-apk/app-release.apk`.
