# Singletion

Singletion is a native macOS menu bar app that watches build outputs for local applications and keeps a single shared installed copy up to date.

When Singletion sees a newer build for a managed app, it can:

- detect the updated source app bundle
- stop the currently running installed copy
- replace the shared installed bundle
- relaunch the app
- record status, logs, and the last successful install

## Configuration model

Singletion uses a hybrid configuration model:

- GUI for onboarding and editing managed apps
- JSON config files on disk for portability, backup, and agent/script friendliness

Managed app definitions live in:

```bash
~/Library/Application Support/Singletion/apps/
```

Runtime state is stored separately and is not the source of truth.

## Development

1. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

2. Build from the command line:

   ```bash
   xcodebuild -project Singletion.xcodeproj -scheme Singletion -configuration Debug build
   ```

3. Install the app to a stable location and relaunch it:

   ```bash
   ./install-singletion.sh
   ```

## Notes

- Singletion runs as a menu bar app and uses the SF Symbol `die.face.1`.
- Launch at login can be toggled from the app UI.
- Self-management is supported with a detached helper shell flow so Singletion can update its own installed bundle when configured to do so.
