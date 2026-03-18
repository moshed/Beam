# Beam - Spotlight Alternative

A macOS Spotlight replacement with instant math, natural language calculations, unit/currency conversions, and search for apps, contacts, and files.

## Architecture

- **SwiftUI + AppKit hybrid**: Menu bar app (LSUIElement) with NSPanel floating window
- **No sandbox**: Required for Carbon global hotkey, launching apps, file access
- **Global hotkey**: Option+Space (Carbon API)
- **NSVisualEffectView**: Frosted glass HUD appearance

## Structure

```
Beam/
  App/
    BeamApp.swift          - @main entry, empty window scene
    AppDelegate.swift      - Status item, panel lifecycle, hotkey setup
  Models/
    SearchResult.swift     - Unified result type (math, contact, app, file)
  Services/
    HotkeyManager.swift    - Carbon global hotkey (Option+Space)
    MathEvaluator.swift    - Math, dates, units, currency conversions
    AppSearcher.swift      - Cached app list from /Applications
    ContactSearcher.swift  - CNContactStore search
    FileSearcher.swift     - NSMetadataQuery Spotlight search
    SearchCoordinator.swift - Orchestrates all searchers, debounces
  Views/
    BeamPanel.swift        - NSPanel subclass, floating, vibrancy
    BeamContentView.swift  - Main SwiftUI content (search + results)
    SearchBarView.swift    - NSViewRepresentable text field
    SearchResultRow.swift  - Individual result row
    ResultsListView.swift  - Scrollable results list
  Utilities/
    KeyEventHandler.swift  - NSEvent monitor for arrow keys, Enter, Escape
```

## Key Patterns

- Panel follows Clipboard Manager pattern (NSPanel + NSVisualEffectView + NSHostingView)
- HotkeyManager uses Carbon RegisterEventHotKey (signature: "BEAM" = 0x4245414D)
- SearchCoordinator is @Observable, drives all UI updates
- Math evaluation: NSExpression for standard math, custom parsers for natural language/units/currency
- App search: cached list scanned at launch (instant results)
- File search: async NSMetadataQuery (streams in after debounce)
- Currency rates: fetched from open.er-api.com, cached for 1 hour

## Bundle ID

`com.DNZ.beam`

## Build

```bash
xcodebuild -project Beam.xcodeproj -scheme Beam -configuration Debug build
```

Symlinked app: `Beam.app` -> DerivedData build output
