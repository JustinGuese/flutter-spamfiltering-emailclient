# Platform-Specific Notes

This document collects platform-specific requirements, configuration constraints, credential storage backends, and known environment gotchas verified directly against the codebase in `app/` and the system build scripts.

---

## Linux

### System Dependencies

Building and running on desktop Linux (Ubuntu, Debian, Fedora, Arch) requires the following development packages:

- **Build Tools**: `clang`, `cmake` (`>= 3.13`), `ninja-build`, `pkg-config`
- **GTK Toolkit**: `libgtk-3-dev` (checked via `pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)` in `app/linux/CMakeLists.txt`)
- **Keyring Storage**: `libsecret-1-dev`, `gnome-keyring`, and `libsecret-tools`
- **Attachments (runtime)**: the file picker uses the freedesktop file-chooser portal over D-Bus (`xdg-desktop-portal` with a backend such as `xdg-desktop-portal-gtk`, present on ordinary GNOME/KDE desktops), and opening a received file uses `xdg-open`. Without them the compose window and the reader report that the picker or an app to open the file is unavailable; nothing else breaks.

### Secure Credential Storage (`libsecret`)

Email account credentials (IMAP/SMTP passwords and auth tokens) are saved using `flutter_secure_storage`. On Linux, this library relies on `libsecret-1` to communicate with the system Secret Service (such as GNOME Keyring or KWallet) over D-Bus.

If running in a container, virtual machine, SSH session, or headless CI environment without a graphical desktop session, you must start a D-Bus session with an unlocked keyring daemon:

```bash
eval $(dbus-launch --sh-syntax)
eval $(gnome-keyring-daemon --start --components=secrets)
```

Without an active Secret Service provider, credential read and write operations will fail.

### Wayland and `GDK_BACKEND`

On certain Linux desktop environments using Wayland (notably GNOME on Wayland or Sway), Flutter's GTK embedding may exhibit rendering artifacts or window management bugs. If this occurs, force the GTK X11 backend:

```bash
cd app
GDK_BACKEND=x11 flutter run -d linux
```

---

## macOS

### Minimum Deployment Target

- **macOS Target**: `12.0` (configured via `MACOSX_DEPLOYMENT_TARGET = 12.0` in `app/macos/Runner.xcodeproj/project.pbxproj` and `app/macos/Runner/Info.plist`).

### App Sandbox & Entitlements

The macOS target has App Sandbox enabled by default in both debug and release configurations:

- `app/macos/Runner/DebugProfile.entitlements`:
  - `com.apple.security.app-sandbox`: `true`
  - `com.apple.security.cs.allow-jit`: `true`
  - `com.apple.security.network.server`: `true`
  - `com.apple.security.network.client`: `true`
  - `com.apple.security.files.user-selected.read-write`: `true`
- `app/macos/Runner/Release.entitlements`:
  - `com.apple.security.app-sandbox`: `true`
  - `com.apple.security.network.client`: `true`
  - `com.apple.security.files.user-selected.read-write`: `true`

!!! warning "Entitlements that must stay"
    Sandboxed macOS applications require `com.apple.security.network.client` to establish outgoing TCP connections (IMAP/SMTP on ports 993/465/587, the community API over HTTPS), and `com.apple.security.files.user-selected.read-write` for the file picker used to attach files and to save received ones. Keep both in the debug and release entitlements.

### Keychain Services

Credentials are stored securely in the macOS Keychain Services API using `flutter_secure_storage`. Sandboxed apps access Keychain items scoped to their bundle identifier.

---

## Windows

### CMake and Toolchain

- **CMake Minimum Version**: `3.14` (configured in `app/windows/CMakeLists.txt`).
- **CMake Policy Range**: `3.14...3.25` for modern C++ CMake target behavior.
- **Build Requirements**: Visual Studio 2022 (or VS 2019) with C++ Desktop Development and Windows 10/11 SDK.

### Attachments

The file picker is the native Windows dialog and received files open with the default handler for their type (`ShellExecute`). Program and script types are never opened from the reader, only saved.

### Credential Storage

On Windows, `flutter_secure_storage` persists credentials via the Windows Data Protection API (DPAPI) and Windows Credential Manager. No external daemons or services are required.

---

## Android

### Build Configuration

- **Gradle Build Script**: Kotlin DSL (`app/android/app/build.gradle.kts`).
- **Java Compatibility**: Java 17 (`JavaVersion.VERSION_17`, Kotlin JVM target `17`).
- **Application ID / Namespace**: `com.datafortress.spamfilteringemailclient`.
- **SDK Targets**:
  - `compileSdk`: Inherited from `flutter.compileSdkVersion`.
  - `minSdk`: Inherited from `flutter.minSdkVersion` (minimum supported version is determined by plugin requirements).
  - `targetSdk`: Inherited from `flutter.targetSdkVersion`.

### Attachments

Files are picked with the system document picker (Storage Access Framework), so no storage permission is needed. Received files are opened through `open_filex`'s `FileProvider`, which covers the app's private files directory where downloads are kept.

### Credential Storage

Credentials are stored in Android `EncryptedSharedPreferences` backed by the hardware-isolated Android Keystore.

---

## iOS

### Deployment Target

- **iOS Target**: `15.0` (configured via `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in `app/ios/Runner.xcodeproj/project.pbxproj`).

### Attachments

No `Info.plist` keys are needed: files are chosen with the system document picker and opened with the system document viewer.

### Credential Storage

Credentials use iOS Keychain Services with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` protection via `flutter_secure_storage`.
