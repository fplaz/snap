# Milestone 2 verification

Implementation evidence for the annotation milestone, dated 2026-10-01. User acceptance and the hardware coverage below remain separate from automated checks.

## Implemented behavior

- Pen, arrow, line, rectangle, ellipse, and multiline text in the frozen capture overlay.
- Select, move, recolor, change stroke/font size, and delete objects; double-click selected text to edit it.
- Six colors, stroke widths 2/4/8 points, and text sizes 16/24/32 points.
- Ordered annotation objects with undo/redo; each completed gesture is one history entry. New edits invalidate redo.
- Crop remains fixed while annotating. Clear Annotations immediately removes drawing and text, including pending text, while preserving the selected area and toolbar (updated at the user's request on 2026-10-03).
- Native text editing owns text copy and undo; Return inserts a newline, Command–Return commits, and Escape cancels text editing.
- Preview and PNG export share annotation rendering. Export keeps original capture pixel dimensions and excludes toolbar/selection chrome.
- Copy/Save commit pending text. Export blocks overlapping gestures and edits; cancelled Save resumes the existing capture.
- Drawing invalidates the affected annotation region; it does not recapture the desktop or encode PNG on each event.

## Automated checks

- Shared Snap scheme built and tested on the Apple silicon development Mac using Xcode 27.0.
- `xcodebuild test`: **39 tests passed, 0 failures**. Result: `.build/xcode/Logs/Test/Test-Snap-2026.10.01_21-59-35--0300.xcresult`.
- Coverage includes existing capture/session/geometry behavior, document history, hit testing, clipping, fractional crop alignment, Retina stroke scale, empty-document pixel equivalence, multiline Unicode export, fixed crop while drawing, gesture cancellation, pending-text export, text-edit cancellation, export lockout, reset cleanup, and selected-text font-size layout/history.
- Final Apple Development app signature passes `codesign --verify --deep --strict` with host trust-store access. The sandbox-only invocation could not evaluate signing trust; the host verification succeeded.
- Restarted the development app from `.build/xcode/Build/Products/Debug/Snap.app` after the final tests.

## Desktop observations

- User invoked Command–Shift–7 and selected a region. The native accessibility tree and screenshot showed the annotation toolbar with Pen, Red, 4 pt, 24 pt, disabled Undo/Redo, and Copy/Save/Start Over/Cancel.
- Toolbar controls fit without overlap on the current display. Frozen capture resolution and shadows were accepted in milestone 1; no capture configuration change was made here.
- Subsequent native automation queries timed out. Drawing, native text shortcuts, Save cancellation, and export appearance have not yet been verified end-to-end through that connection.

## Remaining acceptance coverage

- Real desktop drawing/editing and Copy/Save output comparison, including native text undo/copy and input-method composition.
- Mixed-scale multiple displays, fullscreen apps, other supported macOS versions, and repeated-capture memory cleanup.
- Proposed p95 drawing latency of two display refresh intervals is unmeasured; passing interaction tests is not a displayed-frame latency result.
- The toolbar uses a fixed 460-by-96-point layout with popup tool/style controls; extremely narrow display configurations have not been exercised.

## Review

- Manual source review and an inline simplification pass corrected export callback wiring, transient Escape behavior, local redraw bounds, and text-height updates when changing font size.
- Code review: skipped (ce-code-review unavailable). This repository has no commits, so the dedicated workflow cannot resolve a comparison base and excludes untracked sources. No independent review receipt is claimed.
- No commit, push, or pull request was created. Changes remain local.

## Toolbar refinement — 2026-10-03

- Replaced the translucent two-row HUD with a 408-by-52-point black toolbar, metallic gradient, fine brushed texture, and subtle border/separators, using Linear’s website as the visual reference.
- Tool and color menus use icons/swatches. Tool names remain in tooltips and accessibility labels. Save, Copy, Start Over, Cancel, Undo, and Redo use icons.
- Contextual size menu: three stroke-thickness icons for non-text tools; three A-size icons for text. Independent width/font choices survive switching tools.
- Six-dot grip and open-hand cursor indicate dragging; toolbar background drags are constrained to the usable screen bounds without changing crop or document history. Export blocks toolbar dragging.
- Offscreen native AppKit previews were rendered and visually inspected in drawing and text modes. They establish appearance/layout, not real desktop pointer interaction.
- Full shared scheme: **41 tests passed, 0 failures**, including new contextual-size and toolbar-drag behavior checks. Result: `.build/xcode/Logs/Test/Test-Snap-2026.10.03_18-26-22--0300.xcresult`.
- Host signing verification passed; the final build was restarted through Finder and its process confirmed running. Real desktop interaction remains a user acceptance check.

### Clear action correction — 2026-10-03

The former Start Over action now clears annotations without resetting the selected area or moving/hiding the toolbar. Pending text and gestures are cancelled, and annotation undo/redo history is cleared. The tooltip/accessibility label is now Clear Annotations. The full shared scheme passed **42 tests, 0 failures**, including pending-text cleanup and crop/toolbar preservation (`Test-Snap-2026.10.03_18-38-25--0300.xcresult`).
