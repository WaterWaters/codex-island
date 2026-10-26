# Native state previews

Sixteen PNGs show Full and Mini mode for four states (`running`, `needsInput`, `blocked`, `idle`) on a notched MacBook-style display and a standard external display. All four README languages share these images and provide translated descriptions and alt text.

The images use the actual `IslandView`, `IslandGeometry`, outline and activity components. The surrounding desktop is an illustrative composition. Session metadata is synthetic, preferences are in memory, animations use a fixed paused phase, and Full mode uses the asset-free fallback cat symbol. Mini mode hides pets and text. No local sessions, installed Codex pet assets or private images are read. The displayed app UI is currently Simplified Chinese; app localization is available separately in Settings.

These are native SwiftUI renders, not desktop screenshots. They demonstrate layout and state styling; they do not prove real fullscreen, Spaces, external-display or notch behavior.

## Reproduce

From the repository root on macOS:

```bash
./Scripts/package_app.sh
./build/CodexIsland.app/Contents/MacOS/CodexIsland --render-gallery "$PWD/docs/assets/previews"
./build/CodexIsland.app/Contents/MacOS/CodexIsland --mini --render-gallery "$PWD/docs/assets/previews"
```

Each image is a Retina render of the same 648-point composition. Each invocation writes eight named PNGs (Mini files have a `mini-` prefix), leaving this guide intact. No private pet image is required. Artwork and generated previews follow the repository's MIT license.
