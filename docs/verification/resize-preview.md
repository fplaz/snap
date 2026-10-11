# Bottom-right resize preview — 2026-10-08

- A black 2.5-point L marks the bottom-right corner, with a larger invisible hit region. Corner dragging takes priority over moving the area. The top-left corner stays fixed; resizing is clamped to the display and a 16-point minimum (or the original dimension if smaller).
- Annotation document coordinates and undo history are unchanged. A canvas offset preserves their screen positions while the bottom edge moves. Drawing, hit testing, text editing, and export account for that offset. The renderer clips annotation portions outside the canvas; growing it restores them.
- Toolbar axes follow independently. If initially below the bottom, it follows with its existing vertical gap; otherwise it waits until the bottom edge passes it with the default 10-point gap. Horizontal attachment uses the toolbar's right edge: when aligned with or beyond the canvas's right edge, it follows with its existing offset. A toolbar further left stays put until the canvas edge reaches its right edge, then follows with right edges aligned. Movement is clamped to the display's usable bounds.
- Escape restores the selection, toolbar, and annotation offset. Export is blocked while resizing; on release, CaptureSession receives the new rectangle.
- All 90 tests passed (`/tmp/snap-resize-tests.log`), including shrink/grow coordinate preservation, resize cancellation/minimum size, toolbar edge crossing, and session export guards. Universal Release preview compiled at `.build/area-drag-preview/Snap.app` (`/tmp/snap-resize-preview-build.log`). Manual visual review is pending.
- The distribution DMG remains build 5 and does not include resizing. This preview retains the previously approved border dragging.

## Follow-up fixes — 2026-10-10

- Doubled the border hit tolerance to 10 points inside/outside each edge, matching cursor rectangles and mouse hit testing. Active drags keep their closed-hand cursor even when crossing the resize handle or toolbar; the bottom-right handle still starts a resize.
- Corrected toolbar horizontal attachment from its left edge to its right edge. A normally aligned toolbar now follows both widening and narrowing of the canvas.
- All 92 tests passed (`/tmp/snap-resize-fixes-tests.log`), including near-border drags from inside/outside and right-edge alignment during shrinking/growing. The universal preview rebuilt successfully (`/tmp/snap-resize-fixes-preview-build.log`); the release DMG remains unchanged.
