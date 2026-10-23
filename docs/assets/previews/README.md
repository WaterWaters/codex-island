# Native state previews

Eight PNGs show four states (`running`, `needsInput`, `blocked`, `idle`) on a notched MacBook-style display and a standard external display. All four README languages share these images and provide translated descriptions and alt text.

The images use the actual `IslandView`, `IslandGeometry`, outline and activity components. The surrounding desktop is an illustrative composition. Session metadata is synthetic, preferences are in memory, animations use a fixed paused phase, and the asset-free fallback cat symbol is used. No local sessions, installed Codex pet assets or private images are read. The displayed app UI is currently Simplified Chinese; these images do not imply that app localization is implemented.

These are native SwiftUI renders, not desktop screenshots. They demonstrate layout and state styling; they do not prove real fullscreen, Spaces, external-display or notch behavior.

## Reproduce

From the repository root on macOS:

```bash
./Scripts/package_app.sh
./build/CodexIsland.app/Contents/MacOS/CodexIsland --render-gallery "$PWD/docs/assets/previews"
```

Each image is a Retina render of the same 648-point composition. The generator writes only the eight named PNGs, leaving this guide intact. No private pet image is required. Artwork and generated previews follow the repository's MIT license.
