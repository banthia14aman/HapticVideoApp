# HapticVideo - Local Demo Version

**AI-Powered Haptic Video Platform for iOS** - No internet or Firebase required!

## 🎯 Features

- ✅ **Fully Local** - All data stored on device, no cloud setup needed
- ✅ **User Authentication** - Simple local login/signup
- ✅ **Video Upload** - Record or select from library
- ✅ **AI Haptic Generation** - Automatic haptic pattern creation
- ✅ **Immersive Playback** - Feel haptics synchronized with video
- ✅ **Public Feed** - Browse all uploaded videos
- ✅ **Profile Management** - View stats and manage account

## 📋 Prerequisites

- **Xcode 15.0+**
- **macOS 14.0+**
- **iOS 15.0+** target
- **Real iPhone 8+ for haptics** (simulator won't feel haptics)

## 🚀 Quick Setup (5 Minutes!)

### Step 1: Create Xcode Project

1. Extract the `HapticVideoApp` folder
2. Open **Xcode**
3. **File → New → Project**
4. Choose: **iOS → App**
5. Configure:
   - Product Name: `HapticVideoApp`
   - Team: Select your Apple ID
   - Organization Identifier: `com.yourname` (any domain)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - ❌ Uncheck: Core Data, Tests
6. Click **Next**
7. **Save in the extracted HapticVideoApp folder** (not inside it, same level)
8. Click **Create**

### Step 2: Add Source Files

1. In Xcode Project Navigator (left sidebar), **delete** these auto-generated files:
   - `ContentView.swift`
   - `HapticVideoAppApp.swift`

2. Drag folders from Finder into Xcode (onto "HapticVideoApp" group):
   - Drag `Models` folder
   - Drag `ViewModels` folder
   - Drag `Views` folder
   - Drag `Services` folder

3. Drag the two root Swift files:
   - `HapticVideoAppApp.swift`
   - `ContentView.swift`

4. When prompted:
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create groups"
   - ✅ Ensure "HapticVideoApp" target is selected
   - Click **Finish**

### Step 3: Configure Info.plist

1. Open `Info.plist` in Xcode
2. Right-click → **Add Row**, add these 3 keys:

**Privacy - Camera Usage Description**
```
Value: We need camera access to record videos with haptics.
```

**Privacy - Photo Library Usage Description**
```
Value: We need photo library access to select videos.
```

**Privacy - Microphone Usage Description**
```
Value: We need microphone access to record audio with your videos.
```

### Step 4: Build and Run!

1. Select simulator: **iPhone 15 Pro** (or any)
2. Press **⌘ + R** (or Product → Run)
3. Wait for build (30-60 seconds first time)
4. App launches! 🎉

## 📱 Testing on Real Device (for Haptics)

**IMPORTANT:** Haptics DON'T work in Simulator!

1. Connect your iPhone (8 or later) via USB
2. iPhone: Settings → General → VPN & Device Management → **Trust your computer**
3. Xcode: Select your iPhone from device dropdown (top bar)
4. Press **⌘ + R**
5. iPhone: Settings → General → VPN & Device Management → Trust the app
6. Now you can FEEL haptics! 🎉

## 🎮 How to Use

### First Launch
1. App shows login screen
2. Tap **"Don't have an account? Sign Up"**
3. Enter:
   - Username: `demo`
   - Display Name: `Demo User`
   - Email: `demo@test.com`
   - Password: `123456`
4. Tap **Sign Up**

### Browse Feed
- See 2 sample videos (mock data)
- Tap any video card to play
- Videos marked with 🟣 **HAPTIC** badge have haptics

### Upload a Video
1. Tap **Upload** tab (middle)
2. Tap **"Select Video"**
3. Choose a video from your library (or record new)
4. Enter title (e.g., "My First Haptic Video")
5. Tap **"Upload & Generate Haptics"**
6. Watch progress:
   - Upload: 0-60%
   - AI Generating: 60-90%
   - Finalizing: 90-100%
7. Success! Video appears in feed

### Watch with Haptics
1. Go to **Feed** tab
2. Tap your uploaded video
3. Video plays automatically
4. **On real iPhone:** Feel haptic feedback synchronized with video!
5. See pink dots on timeline = haptic events
6. Controls: Play/pause, seek backward/forward 10s

### Profile
- View upload count
- Sign out (clears local data)

## 📂 Project Structure

```
HapticVideoApp/
├── HapticVideoAppApp.swift          # App entry point
├── ContentView.swift                 # Main routing
│
├── Models/
│   ├── User.swift                    # User data model
│   ├── Video.swift                   # Video metadata
│   └── HapticEvent.swift             # Haptic patterns
│
├── ViewModels/
│   ├── AuthenticationViewModel.swift # Login logic
│   ├── FeedViewModel.swift           # Feed data
│   └── UploadViewModel.swift         # Upload + AI
│
├── Views/
│   ├── Authentication/
│   │   └── AuthenticationView.swift  # Login/signup UI
│   ├── Feed/
│   │   └── FeedView.swift            # Video feed
│   ├── Upload/
│   │   └── UploadView.swift          # Video upload
│   ├── Player/
│   │   └── VideoPlayerView.swift     # Playback + haptics
│   └── Profile/
│       └── ProfileView.swift         # User profile
│
└── Services/
    ├── LocalDataStore.swift          # Local storage (UserDefaults + Files)
    ├── HapticService.swift           # Core Haptics engine
    └── VideoPlayerService.swift      # AVPlayer wrapper
```

## 💾 How Data is Stored

**Everything is LOCAL** - No internet needed!

- **User Data:** UserDefaults (persists after app close)
- **Video Files:** App Documents folder
- **Thumbnails:** App Documents folder
- **Haptic Patterns:** JSON files in Documents
- **Video Metadata:** UserDefaults (JSON encoded)

**Location:** `/var/mobile/Containers/Data/Application/[APP-ID]/Documents/`

## 🤖 AI Haptic Generation

Currently generates **sample haptic events** automatically:

```swift
// In UploadViewModel.swift → generateHapticsWithAI()

// Creates haptic events every 2 seconds
// Types: Transient (tap), Impact (sharp hit), Continuous (vibration)
// Random intensity: 0.5-1.0
// Random sharpness: 0.3-0.8
```

**To Integrate Your ML Model:**

1. Open `ViewModels/UploadViewModel.swift`
2. Find `generateHapticsWithAI(for videoURL: URL)` function
3. Replace the sample generation code with:
   - Video frame extraction (Vision framework)
   - Audio waveform analysis (AVFoundation)
   - Your ML model inference (Core ML or API)
   - Convert predictions to `HapticEvent` array

**Output Format:**
```swift
HapticEvent(
    time: 5.2,              // 5.2 seconds into video
    intensity: 0.8,         // 0.0 to 1.0
    sharpness: 0.6,         // 0.0 to 1.0 (soft to sharp)
    duration: 0.2,          // 0.2 seconds long
    type: .continuous       // or .transient, .impact
)
```

## 🎨 Customization

### Change App Name
1. Xcode → Select Project → Target
2. **General** tab → Display Name: `"Your App Name"`

### Change Colors
Replace `Color.purple` and `Color.pink` with your brand colors:
- In all View files
- Or create a `Colors.swift` file with custom Color extensions

### Add Features
Easy to extend:
- **Comments:** Add `Comment` model, display under videos
- **Likes:** Add `likes: Int` to `Video` model
- **Search:** Filter `dataStore.allVideos` by title
- **Edit Haptics:** Create timeline editor view

## 🐛 Troubleshooting

### Build Errors

**"Cannot find 'LocalDataStore' in scope"**
- Fix: Ensure all files are added to target
- Project Navigator → Select file → File Inspector (right) → Target Membership → ✅ HapticVideoApp

**"Module compiled with Swift X.X cannot be imported"**
- Fix: Clean build folder
- Xcode → Product → Clean Build Folder (⌘ + Shift + K)
- Then build again (⌘ + B)

### Runtime Issues

**App crashes on launch**
- Check: Console for error messages (⌘ + Shift + Y to show)
- Common: Missing Info.plist keys (add camera/library permissions)

**Videos don't save**
- Check: Simulator has storage space
- Try: Reset simulator (Device → Erase All Content and Settings)

**Haptics don't work**
- ✅ Are you on a REAL iPhone (not simulator)?
- ✅ Is it iPhone 8 or later?
- ✅ Check Settings → Sounds & Haptics → System Haptics is ON
- Console should show: "Device supports haptics"

**Upload fails**
- Check video size (should be under 500MB)
- Check video format (MP4, MOV work best)
- Try a shorter video (under 1 minute for testing)

### Data Issues

**Lost videos after app restart**
- Check: UserDefaults is saving (print statements in LocalDataStore)
- Files should persist in Documents directory

**Want to reset all data?**
```swift
// Add this to ProfileView sign out:
UserDefaults.standard.removeObject(forKey: "allVideos")
try? FileManager.default.removeItem(at: LocalDataStore.shared.getDocumentsDirectory())
```

## 🚀 Next Steps

### Immediate
- [x] Test upload and playback
- [ ] Record a video with action/beats
- [ ] Feel the auto-generated haptics
- [ ] Customize haptic generation logic

### Soon
- [ ] Integrate your ML model for smart haptic detection
- [ ] Add haptic timeline editor for manual adjustment
- [ ] Improve AI with scene detection
- [ ] Add more haptic types (subtle textures, etc.)

### Later
- [ ] Add Firebase for cloud sync (optional)
- [ ] TestFlight beta testing
- [ ] App Store submission
- [ ] Analytics and crash reporting

## 📚 Learning Resources

- **SwiftUI:** https://developer.apple.com/tutorials/swiftui
- **Core Haptics:** https://developer.apple.com/documentation/corehaptics
- **AVFoundation:** https://developer.apple.com/av-foundation/
- **PhotosUI:** https://developer.apple.com/documentation/photokit
- **Core ML:** https://developer.apple.com/machine-learning/core-ml/

## 💡 Pro Tips

1. **Test on real device ASAP** - Haptics are the core feature!
2. **Start with short videos** (15-30 sec) for faster iteration
3. **Vary haptic types** - Mix transient (quick taps) with continuous (sustained)
4. **Match intensity to content** - Explosions = 1.0, footsteps = 0.3-0.5
5. **Don't overdo it** - Too many haptics = overwhelming, aim for key moments

## ⚠️ Known Limitations (Local Version)

- ❌ No cloud backup (data only on device)
- ❌ No user discovery (just your videos)
- ❌ No sharing between devices
- ❌ Limited storage (device only)

**Want cloud features?** Add Firebase later using my previous code!

## 🎉 You're Ready!

This is a **fully functional** haptic video app that works 100% offline.

**Total Setup Time:** 5 minutes  
**Dependencies:** 0 (no Firebase, no external SDKs!)  
**Internet Required:** ❌ Nope!

Just build, run, and start creating immersive haptic videos! 🚀

---

**Built for testing and local development**  
Add your AI model → Test haptics → Iterate quickly → Ship amazing experiences!

Good luck! Make videos you can FEEL! 🎯
