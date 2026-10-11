# Selection dragging preview — 2026-10-08

## Final decision

The user approved border dragging for release and removed all edge grip indicators. Hovering the border shows an open hand; dragging shows a closed hand. The original compact toolbar placement is restored. All grip drawing, grip hit regions, and hover redraw state were removed. Historical preview iterations below describe the designs evaluated before this decision.

- Hover within five points of the selection border to show an open-hand cursor and six-dot grips centered on all four edges, half inside the selection and half outside. Side grips use vertical dot layouts. Grips stay within the display at screen boundaries; the toolbar's default position leaves additional space for the horizontal grips. Drag from the border or any visible grip; a closed hand indicates the active drag.
- Selection size and annotation coordinates stay unchanged. The crop rectangle moves over the frozen desktop on its current display, with the toolbar following and clamped to its usable bounds. Escape restores the original selection and toolbar position.
- Export is blocked during the gesture; releasing updates CaptureSession's crop rectangle for save, copy, and upload. Moving the area does not create annotation undo operations.
- 86 tests passed with no failures (`/tmp/snap-area-drag-tests.log`), including annotation preservation, toolbar movement, display clamping, Escape restoration, and session export state.
- Universal Release preview built at `.build/area-drag-preview/Snap.app`. The distribution DMG remains build 4. Manual visual review is pending the user's decision on shipping this interaction.
- The user confirmed the original single-grip preview worked. The four-grip update rebuilt successfully and passed all 86 tests (`/tmp/snap-four-grips-tests.log`); its visual review is pending.
- Subsequent visual refinements center each grip on its border and reduce both dimensions by 30% (32 × 20 points to 22.4 × 14, rotated on the vertical edges). Dot spacing, dot size, and corner radii scale by the same amount. These layout-only changes are compiled in the preview; the release DMG is unchanged.
