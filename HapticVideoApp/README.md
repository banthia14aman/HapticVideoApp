# HapticVideoApp

A modern iOS application for recording, editing, and sharing videos with synchronized haptic feedback. Built natively with SwiftUI, AVFoundation, and powered by Firebase.

## 🎯 Features

- ✅ **Cloud-Powered Backend** - Synchronized across devices using Firebase
- ✅ **Authentication** - Secure email/password login via Firebase Auth
- ✅ **Video Upload & Storage** - Upload heavy video assets directly to Firebase Cloud Storage
- ✅ **AI Haptic Generation** - Automatic, audio-driven haptic pattern creation
- ✅ **Immersive Playback** - Feel haptics perfectly synchronized with the video
- ✅ **Deep Linking** - Share videos seamlessly with friends using custom universal links (`hapticapp://video/...`)
- ✅ **In-App Feedback** - Direct integration to submit bug reports and feature requests via GitHub Issues

## 📋 Prerequisites

- **Xcode 15.0+**
- **macOS 14.0+**
- **iOS 15.0+** target
- **Real iPhone 8+** (Required for haptic feedback; simulators cannot generate physical haptics)
- **Firebase Account**

## 🚀 Setup Guide

### 1. Clone the Repository
```bash
git clone https://github.com/banthia14aman/HapticVideoApp.git
cd HapticVideoApp
```

### 2. Configure Firebase
Since this app relies on Firebase for its backend, you need to provide your own `GoogleService-Info.plist` file.
1. Go to [console.firebase.google.com](https://console.firebase.google.com/) and create a new project.
2. Add an iOS app with the bundle identifier matching this Xcode project.
3. Download the `GoogleService-Info.plist` file.
4. Drag and drop the downloaded plist file into the Xcode Project Navigator.

### 3. Enable Firebase Services
In your Firebase Console, ensure the following are enabled:
- **Authentication**: Enable the "Email/Password" sign-in method.
- **Firestore Database**: Create a database (start in Test Mode or apply proper Security Rules).
- **Cloud Storage**: Initialize a storage bucket.

### 4. Build and Run!
1. Connect your physical iPhone.
2. Press **⌘ + R** (or Product → Run) in Xcode.
3. Trust the developer certificate in your iPhone Settings if prompted.
4. Feel the haptics! 🎉

## 🎮 How to Use

### Uploading & AI Haptics
1. Tap the **Upload** tab.
2. Select a video from your library.
3. Tap **Upload & Generate Haptics**. The app runs an on-device FFT audio analysis to generate haptics before uploading the assets to Firebase.

### Sharing Videos
1. Find any video in your Feed.
2. Copy the shared deep link.
3. When someone opens the link, the app will instantly launch and stream the video directly from the cloud backend.

## 🤝 Contributing & Feedback
Have a suggestion or found a bug? You can use the built-in "Give Feedback" button in the app's Profile page, which automatically formats your feedback and creates a new Issue on this repository!

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
