/*
================================================================================
  Edit_Finalize.ijm
  Triggered by: F2
================================================================================
  Opens the skeletonization pipeline on the current cell image, lets you
  manually edit the skeleton if needed, then collects all measurements and
  writes them to a per-folder Excel file.

  Controls (both editing stages use the same COMPOSITE-window pattern):
    Stage 1 -- skeleton (channel 1 = RED skeleton, channel 2 = GREEN cell):
      Space  →  Re-skeletonize from your edits and refresh the composite preview
      Shift  →  Finish skeleton edits and move on to soma review
    Stage 2 -- soma (channel 1 = RED soma mask, channel 2 = GREEN cell):
      Space  →  Sync your edits into the mask and print live Area/Circ/AR/
                Solidity stats to the Log, so you can see the numbers as you paint
      Shift  →  Accept the soma, collect data, and advance to the next image

  How to edit on the Composite (both stages):
    - Make sure channel 1 is active (slider at bottom of Composite window).
    - Select the Brush tool. Set foreground to WHITE to add (branches or soma).
    - Set foreground to BLACK to erase (branches or soma).
    - You see exactly what you are adding/removing against the cell image.
    - If nothing was automatically detected for the soma, it just starts as
      an empty (black) channel 1 - paint the soma directly with the white
      brush, or press Shift immediately to accept an empty soma (Area = 0).

  See "SOMA EDITING" below for more on the second stage.

  Data collected per cell:

  "Summary" sheet (one row per cell — easy-read overview):
    Cell_ID                   — crop number (1, 2, 3 …)
    Soma_Area_um2             — largest detected soma blob (µm²)
    Soma_Circularity          — soma roundness 0–1 (1=perfect circle; LPS→higher)
    Soma_AR                   — soma major/minor axis ratio (LPS→closer to 1)
    Soma_Solidity             — soma area / convex hull area (LPS→higher)
    Num_Branches              — total branches across all skeleton components
    Total_Branch_Length_um    — sum of all branch lengths (µm)
    Avg_Branch_Length_um      — mean branch length (µm)
    Max_Branch_Length_um      — longest single branch (µm)
    Num_Junctions             — junction voxel count
    Num_Endpoints             — end-point voxel count
    Num_Triple_Points         — triple-point count (3-way forks)
    Num_Quadruple_Points      — quadruple-point count (4-way forks)
    Ramification_Index        — Total_Branch_Length / Soma_Area (LPS→lower)
    Junction_Density          — Num_Junctions / Total_Branch_Length (LPS→lower)
    Endpoint_Density          — Num_Endpoints / Total_Branch_Length (LPS→lower)
    Avg_Span_Ratio            — mean (Euclidean_Distance / Branch_Length) per branch,
                                 0–1; high = straight processes (LPS→higher)
    Branch_Density            — Num_Branches / Soma_Area (LPS→lower)
    Complexity_Index          — (Num_Endpoints * Total_Branch_Length) / Soma_Area
                                 (compound ramification measure; LPS→lower)

  "Detailed" sheet (one row per branch — all data from Branch information table):
    Cell_ID                   — which cell this branch belongs to
    Skeleton_ID               — component index within the skeleton
    Branch_Length_um          — length of this individual branch (µm)
    V1x, V1y                  — start endpoint coordinates (µm)
    V2x, V2y                  — end endpoint coordinates (µm)
    Euclidean_Distance_um     — straight-line tip-to-tip distance (µm)
    Running_Avg_Length_um     — running average length up to this branch (µm)
    Branch_Type               — slab type code from Analyze Skeleton

  Output files saved per cell, into that cell's own subfolder
  (e.g. <BaseName>-Images/<name>-N/):
    <name>-N.tif                   — the original crop (saved by F1)
    <name>-N(Skeleton).tif         — final edited skeleton (with scale bar)
    <name>-N(Tagged-Skeleton).tif  — colour-coded skeleton (with scale bar)
    <name>-N(Composite).tif        — red skeleton + green cell overlay (with scale bar)
    <name>-N(Soma-Mask).tif        — white soma blob on black background (with scale bar)
    <name>-N(Soma-Overlay).tif     — cell image (green) with soma region (cyan) (with scale bar)

  One level up, in the main <BaseName>-Images folder (shared across all cells):
    <name>-Data.xlsx               — Summary sheet (per cell) + Detailed sheet (per branch)

  NOTES:
    * Always close the Excel file before pressing Shift.
    * If your microglia channel is not FITC (channel 1), set MICROGLIA_CHANNEL
      below to the correct channel number — it is passed automatically to
      Skeletonize_And_Detect_Soma.ijm, so you only need to change it here.
    * Pixel size is read from the image's own calibration (Image > Properties).
      If images were saved without calibration, measurements will fall back to pixels.
    * All 16-bit -> 8-bit conversions used for measurement are now independent
      of any manual Brightness/Contrast left on screen from F1 preprocessing
      (see SOURCE_INTENSITY_MAX below) -- otherwise SOMA_ABS_MIN_INTENSITY and
      PROCESS_FIXED_THRESHOLD would mean different things on different images.
    * A batch's calibration (calibrated vs. not, and the um/px scale) is
      locked the first time any cell in that "<BaseName>-Images" folder is
      finalized, and every later cell is checked against it -- including
      across a resumed session on a different day. A mismatch stops with an
      on-screen message instead of writing inconsistent columns.
    * Redoing a cell that's already been written to Excel now asks for
      confirmation first, since the plugin can't overwrite an existing row
      from a macro - continuing creates a second row for that Cell_ID.
    * Every cell now goes through a second brush-editing stage for the soma
      (same Space/Shift pattern as skeleton editing) before its measurements
      are written. See "SOMA EDITING" below.
================================================================================
*/

// ── Tunable Parameters — SINGLE SOURCE OF TRUTH ──────────────────────────────
//
// All parameters live here. Edit_Finalize.ijm passes them to
// Skeletonize_And_Detect_Soma.ijm via setProperty/getProperty at call time
// (see runSkeletonizeAndPreparePreview below), so there is no second copy to
// keep in sync. Do NOT add a duplicate parameter block to Skeletonize.

// Channel: 1=FITC, 2=TRITC, 3=CY5
MICROGLIA_CHANNEL = 1;

// --- 16-bit -> 8-bit normalisation ---
// IMPORTANT: every absolute intensity threshold below (SOMA_ABS_MIN_INTENSITY,
// PROCESS_FIXED_THRESHOLD) is expressed in 8-bit values (0-255). Converting a
// 16-bit source image to 8-bit with ScaleConversions on (the standard IJ
// approach) rescales using the image's CURRENT DISPLAY min/max -- i.e.
// whatever Brightness/Contrast was left on screen from the manual
// preprocessing step in F1. That means the same real fluorescence signal
// could be mapped to different 8-bit values on different images/days,
// silently breaking the absolute thresholds this pipeline depends on for
// comparing LPS vs PBS.
//
// By design, before every 16(or 32)-bit -> 8-bit conversion used for
// measurement, the display range is reset first (see normalizeTo8Bit() below),
// so the conversion reflects the image's own real pixel data, not a manual B/C
// adjustment.
//   SOURCE_INTENSITY_MAX = 0   -> "auto": use THIS image's own actual
//                                  min/max (resetMinAndMax()). Removes the
//                                  dependency on manual B/C, but each image
//                                  is still stretched to its own dynamic
//                                  range, so is not truly identical across
//                                  images with different overall brightness.
//   SOURCE_INTENSITY_MAX > 0  -> use a FIXED absolute scale (0-this value)
//                                  for every image in the batch, e.g. 4095
//                                  for a 12-bit camera or 65535 for true
//                                  16-bit data. This is the more rigorous,
//                                  fully comparable option if you know your
//                                  camera's real bit depth / max ADU count
//                                  -- set it once and use it for the whole
//                                  study.
SOURCE_INTENSITY_MAX = 0;

// --- Soma detection ---
// Soma is detected by thresholding only the TOP brightest pixels.
// SOMA_TOP_PERCENT = what fraction of the brightest pixels to keep (0–100).
// Lower = stricter / smaller soma mask. 12 covers the bright core well;
// raise toward 20 if the soma is still leaking into the skeleton.
SOMA_TOP_PERCENT        = 12;

// Hard floor on the soma threshold intensity (0–255).
// The percentile threshold is clamped to this minimum so dim images
// cannot accidentally qualify faint debris as soma.
// Lower if the real soma is missed; raise if bright junk still gets through.
SOMA_ABS_MIN_INTENSITY  = 150;

// Gaussian blur before soma thresholding — smooths the bright core into one blob.
SOMA_BLUR_RADIUS        = 2;

// Pixels to erode the soma mask inward after detection.
// Set to 0: eroding shrinks the subtracted hole and leaves bright soma-edge
// pixels in the process image, which then get skeletonized as false branches.
// Only increase if process roots are being swallowed by the soma mask.
SOMA_ERODE_PASSES       = 0;

// Pixels to dilate the soma mask outward before process subtraction.
// 2 passes extends the mask just enough to cover the bright soma-edge halo
// that sits between the core and the real process roots, eliminating the
// spurious junction tangle at the soma boundary without swallowing real processes.
// Reduce to 1 or 0 if nearby process roots start disappearing.
SOMA_DILATE_PASSES      = 2;

// Morphology for the MEASURED / SAVED soma ONLY — decoupled from the erode/dilate
// above, which stays dedicated to building the subtraction mask the skeleton needs.
// SOMA_ERODE_PASSES / SOMA_DILATE_PASSES still pad that scratch mask (+2 by default)
// so the bright soma-edge halo is swallowed before skeletonizing; these two instead
// control the soma that is measured (Soma_Area/Circularity/AR/Solidity), saved as
// Soma-Mask.tif, and handed to the brush-editing stage as its starting candidate.
// Kept at 0/0 so the measured soma stays tight to the thresholded bright core
// instead of inheriting the +2 dilate. Raise SOMA_MEASURE_ERODE_PASSES to 1 to go
// tighter still; raise SOMA_MEASURE_DILATE_PASSES if you deliberately want the
// measured soma padded. Only Edit_Finalize.ijm reads these — nothing to pass to
// Skeletonize_And_Detect_Soma.ijm. NOTE: a tighter mask can drop below
// SOMA_MIN_AREA (15) on small somas — lower it to ~8–10 if small somas vanish.
SOMA_MEASURE_ERODE_PASSES  = 0;
SOMA_MEASURE_DILATE_PASSES = 0;

// Minimum soma area (px²).
SOMA_MIN_AREA           = 15;

// Maximum soma area (px²). Set to ~2–3× your typical soma area.
SOMA_MAX_AREA           = 50000;

// Circularity floor for soma — keeps only roundish blobs.
// 0.4 accepts mildly irregular soma while excluding thin process fragments.
// Raise toward 0.6 if bright debris is being mistaken for soma.
SOMA_CIRCULARITY_MIN    = 0.4;

// --- Process skeletonization ---
// Contrast stretch saturation % before thresholding.
// Lower = more aggressive (lifts dim distal tips). 0.05 is very aggressive.
CONTRAST_SATURATE       = 0.05;

// Threshold method for processes.
// "Li" captures thin dim structures well. Try "Otsu" if too much noise appears.
PROCESS_THRESHOLD_METHOD = "Li";

// Fixed threshold value to use instead of auto-threshold.
// Set to 0 to use auto (PROCESS_THRESHOLD_METHOD).
// Lower = more branches captured. Raise if too much background noise appears.
PROCESS_FIXED_THRESHOLD = 32;

// Gaussian blur before thresholding. Keep very low (0–0.5) for small images.
PROCESS_BLUR_SIGMA      = 0;

// 1 despeckle pass removes isolated noise pixels from the low threshold
// without fattening real processes (despeckle only removes fully isolated pixels).
// Set to 0 to skip.
PROCESS_DESPECKLE_PASSES = 1;

// Morphological CLOSE passes (dilate then erode) applied to the process mask
// before skeletonizing. Bridges sub-threshold gaps so a process that dims out
// mid-branch reconnects into ONE piece instead of skeletonizing into fragments,
// and reconnects dim distal tips back to the main arbor. Each pass bridges a gap
// of roughly 2 px; the matching erode restores process thickness afterward, so
// this changes connectivity, not width.
//   0 = off (original behaviour).
//   1 = recommended. Raise to 2 only if branches still break at obvious gaps —
//       higher risks fusing two processes that run close together, or shifting
//       junctions. This is the knob that fixes "doesn't pick up complete branches".
PROCESS_CLOSE_PASSES = 1;

// Remove disconnected mask blobs smaller than this many px² BEFORE skeletonizing.
// Because the close above runs first, real processes are joined to the arbor and
// survive as one big component; what remains below this floor is isolated
// background speckle that would otherwise skeletonize into its own component and
// inflate Num_Branches / Num_Junctions / Num_Endpoints (the final stats sum across
// ALL components). This is what lets you safely LOWER PROCESS_FIXED_THRESHOLD to
// grab dim processes — the low threshold's background pickup is cleaned up here.
//   0 = off (keep every blob, original behaviour).
//   20 = recommended gentle default: kills speckle, keeps genuine fragments.
//   Raise toward 40–60 if background still leaks; lower if real short fragments
//   are disappearing. For an even stricter clean, see KEEP_LARGEST_COMPONENT below.
PROCESS_MIN_PARTICLE_SIZE = 20;

// Stricter alternative to the size floor: after cleaning, keep ONLY the single
// largest connected component (the main arbor) and discard everything else,
// regardless of size. Guarantees zero background pickup, but will drop any
// genuinely detached distal fragment whose gap the close didn't bridge — use the
// Stage-1 skeleton brush to hand-add those back. Leave false unless background is
// still a problem after tuning PROCESS_MIN_PARTICLE_SIZE.
//   false = size-floor cleaning only (recommended).
//   true  = keep largest component only (strictest).
KEEP_LARGEST_COMPONENT = false;

// --- Spur pruning ---
// Terminal spurs (free endpoint -> nearest junction) shorter than this are
// physically erased from the skeleton pixels by pruneShortSpurs(), BEFORE
// Analyze Skeleton ever measures it — not filtered out of the stats afterward.
// Junction pixels are identified by actual pixel connectivity, never by
// coordinate distance, and are never erased themselves, so two genuinely
// close junctions are never merged or confused. Because pruning happens
// before measurement, Num_Branches/Num_Junctions/Num_Endpoints/Num_Triple/
// Num_Quadruple_Points and every Detailed branch row all come from one
// consistent reading of the same pruned skeleton — no separate bookkeeping.
// Set to 0 to disable pruning (keep every branch, however short).
// 5 µm is a reasonable default for microglia; raise to 8–10 if stubs persist.
MIN_BRANCH_LENGTH_UM = 5.0;

// --- Scale bar ---
// SCALEBAR_HEIGHT controls both the bar thickness and the "height=" parameter
// in the Scale Bar command (they are kept equal intentionally so the rendered
// bar matches the specified thickness on all Fiji versions).
SCALEBAR_WIDTH_UM  = 10;   // length of scale bar in microns
SCALEBAR_HEIGHT    = 4;    // bar thickness in pixels (also passed as height=)
SCALEBAR_FONT      = 14;   // label font size
SCALEBAR_COLOR     = "White";
SCALEBAR_LOCATION  = "Lower Right";

// ── End of Tunable Parameters ─────────────────────────────────────────────────

// ── Helper Functions ──────────────────────────────────────────────────────────

// Draws the standard scale bar using the SCALEBAR_* settings above.
// Centralised here so all 5 call sites below stay in sync.
function addScaleBar() {
    run("Scale Bar...",
        "width=" + SCALEBAR_WIDTH_UM +
        " height=" + SCALEBAR_HEIGHT +
        " thickness=" + SCALEBAR_HEIGHT +
        " font=" + SCALEBAR_FONT +
        " color=" + SCALEBAR_COLOR +
        " background=None location=[" + SCALEBAR_LOCATION + "] bold overlay");
}

// Each cell's images live in their own subfolder (e.g. <BaseName>-1/), one
// level below the main "<BaseName>-Images" folder. Given the path to a cell
// subfolder, this returns the path to its parent (the main image folder),
// which is where the combined Excel file for all cells is written.
function getParentDir(dirPath) {
    trimmed = dirPath;
    if (endsWith(trimmed, "/") || endsWith(trimmed, "\\")) {
        trimmed = substring(trimmed, 0, lengthOf(trimmed) - 1);
    }
    return File.getParent(trimmed) + File.separator;
}

// Converts the current image to 8-bit in a way that is independent of any
// manual Brightness/Contrast adjustment left on screen (see the
// SOURCE_INTENSITY_MAX comment in the Tunable Parameters block for why this
// matters). No-op for images that are already 8-bit.
function normalizeTo8Bit() {
    if (bitDepth() == 16 || bitDepth() == 32) {
        if (SOURCE_INTENSITY_MAX > 0) {
            setMinAndMax(0, SOURCE_INTENSITY_MAX);
        } else {
            resetMinAndMax();
        }
    }
    setOption("ScaleConversions", true);
    run("8-bit");
}

// Duplicates the microglia channel from windowName as an 8-bit grayscale
// image, renamed to newName. Falls back to a plain duplicate when the source
// image isn't multi-channel. Signature matches Skeletonize_And_Detect_Soma.ijm
// so both files use MICROGLIA_CHANNEL the same way and can be compared directly.
function duplicateMicrogliaChannel(windowName, newName) {
    selectWindow(windowName);
    Stack.getDimensions(dmc_w, dmc_h, dmc_c, dmc_s, dmc_f);
    if (dmc_c > 1) {
        Stack.setChannel(MICROGLIA_CHANNEL);
        run("Duplicate...", "duplicate channels=" + MICROGLIA_CHANNEL);
    } else {
        run("Duplicate...", " ");
    }
    normalizeTo8Bit();
    rename(newName);
}

// Soma correction uses the same Space/Shift brush-editing pattern as
// skeleton editing, rather than a separate confirm/correct dialog flow.
// Builds a 2-channel Composite: channel 1 (red) = soma mask, channel
// 2 (green) = cell -- exactly the skeleton-editing convention, just with a
// mask instead of a skeleton on channel 1. White brush = add to soma, black
// brush = erase, same foreground-color convention as skeleton editing.
// These three helpers are used together from the main Finalize loop below:
//   rebuildSomaComposite()     -- (re)build the Composite from "soma_final"
//   syncSomaMaskFromComposite() -- pull channel 1 back out into "soma_final"
//   reportSomaStats()          -- measure "soma_final" and print live stats
//
// "soma_final" only exists transiently between a sync and the next rebuild
// (rebuildSomaComposite consumes/closes it) - it's left open, holding the
// accepted mask, right after the soma-editing loop's final sync on Shift.

// (Re)builds the "Composite" window from the current "soma_final" mask and
// the cell image, and activates channel 1 for editing - same zoom-
// preserving, channel-activating behaviour as runSkeletonizeAndPreparePreview().
function rebuildSomaComposite(cellImageName) {
    zoom = getZoom() * 100;
    duplicateMicrogliaChannel(cellImageName, "soma_edit_cell");
    selectWindow("soma_final");
    run("Duplicate...", " ");
    rename("soma_edit_mask");
    close("soma_final"); // consumed into the composite; syncSomaMaskFromComposite()
                          // recreates it fresh from the composite each time it's needed
    if (isOpen("Composite")) { close("Composite"); }
    run("Merge Channels...", "c1=[soma_edit_mask] c2=[soma_edit_cell] create keep");
    close("soma_edit_mask");
    close("soma_edit_cell");
    if (isOpen("Composite")) {
        selectWindow("Composite");
        run("Set... ", "zoom=" + zoom + " x=0 y=0");
    }
    activateCompositeChannel1();
}

// Pulls channel 1 (the soma mask, with whatever brush edits were made) back
// out of the Composite into a freshly (re)named "soma_final" window, and
// binarizes it - brush strokes can leave anti-aliased edges, so anything
// >=128 is treated as soma. Reuses extractChannel1From() so this stays in
// sync with exactly how skeleton editing pulls channel 1 out of Composite.
function syncSomaMaskFromComposite() {
    extractChannel1From("Composite"); // selects the duplicated 8-bit channel-1 image, unrenamed
    rename("soma_final");
    setThreshold(128, 255);
    setOption("BlackBackground", true);
    run("Convert to Mask");
}

// Measures the current "soma_final" mask and prints live stats to the Log,
// so the user can see Area/Circ/AR/Solidity update as they paint, the same
// way skeleton editing's Space key lets you see branch/junction changes.
function reportSomaStats() {
    selectWindow("soma_final");
    run("Select None");
    setThreshold(255, 255);
    run("Create Selection");
    resetThreshold();
    if (selectionType() != -1) {
        run("Set Measurements...", "area shape fit redirect=None decimal=4");
        run("Measure");
        rssRow = nResults - 1;
        print("  Soma (live): Area=" + d2s(getResult("Area", rssRow), 2) +
              "  Circ=" + d2s(getResult("Circ.", rssRow), 3) +
              "  AR=" + d2s(getResult("AR", rssRow), 3) +
              "  Solidity=" + d2s(getResult("Solidity", rssRow), 3));
        close("Results");
        run("Select None");
    } else {
        print("  Soma (live): empty (no region currently marked).");
    }
}

// Duplicates channel 1 (the skeleton channel) out of the named composite
// window as 8-bit grayscale, leaving the result selected and un-renamed —
// callers finish with their own Skeletonize/Multiply/rename steps. Used by
// both the live preview and the final skeleton extraction.
function extractChannel1From(windowName) {
    selectWindow(windowName);
    Stack.setChannel(1);
    run("Duplicate...", "duplicate channels=1");
    setOption("ScaleConversions", true);
    run("8-bit");
    run("Grays");
}

// If the Composite window is open, brings it to front with channel 1
// active — the channel the brush-editing instructions assume is selected.
function activateCompositeChannel1() {
    if (isOpen("Composite")) {
        selectWindow("Composite");
        Stack.setChannel(1);
    }
}

// Closes every open image window. Used between cells, and at the very end
// of the batch, so leftover windows from one cell never bleed into the next.
function closeAllImages() {
    while (nImages > 0) {
        selectImage(nImages);
        close();
    }
}

// The pipeline uses the ROI Manager internally (soma blob detection below,
// and again inside Skeletonize_And_Detect_Soma.ijm) but the user never needs
// to see or touch it. There's no macro command to hide it directly, so this
// creates it if needed and then hides the window via a one-line Java call -
// roiManager("reset"/"add"/"select"/"count") all keep working normally on
// the hidden instance afterward. Safe to call repeatedly / from either macro.
function hideRoiManager() {
    if (!isOpen("ROI Manager")) {
        run("ROI Manager...");
    }
    eval("script",
        "importClass(Packages.ij.plugin.frame.RoiManager);" +
        "rm = RoiManager.getInstance();" +
        "if (rm != null) rm.setVisible(false);");
}

// Runs the skeletonization pipeline (produces the Skeleton + Composite
// windows), closes the standalone Skeleton window since editing happens on
// Composite instead, warns if Composite didn't appear, and activates
// Composite on channel 1 so it's ready for editing. Used both for the first
// image opened before pressing F2, and for each subsequent "next image"
// advance inside the Finalize loop.
//
// Parameters are passed to Skeletonize_And_Detect_Soma.ijm by writing a small
// key=value config file to the system temp directory before calling run().
// Skeletonize reads that file on startup. This is the standard IJ macro
// mechanism for passing data between macros launched with run() — there is no
// shared variable scope between them.
function runSkeletonizeAndPreparePreview() {
    // Write all tunable parameters to a temp config file.
    // Skeletonize_And_Detect_Soma.ijm reads this file at startup so there is
    // only one copy of every default — here in Edit_Finalize.ijm.
    cfgPath = getDirectory("temp") + "SkeleSoma_params.txt";
    f = File.open(cfgPath);
    print(f, "MICROGLIA_CHANNEL="         + MICROGLIA_CHANNEL);
    print(f, "SOURCE_INTENSITY_MAX="      + SOURCE_INTENSITY_MAX);
    print(f, "SOMA_TOP_PERCENT="          + SOMA_TOP_PERCENT);
    print(f, "SOMA_ABS_MIN_INTENSITY="    + SOMA_ABS_MIN_INTENSITY);
    print(f, "SOMA_BLUR_RADIUS="          + SOMA_BLUR_RADIUS);
    print(f, "SOMA_ERODE_PASSES="         + SOMA_ERODE_PASSES);
    print(f, "SOMA_DILATE_PASSES="        + SOMA_DILATE_PASSES);
    print(f, "SOMA_MIN_AREA="             + SOMA_MIN_AREA);
    print(f, "SOMA_MAX_AREA="             + SOMA_MAX_AREA);
    print(f, "SOMA_CIRCULARITY_MIN="      + SOMA_CIRCULARITY_MIN);
    print(f, "CONTRAST_SATURATE="        + CONTRAST_SATURATE);
    print(f, "PROCESS_THRESHOLD_METHOD=" + PROCESS_THRESHOLD_METHOD);
    print(f, "PROCESS_FIXED_THRESHOLD="  + PROCESS_FIXED_THRESHOLD);
    print(f, "PROCESS_BLUR_SIGMA="       + PROCESS_BLUR_SIGMA);
    print(f, "PROCESS_DESPECKLE_PASSES=" + PROCESS_DESPECKLE_PASSES);
    print(f, "PROCESS_CLOSE_PASSES="     + PROCESS_CLOSE_PASSES);
    print(f, "PROCESS_MIN_PARTICLE_SIZE=" + PROCESS_MIN_PARTICLE_SIZE);
    print(f, "KEEP_LARGEST_COMPONENT="   + KEEP_LARGEST_COMPONENT);
    File.close(f);

    run("Skeletonize And Detect Soma");

    if (isOpen("Skeleton")) {
        selectWindow("Skeleton");
        close();
    }

    if (!isOpen("Composite")) {
        print("WARNING: Composite did not open — check that the skeleton was produced.");
    }

    activateCompositeChannel1();
}

// Counts white (>0) 8-connected neighbours of (x,y) in the current image.
// Used by pruneShortSpurs() to identify endpoints (degree 1) and junctions
// (degree >=3) directly from pixel connectivity — never from coordinate
// distance — so two close junctions can never be confused for one.
function neighborCount8(x, y, w, h) {
    n = 0;
    for (dy = -1; dy <= 1; dy++) {
        for (dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            nx = x + dx;
            ny = y + dy;
            if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                if (getPixel(nx, ny) > 0) { n++; }
            }
        }
    }
    return n;
}

// Physically erases short terminal spurs from a binary skeleton image
// before Analyze Skeleton ever measures it. This is what makes Num_Junctions / Num_Triple_Points /
// Num_Quadruple_Points / Num_Endpoints consistent with Num_Branches and the
// Detailed branch rows: every one of those numbers ends up coming from one
// measurement of the same already-pruned image, rather than a raw skeleton
// measurement patched up afterward to pretend some branches don't exist.
//
// How it works:
//   1. Find every endpoint (a white pixel with exactly one white 8-neighbour)
//      in the image before any erasing — this snapshot means erasing one
//      spur can never change how another spur's trace is read.
//   2. From each endpoint, walk the 1-pixel-wide skeleton path inward,
//      summing true geometric distance (1 per orthogonal step, sqrt(2) per
//      diagonal step) until reaching a pixel with 3+ white 8-neighbours —
//      an actual junction pixel, identified purely by its own connectivity.
//   3. If that path's total length is under thresholdUm, erase every pixel
//      walked except the junction pixel itself. The junction pixel is never
//      touched directly — if removing its spurs drops its remaining degree
//      below 3, the next Analyze Skeleton run will correctly stop counting
//      it as a junction on its own, with no special-casing needed here.
//   4. A spur that runs from one endpoint to another endpoint with no
//      junction in between (an isolated short fragment) is left alone —
//      that's a different situation from "stub off a junction" and is
//      riskier to delete automatically.
//   5. Afterward, any pixel left with zero remaining neighbours (e.g. a
//      3-way junction that lost all three of its spokes in the same pass)
//      is cleaned up too, so it doesn't show up as a meaningless 1-pixel
//      "component" in the next measurement.
//
// Returns the number of spurs erased, for logging.
function pruneShortSpurs(thresholdUm, pxToUm) {
    if (thresholdUm <= 0) { return 0; }

    w = getWidth();
    h = getHeight();

    // Collect all endpoint pixels (white pixel with exactly one white 8-neighbour)
    // into a snapshot array BEFORE any erasing begins.
    // maxPts caps the array size. If a skeleton somehow has more endpoints than
    // this (very dense image), the surplus are silently skipped — the log warning
    // below makes this visible so it can be investigated.
    maxPts = 4000;
    endX   = newArray(maxPts);
    endY   = newArray(maxPts);
    nEnd   = 0;
    nEndSkipped = 0;
    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            if (getPixel(x, y) > 0 && neighborCount8(x, y, w, h) == 1) {
                if (nEnd < maxPts) {
                    endX[nEnd] = x; endY[nEnd] = y; nEnd++;
                } else {
                    nEndSkipped++;
                }
            }
        }
    }
    if (nEndSkipped > 0) {
        print("WARNING: pruneShortSpurs hit the " + maxPts + "-endpoint cap; " +
              nEndSkipped + " endpoint(s) skipped. Raise maxPts in pruneShortSpurs " +
              "if this image has an unusually dense skeleton.");
    }

    maxPathPx    = 2000;
    spursRemoved = 0;

    for (i = 0; i < nEnd; i++) {
        sx = endX[i]; sy = endY[i];
        // Guard: already erased as part of an earlier spur sharing this pixel.
        if (getPixel(sx, sy) == 0) { continue; }

        pathX = newArray(maxPathPx);
        pathY = newArray(maxPathPx);
        pathX[0] = sx; pathY[0] = sy;
        pathLen  = 1;

        cx = sx; cy = sy; px = -1; py = -1;
        pathDistPx      = 0;
        reachedJunction  = false;
        deadEnd          = false;

        while (pathLen < maxPathPx) {
            // Collect all white 8-neighbours (up to 8) excluding the pixel
            // we just came from. We must gather them all before deciding
            // anything so that a pixel at a junction (degree >= 3) is never
            // mistakenly treated as a passable straight-path pixel just
            // because we happened to stop collecting at 2.
            nbX = newArray(8); nbY = newArray(8); nNb = 0;
            for (dy = -1; dy <= 1; dy++) {
                for (dx = -1; dx <= 1; dx++) {
                    if (dx == 0 && dy == 0) { continue; }
                    nx = cx + dx; ny = cy + dy;
                    if (nx == px && ny == py) { continue; }
                    if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                        if (getPixel(nx, ny) > 0) {
                            nbX[nNb] = nx; nbY[nNb] = ny; nNb++;
                        }
                    }
                }
            }

            if (nNb == 0) { deadEnd = true; break; }

            // If this step lands on a junction, stop — never erase the junction.
            nx = nbX[0]; ny = nbY[0];
            stepDist = sqrt((nx - cx) * (nx - cx) + (ny - cy) * (ny - cy));
            px = cx; py = cy; cx = nx; cy = ny;
            pathDistPx += stepDist;

            if (neighborCount8(cx, cy, w, h) >= 3) {
                reachedJunction = true;
                break; // junction pixel itself is never added to the erasure path
            }
            pathX[pathLen] = cx; pathY[pathLen] = cy; pathLen++;
        }

        if (reachedJunction && (pathDistPx * pxToUm) < thresholdUm) {
            for (k = 0; k < pathLen; k++) {
                setPixel(pathX[k], pathY[k], 0);
            }
            spursRemoved++;
        }
        // deadEnd spurs (endpoint-to-endpoint, no junction) are left untouched.
    }

    // Remove any pixel left with zero remaining neighbours (e.g. a 3-way
    // junction whose every spoke was pruned in the same pass).
    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            if (getPixel(x, y) > 0 && neighborCount8(x, y, w, h) == 0) {
                setPixel(x, y, 0);
            }
        }
    }

    updateDisplay();
    return spursRemoved;
}

// The Summary/Detailed sheets use ONE set of column headers per batch
// (Soma_Area_um2 vs Soma_Area_px2, etc.), and even when two calibrated cells
// both say "um2" the actual um-per-pixel scale must match or the numbers
// aren't comparable. Without a check, a batch that drifts between
// calibrated/uncalibrated cells - or between two different um/px scales,
// e.g. from an accidental objective/zoom change -- would silently corrupt
// or misrepresent data already written to the same sheet.
//
// This locks calibration the first time any cell in a given mainDir (batch)
// is finalized, by writing a small marker file, and checks every later cell
// -- including in a resumed session on a different day - against it.
// Exits with an actionable message on mismatch instead of writing bad data.
function checkAndLockCalibration(mainDirPath, isCalibrated, umPerPixel) {
    markerPath = mainDirPath + ".calibration.txt";

    if (!File.exists(markerPath)) {
        f = File.open(markerPath);
        if (isCalibrated) {
            print(f, "calibrated=1");
            print(f, "px2um=" + umPerPixel);
        } else {
            print(f, "calibrated=0");
        }
        File.close(f);
        return;
    }

    lockedCalibrated = false;
    lockedPx2um      = 0;
    cclLines = split(File.openAsString(markerPath), "\n");
    for (cli = 0; cli < cclLines.length; cli++) {
        cclLine = replace(cclLines[cli], "\r", "");
        if (startsWith(cclLine, "calibrated=1")) { lockedCalibrated = true; }
        if (startsWith(cclLine, "px2um="))       { lockedPx2um = parseFloat(substring(cclLine, 6)); }
    }

    if (lockedCalibrated != isCalibrated) {
        // ImageJ macro has no ?: ternary operator -- build these labels
        // with plain if/else instead.
        lockedLabel = "UNCALIBRATED (px)";
        if (lockedCalibrated) { lockedLabel = "CALIBRATED (µm)"; }
        thisLabel = "UNCALIBRATED (px).";
        if (isCalibrated) { thisLabel = "CALIBRATED (µm)."; }

        exit("Calibration mismatch for this batch:\n  " + mainDirPath + "\n \n" +
             "The first cell finalized in this batch was " + lockedLabel +
             ",\nbut this cell is " + thisLabel + "\n \n" +
             "Mixing calibrated and uncalibrated cells in the same batch would\n" +
             "corrupt the Summary/Detailed Excel columns (they'd disagree on\n" +
             "whether values are _um2 or _px2). Fix this cell's calibration in\n" +
             "Image > Properties to match the rest of the batch (or start a new\n" +
             "output folder for it), then press F2 again.");
    }

    if (lockedCalibrated && lockedPx2um > 0 && isCalibrated) {
        pctDiff = abs(umPerPixel - lockedPx2um) / lockedPx2um * 100;
        if (pctDiff > 0.5) {
            exit("Calibration mismatch for this batch:\n  " + mainDirPath + "\n \n" +
                 "The rest of this batch is calibrated at " + lockedPx2um + " \u00b5m/px,\n" +
                 "but this cell is calibrated at " + umPerPixel + " \u00b5m/px (" +
                 d2s(pctDiff, 1) + "% different).\n \n" +
                 "This usually means the image was captured at a different\n" +
                 "objective/zoom. Writing it into the same sheet would silently\n" +
                 "mix two different physical scales under the same 'um' column.\n \n" +
                 "Double-check Image > Properties for this cell. If the different\n" +
                 "scale is intentional, use a separate output folder for it instead\n" +
                 "of continuing this batch, then press F2 again.");
        }
    }
}

// The "Read and Write Excel" plugin has no macro-callable way to
// find-and-overwrite a specific existing row, so redoing a cell (bad edit,
// wrong parameters, etc.) and pressing Shift again would otherwise just
// append a second row for the same Cell_ID with no warning. 
// These two functions track which Cell_IDs
// have already been written for this batch in a small marker file (works
// across sessions/days too, unlike an in-memory list), so we can warn and
// let the user cancel before writing a duplicate. See the confirmation
// dialog at the top of the "Write Summary sheet" step below.
function cellAlreadyRecorded(mainDirPath, cellID) {
    markerPath = mainDirPath + ".finalized_cells.txt";
    if (!File.exists(markerPath)) { return false; }
    carLines = split(File.openAsString(markerPath), "\n");
    for (cri = 0; cri < carLines.length; cri++) {
        carLine = String.trim(replace(carLines[cri], "\r", ""));
        if (carLine == "" + cellID) { return true; }
    }
    return false;
}

function markCellRecorded(mainDirPath, cellID) {
    if (cellAlreadyRecorded(mainDirPath, cellID)) { return; }
    markerPath = mainDirPath + ".finalized_cells.txt";
    existingIDs = newArray(0);
    if (File.exists(markerPath)) {
        mcrLines = split(File.openAsString(markerPath), "\n");
        for (mci = 0; mci < mcrLines.length; mci++) {
            t = String.trim(replace(mcrLines[mci], "\r", ""));
            if (t != "") { existingIDs = Array.concat(existingIDs, t); }
        }
    }
    f = File.open(markerPath);
    for (mci = 0; mci < existingIDs.length; mci++) {
        print(f, existingIDs[mci]);
    }
    print(f, "" + cellID);
    File.close(f);
}

// Parses a cell-crop image title of the form "<BaseName>-<N>" (as produced by
// Capture_Images.ijm) and returns it packed as "<BaseName>||<N>". Exits with a
// clear, actionable message instead of a cryptic macro error if the title
// doesn't match that pattern -- e.g. the file was renamed by hand, or was
// never produced by Capture_Images.ijm in the first place.
//
// The split point is always the last "-" in the title: the cell number is
// appended last by Capture_Images, so this is safe even when BaseName itself
// legitimately contains dashes (e.g. "2024-06-12_Mouse-1-CY5-3" splits into
// BaseName "2024-06-12_Mouse-1-CY5", cell #3).
//
// NOTE: this returns a packed string rather than setting baseName/picNum
// directly. Per the comment above the calibration block, variables assigned
// inside an IJ macro function are local and do not escape to the caller --
// so the caller unpacks the two values itself (see usage below).
function parseCellFilename(name) {
    pcf_indicator = name.lastIndexOf("-");
    if (pcf_indicator < 0) {
        exit("Can't find a cell number in image title: \"" + name + "\"\n \n" +
             "Edit_Finalize.ijm (F2) expects filenames produced by Capture_Images.ijm\n" +
             "(F1): <BaseName>-<N>.tif  e.g. \"Mouse1-3.tif\" for cell #3.\n \n" +
             "If this file was renamed by hand, restore a trailing \"-<number>\"\n" +
             "immediately before the file extension, then try again.");
    }

    pcf_base = name.substring(0, pcf_indicator);
    pcf_base = pcf_base.trim();

    pcf_numStr = name.substring(pcf_indicator + 1, name.length());
    pcf_num    = parseInt(pcf_numStr);

    if (isNaN(pcf_num)) {
        exit("Can't read a cell number from image title: \"" + name + "\"\n \n" +
             "Expected a plain integer after the last \"-\" (e.g. \"...-3\" for\n" +
             "cell #3), but found: \"" + pcf_numStr + "\"\n \n" +
             "Edit_Finalize.ijm (F2) expects filenames produced by Capture_Images.ijm\n" +
             "(F1). If this file was renamed by hand, make sure it ends in\n" +
             "\"-<number>\" with nothing else after the number.");
    }

    return pcf_base + "||" + pcf_num;
}

// ── Initialise ────────────────────────────────────────────────────────────────

// Keep the ROI Manager out of the way for the whole session - it's still
// used internally (soma blob detection), just never shown as a window.
hideRoiManager();

officialName = getTitle();
dotIdx = officialName.lastIndexOf(".");
if (dotIdx > 0) { officialName = officialName.substring(0, dotIdx); }
rename(officialName);

// The opened cell image lives inside its own subfolder; mainDir is the main
// "<BaseName>-Images" folder one level up, where the combined Excel goes.
// All cells from this batch share the same mainDir, so this is computed once.
mainDir = getParentDir(File.directory);
print("Main image folder: " + mainDir);

// ── Read pixel calibration from the source image ──────────────────────────────
// IJ macro variables set inside functions are local and don't escape to the
// caller's scope, so calibration is read inline at both sites rather than
// via a helper function.
getVoxelSize(pixW, pixH, pixD, pixUnit);
if (pixUnit == "microns" || pixUnit == "µm" || pixUnit == "um") {
    calibrated = true;
    px2um      = pixW;          // µm per pixel (linear)
    px2um2     = pixW * pixH;   // µm² per pixel² (area)
    unitLabel  = "um";
    print("Calibration: " + pixW + " µm/px  (area factor: " + px2um2 + " µm²/px²)");
} else {
    calibrated = false;
    px2um      = 1;
    px2um2     = 1;
    unitLabel  = "px";
    print("WARNING: No µm calibration found — measurements will be in pixels.");
    showMessage("WARNING: No pixel calibration found!\n \n" +
        "All measurements will be recorded in pixels, not microns.\n \n" +
        "To fix before continuing:\n" +
        "  1. Close this dialog\n" +
        "  2. Go to Image > Properties\n" +
        "  3. Set Pixel Width, Pixel Height, and Unit to 'microns'\n" +
        "  4. Press F2 again\n \n" +
        "Click OK to continue anyway (pixel units will be used).");
}

// ── Robust filename parsing for VSI-style names with multiple dashes ──────────
parsed   = parseCellFilename(officialName);
splitIdx = parsed.lastIndexOf("||");
baseName = parsed.substring(0, splitIdx);
picNum   = parseInt(parsed.substring(splitIdx + 2, parsed.length()));

print("Base name: [" + baseName + "]  Cell #: " + picNum);

// Lock/verify this batch's calibration (see checkAndLockCalibration above).
checkAndLockCalibration(mainDir, calibrated, px2um);

// Run skeletonization pipeline — produces: Skeleton, Composite. Closes the
// standalone Skeleton window (editing is done on Composite), warns if
// Composite didn't appear, and activates Composite on channel 1 for editing.
runSkeletonizeAndPreparePreview();

// ── Instructions ──────────────────────────────────────────────────────────────

print("========================================");
print("Image: " + officialName);
print("Edit on the COMPOSITE window (red = skeleton).");
print("  Channel 1 must be active (bottom slider).");
print("  WHITE brush = draw | BLACK brush = erase");
print("----------------------------------------");
print("  Space  → re-skeletonize and refresh preview");
print("  Shift  → collect data and continue");
print("  (Close Excel before pressing Shift!)");
print("========================================");

editing = true;

// ── Edit / Preview / Finalize Loop ───────────────────────────────────────────

while (editing) {
    previewMacro  = isKeyDown("space");
    finishedMacro = isKeyDown("shift");

    // ── PREVIEW ───────────────────────────────────────────────────────────────
    if (previewMacro) {
        setKeyDown("none");
        zoom = getZoom() * 100;

        extractChannel1From("Composite");
        run("Skeletonize (2D/3D)");
        rename("Skeleton_edit");

        numSpursRemoved_preview = pruneShortSpurs(MIN_BRANCH_LENGTH_UM, px2um);
        if (numSpursRemoved_preview > 0) {
            print("Preview: " + numSpursRemoved_preview + " short spur(s) pruned (< " + MIN_BRANCH_LENGTH_UM + " " + unitLabel + ").");
        }

        run("Analyze Skeleton (2D/3D)", "prune=none");
        if (isOpen("Results")) { close("Results"); }
        if (isOpen("Branch information")) { close("Branch information"); }

        if (isOpen("Tagged skeleton")) {
            duplicateMicrogliaChannel(officialName, "preview_source");
            run("Grays");

            close("Composite");
            close("Skeleton_edit");
            run("Merge Channels...",
                "c1=[Tagged skeleton] c2=[preview_source] create keep");
            close("Tagged skeleton");
            close("preview_source");

            activateCompositeChannel1();
            run("Set... ", "zoom=" + zoom + " x=0 y=0");
        } else {
            close("Skeleton_edit");
        }
        wait(400);
    }

    // ── FINALIZE ──────────────────────────────────────────────────────────────
    if (finishedMacro) {
        setKeyDown("none");
        // Debounce: give the physical Shift key time to release before the
        // soma-editing stage starts its own isKeyDown polling below --
        // without a pause here, a key held slightly too long could get
        // read as an immediate "accept soma" before you ever see it.
        wait(400);

        zoom = getZoom() * 100;

        // ── Extract final skeleton from Composite channel 1 ───────────────────
        extractChannel1From("Composite");
        run("Multiply...", "value=255");
        run("Skeletonize (2D/3D)");
        rename(officialName + "(Skeleton)");

        // ── Save Composite with scale bar ─────────────────────────────────────
        if (isOpen("Composite")) {
            selectWindow("Composite");
            // Flatten to RGB so scale bar bakes in visibly across both channels
            run("Flatten");
            rename("Composite_flat");
            addScaleBar();
            saveAs("Tiff", File.directory + officialName + "(Composite).tif");
            close();
            close("Composite");
        }

        // ── Soma re-measurement ────────────────────────────────────────────────
        duplicateMicrogliaChannel(officialName, "soma_final");

        run("Gaussian Blur...", "sigma=" + SOMA_BLUR_RADIUS);

        getStatistics(sf_area, sf_mean, sf_min, sf_max, sf_std, sf_hist);
        sf_targetPx   = sf_area * (SOMA_TOP_PERCENT / 100.0);
        sf_cumulative = 0;
        sf_threshLow  = sf_max;
        sf_i = 255;
        while (sf_i >= 0 && sf_cumulative < sf_targetPx) {
            sf_cumulative += sf_hist[sf_i];
            if (sf_cumulative >= sf_targetPx) { sf_threshLow = sf_i; }
            sf_i--;
        }
        // Clamp: never let the threshold drop below the absolute minimum.
        if (sf_threshLow < SOMA_ABS_MIN_INTENSITY) {
            print("Soma threshold clamped: percentile gave " + sf_threshLow +
                  ", raised to SOMA_ABS_MIN_INTENSITY=" + SOMA_ABS_MIN_INTENSITY);
            sf_threshLow = SOMA_ABS_MIN_INTENSITY;
        }
        setThreshold(sf_threshLow, 255);
        setOption("BlackBackground", true);
        run("Convert to Mask");
        run("Fill Holes");
        // Measured/saved soma uses its OWN morphology (default 0/0) so it stays
        // tight to the thresholded core, independent of the +2 dilate that the
        // skeleton's subtraction mask still gets in Skeletonize_And_Detect_Soma.ijm.
        for (e = 0; e < SOMA_MEASURE_ERODE_PASSES;  e++) { run("Erode");  }
        for (d = 0; d < SOMA_MEASURE_DILATE_PASSES; d++) { run("Dilate"); }

        // ── Reduce the raw threshold mask to a single automatic candidate ─────
        // (largest qualifying blob) -- this is only the starting point for the
        // brush-editing loop below.
        run("Set Measurements...", "area shape fit redirect=None decimal=4");
        roiManager("reset");
        run("Analyze Particles...",
            "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
            " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 add exclude clear");
        if (isOpen("Results")) { close("Results"); }

        candidateBestRow  = -1;
        candidateBestArea = 0;
        for (cr = 0; cr < roiManager("count"); cr++) {
            roiManager("select", cr);
            getStatistics(crArea);
            if (crArea > candidateBestArea) { candidateBestArea = crArea; candidateBestRow = cr; }
        }
        run("Select All");
        setForegroundColor(0, 0, 0);
        fill();
        run("Select None");
        if (candidateBestRow >= 0) {
            roiManager("select", candidateBestRow);
            setForegroundColor(255, 255, 255);
            fill();
            run("Select None");
            if (roiManager("count") > 1) {
                print("Soma (finalize): " + roiManager("count") + " qualifying blob(s) found automatically" +
                      " — largest (" + d2s(candidateBestArea, 1) + " px²) kept as the starting candidate.");
            }
        } else {
            print("Soma (finalize): automatic detection found no qualifying blob -- paint one with the white brush, or press Shift to accept an empty soma.");
        }
        roiManager("reset");

        // ── Interactive soma editing: same Space/Shift brush pattern as ───────
        // skeleton editing above, just applied to the soma mask instead of
        // the skeleton. See rebuildSomaComposite() / syncSomaMaskFromComposite()
        // / reportSomaStats() near the top of the file.
        rebuildSomaComposite(officialName);

        print("========================================");
        print("Cell " + picNum + ": review/edit the SOMA on the COMPOSITE window (channel 1, red).");
        print("  WHITE brush = add to soma | BLACK brush = erase from soma");
        print("----------------------------------------");
        print("  Space  → sync edits and show live soma stats in the Log");
        print("  Shift  → accept soma and continue");
        print("========================================");

        // Debounce: clear any lingering key state and give it a moment before
        // this stage starts polling, so the Shift press that ended skeleton
        // editing can't also be read as an immediate "accept soma" here.
        setKeyDown("none");
        wait(400);

        somaEditing = true;
        while (somaEditing) {
            somaPreviewMacro = isKeyDown("space");
            somaFinishMacro  = isKeyDown("shift");

            if (somaPreviewMacro) {
                setKeyDown("none");
                syncSomaMaskFromComposite();
                reportSomaStats();
                rebuildSomaComposite(officialName);
                wait(400);
            }

            if (somaFinishMacro) {
                setKeyDown("none");
                syncSomaMaskFromComposite();
                somaEditing = false;
            }
        }
        if (isOpen("Composite")) { close("Composite"); }

        // ── Save soma images (reflect whatever was just accepted) ─────────────
        // (a) Soma-Mask: white soma blob on black background, with scale bar.
        selectWindow("soma_final");
        run("Duplicate...", " ");
        rename("soma_save_mask");
        addScaleBar();
        saveAs("Tiff", File.directory + officialName + "(Soma-Mask).tif");
        close();

        // (b) Soma-Overlay: cell image in green, soma mask in cyan (green+blue),
        //     merged as a two-channel composite then flattened to RGB.
        //     Cyan = soma is visible against both bright and dark cell regions.
        duplicateMicrogliaChannel(officialName, "ov_cell");

        selectWindow("soma_final");
        run("Duplicate...", " ");
        rename("ov_soma");

        // c2 = green (cell), c3 = blue (soma); together they render as cyan soma
        run("Merge Channels...", "c2=[ov_cell] c3=[ov_soma] create");
        // Merged window is named "Composite"
        rename("soma_overlay_composite");
        run("Flatten");   // collapses to RGB
        rename("soma_overlay_flat");
        close("soma_overlay_composite");
        selectWindow("soma_overlay_flat");
        addScaleBar();
        saveAs("Tiff", File.directory + officialName + "(Soma-Overlay).tif");
        // Left open intentionally — visible for QC while editing continues.
        // Closed automatically by closeAllImages() when advancing to next cell.

        // ── Final soma measurement, from the accepted mask ────────────────────
        // One measurement taken directly from whatever soma_final now
        // contains. This replaces the old two-pass "Analyze Particles, then
        // rebuild the mask to match the winning row" logic - that
        // reconciliation only existed to pick one blob out of several
        // automatic candidates, and the brush-editing loop above already
        // guarantees soma_final holds exactly one accepted region (or none).
        selectWindow("soma_final");
        run("Select None");
        setThreshold(255, 255);
        run("Create Selection");
        resetThreshold();
        if (selectionType() != -1) {
            run("Set Measurements...", "area shape fit redirect=None decimal=4");
            run("Measure");
            somaLastRow    = nResults - 1;
            somaArea_raw   = getResult("Area",     somaLastRow);
            somaCirc_raw   = getResult("Circ.",    somaLastRow);
            somaAR_raw     = getResult("AR",       somaLastRow);
            somaSolid_raw  = getResult("Solidity", somaLastRow);
            close("Results");
            run("Select None");
        } else {
            somaArea_raw  = 0;
            somaCirc_raw  = 0;
            somaAR_raw    = 1;
            somaSolid_raw = 1;
            print("Soma (finalize): empty soma accepted — area recorded as 0.");
        }
        close("soma_final");

        // Measure already returns calibrated area when the image is
        // calibrated (column header says µm²), or raw pixel area when it
        // isn't (column header says px²) — no extra conversion needed either way.
        somaArea_um2 = somaArea_raw;
        // Shape descriptors are dimensionless — no unit conversion needed
        somaCirc   = somaCirc_raw;
        somaAR     = somaAR_raw;
        somaSolid  = somaSolid_raw;

        // ── Skeleton analysis ──────────────────────────────────────────────────
        // selectWindow() can intermittently fail to actually hand over the
        // "current image" to the requested window on the very next line --
        // confirmed by diagnostic logging: right after calling
        // selectWindow(officialName + "(Skeleton)"), getTitle() sometimes
        // still reported the just-saved "(Soma-Overlay)" window (a 24-bit
        // RGB image) instead. This is what caused the intermittent "requires
        // 8-bit grayscale" error on the 2nd+ cell - Analyze Skeleton ran
        // against whatever was actually active, not necessarily the skeleton.
        // Verify the selection landed and retry (with a short wait) until it
        // does, instead of trusting a single selectWindow() call.
        skeletonWinTitle = officialName + "(Skeleton)";
        selectWindow(skeletonWinTitle);
        selRetries = 0;
        while (getTitle() != skeletonWinTitle && selRetries < 20) {
            wait(50);
            selectWindow(skeletonWinTitle);
            selRetries++;
        }
        if (getTitle() != skeletonWinTitle) {
            exit("Could not select '" + skeletonWinTitle + "' before Analyze Skeleton " +
                 "after " + selRetries + " retries -- currently active window is '" +
                 getTitle() + "'. Please report this.");
        }

        // Defensive guard: "Analyze Skeleton (2D/3D)" hard-fails on anything
        // that isn't a plain single-channel 8-bit grayscale image. This
        // should already be true by construction (extractChannel1From forces
        // 8-bit/Grays when the skeleton is built above), but the soma stage
        // now runs a lot of additional Composite/Merge Channels work in
        // between here and there - if any of it ever leaves this image in
        // an unexpected state, fail safely by normalizing instead of
        // crashing, and log it so the pattern can be tracked down.
        run("Select None");
        Stack.getDimensions(skelW, skelH, skelC, skelS, skelF);
        if (skelC > 1 || skelS > 1 || skelF > 1) {
            print("WARNING: '" + officialName + "(Skeleton)' was not a plain single image " +
                  "(channels=" + skelC + " slices=" + skelS + " frames=" + skelF +
                  ") right before Analyze Skeleton -- flattening to channel 1, slice 1.");
            Stack.setChannel(1);
            Stack.setSlice(1);
            Stack.setFrame(1);
            run("Duplicate...", "duplicate channels=1 slices=1 frames=1");
            close(officialName + "(Skeleton)");
            rename(officialName + "(Skeleton)");
        }
        if (bitDepth() != 8) {
            print("WARNING: '" + officialName + "(Skeleton)' was " + bitDepth() +
                  "-bit, not 8-bit, right before Analyze Skeleton -- converting.");
            setOption("ScaleConversions", true);
            run("8-bit");
        }
        // Extra guard: dimensions/bit depth can look perfectly fine (channels=1,
        // slices=1, frames=1, 8-bit) while the image is STILL internally flagged
        // as a composite image. Force a true flatten to clear it, just in case.
        if (is("composite")) {
            print("WARNING: '" + officialName + "(Skeleton)' was still flagged as a " +
                  "composite image right before Analyze Skeleton -- forcing a plain flatten.");
            run("RGB Color");
            run("8-bit");
        }
        run("Grays");

        // Final, unconditional step: force a Duplicate right here, regardless
        // of what the checks above found. Converting bit depth/LUT in place
        // (run("8-bit"), run("Grays"), even the RGB-roundtrip trick above)
        // changes this image's PIXELS but does not change its underlying Java
        // object -- if it was ever built as a CompositeImage (which happens
        // anywhere Merge Channels touched it), it can remain a CompositeImage
        // instance no matter what its reported bitDepth/dimensions/LUT say.
        // ImageJ's plugin runner checks that object identity directly and
        // rejects it with this exact "requires 8-bit grayscale" error even
        // though every macro-visible property (bitDepth(), is("binary"),
        // is("grayscale"), is("composite")) can report back looking
        // perfectly valid. Duplicate... on a single 2D image always
        // constructs a brand-new, genuinely plain ImagePlus, which sidesteps
        // this regardless of what the source object's history was.
        run("Select None");
        run("Duplicate...", " ");
        close(skeletonWinTitle);
        rename(skeletonWinTitle);
        run("Grays");

        numSpursRemoved = pruneShortSpurs(MIN_BRANCH_LENGTH_UM, px2um);
        if (numSpursRemoved > 0) {
            print("Spur pruning (" + MIN_BRANCH_LENGTH_UM + " " + unitLabel + " threshold): " +
                  numSpursRemoved + " short terminal spur(s) erased before measurement.");
        }

        run("Analyze Skeleton (2D/3D)", "prune=none show");

        // ── Save Tagged skeleton with scale bar ───────────────────────────────
        if (isOpen("Tagged skeleton")) {
            selectWindow("Tagged skeleton");
            addScaleBar();
            saveAs("Tiff", File.directory + officialName + "(Tagged-Skeleton).tif");
            close();
        }

        if (isOpen("Tagged Skeleton"))        { close("Tagged Skeleton"); }
        if (isOpen("Longest shortest paths")) { close("Longest shortest paths"); }

        // ── Aggregate summary stats from Results table (per skeleton component) ─
        numBranches  = 0;
        numJunctions = 0;
        numEndpoints = 0;
        numTriple    = 0;
        numQuad      = 0;

        if (isOpen("Results")) {
            selectWindow("Results");
            nSkels = nResults;
            for (r = 0; r < nSkels; r++) {
                numBranches  += getResult("# Branches", r);
                numJunctions += getResult("# Junctions", r);
                numEndpoints += getResult("# End-point voxels", r);
                numTriple    += getResult("# Triple points", r);
                numQuad      += getResult("# Quadruple points", r);
            }
            close("Results");
        }

        // ── Collect per-branch data from Branch information table ─────────────
        // Build arrays then write to Detailed sheet.
        // Columns available: Skeleton ID | Branch length | V1 x | V1 y |
        //                    V2 x | V2 y | Euclidean distance | running average |
        //                    branch type

        branchCount_detail = 0;
        branchSkelID       = newArray(0);
        branchLen_arr      = newArray(0);
        branchV1x          = newArray(0);
        branchV1y          = newArray(0);
        branchV2x          = newArray(0);
        branchV2y          = newArray(0);
        branchEuclid       = newArray(0);
        branchRunAvg       = newArray(0);
        branchType         = newArray(0);

        if (isOpen("Branch information")) {
            selectWindow("Branch information");
            nBI = Table.size;
            branchCount_detail = nBI;

            branchSkelID = newArray(nBI);
            branchLen_arr = newArray(nBI);
            branchV1x     = newArray(nBI);
            branchV1y     = newArray(nBI);
            branchV2x     = newArray(nBI);
            branchV2y     = newArray(nBI);
            branchEuclid  = newArray(nBI);
            branchRunAvg  = newArray(nBI);
            branchType    = newArray(nBI);

            for (r = 0; r < nBI; r++) {
                branchSkelID[r] = Table.get("Skeleton ID",          r);
                bl              = Table.get("Branch length",         r);
                branchLen_arr[r] = bl * px2um;                        // → µm
                branchV1x[r]    = Table.get("V1 x",                 r) * px2um;
                branchV1y[r]    = Table.get("V1 y",                 r) * px2um;
                branchV2x[r]    = Table.get("V2 x",                 r) * px2um;
                branchV2y[r]    = Table.get("V2 y",                 r) * px2um;
                branchEuclid[r] = Table.get("Euclidean distance",   r) * px2um;
                branchRunAvg[r] = Table.get("running average length",r) * px2um;
                branchType[r]   = Table.get("branch type",          r);
            }
            close("Branch information");
        }

        // ── Branch length totals ───────────────────────────────────────────────
        // No filtering needed here anymore — short terminal spurs were already
        // physically erased from the skeleton by pruneShortSpurs() above, before
        // Analyze Skeleton ran. numBranches/numJunctions/numEndpoints/numTriple/
        // numQuad above and the branch* arrays below all already reflect the
        // pruned skeleton consistently, so this just totals what's left.
        totalBranchLen_um = 0;
        maxBranchLen_um   = 0;
        for (r = 0; r < branchCount_detail; r++) {
            totalBranchLen_um += branchLen_arr[r];
            if (branchLen_arr[r] > maxBranchLen_um) {
                maxBranchLen_um = branchLen_arr[r];
            }
        }

        if (numBranches > 0) { avgBranchLen_um = totalBranchLen_um / numBranches; }
        else                  { avgBranchLen_um = 0; }

        // ── Derived morphology metrics ─────────────────────────────────────────
        // These are the key LPS-vs-PBS discriminators.

        // Ramification Index: total process length normalised to soma size.
        // Resting (PBS) cells are highly ramified → high value.
        // Activated (LPS) cells retract processes → low value.
        if (somaArea_um2 > 0) {
            ramificationIndex = totalBranchLen_um / somaArea_um2;
        } else { ramificationIndex = 0; }

        // Junction Density: branching complexity per unit length.
        // Ramified cells have many branch points relative to their total length.
        if (totalBranchLen_um > 0) {
            junctionDensity  = numJunctions  / totalBranchLen_um;
            endpointDensity  = numEndpoints  / totalBranchLen_um;
        } else {
            junctionDensity  = 0;
            endpointDensity  = 0;
        }

        // Average Span Ratio: mean(Euclidean_distance / Branch_length) across branches.
        // 1 = perfectly straight; < 1 = tortuous/curving.
        // LPS cells retain fewer, straighter stub processes → higher span ratio.
        spanRatioSum = 0;
        spanRatioN   = 0;
        for (r = 0; r < branchCount_detail; r++) {
            if (branchLen_arr[r] > 0) {
                spanRatioSum += (branchEuclid[r] / branchLen_arr[r]);
                spanRatioN++;
            }
        }
        if (spanRatioN > 0) { avgSpanRatio = spanRatioSum / spanRatioN; }
        else                 { avgSpanRatio = 0; }

        // Branch Density: number of branches per unit soma area.
        if (somaArea_um2 > 0) {
            branchDensity = numBranches / somaArea_um2;
        } else { branchDensity = 0; }

        // Complexity Index: compound measure combining branching and length vs soma.
        // (Num_Endpoints × Total_Length) / Soma_Area — drops sharply with LPS activation.
        if (somaArea_um2 > 0) {
            complexityIndex = (numEndpoints * totalBranchLen_um) / somaArea_um2;
        } else { complexityIndex = 0; }

        // ── Console log ───────────────────────────────────────────────────────
        print("----------------------------------------");
        print("Cell " + picNum + " summary (branches >= " + MIN_BRANCH_LENGTH_UM + " µm):");
        print("  Soma area:          " + somaArea_um2    + " " + unitLabel + "²");
        print("  Soma circularity:   " + somaCirc);
        print("  Soma aspect ratio:  " + somaAR);
        print("  Soma solidity:      " + somaSolid);
        print("  Branches:           " + numBranches);
        print("  Total length:       " + totalBranchLen_um + " " + unitLabel);
        print("  Avg branch len:     " + avgBranchLen_um   + " " + unitLabel);
        print("  Max branch len:     " + maxBranchLen_um   + " " + unitLabel);
        print("  Junctions:          " + numJunctions);
        print("  Endpoints:          " + numEndpoints);
        print("  Triple points:      " + numTriple);
        print("  Quadruple points:   " + numQuad);
        print("  Ramification index: " + ramificationIndex);
        print("  Junction density:   " + junctionDensity);
        print("  Endpoint density:   " + endpointDensity);
        print("  Avg span ratio:     " + avgSpanRatio);
        print("  Branch density:     " + branchDensity);
        print("  Complexity index:   " + complexityIndex);

        // ── Write Summary sheet (one row per cell) ────────────────────────────
        pathway = mainDir + baseName + "-Data.xlsx";

        // Warn before creating a duplicate row if this cell was already
        // written in an earlier finalize (see cellAlreadyRecorded above).
        if (cellAlreadyRecorded(mainDir, picNum)) {
            proceedAnyway = getBoolean(
                "Cell " + picNum + " already has a row in:\n  " + pathway + "\n \n" +
                "This plugin can't overwrite an existing row from a macro, so\n" +
                "continuing will ADD A DUPLICATE row for this cell.\n \n" +
                "If you're redoing this cell: click Cancel, close the Excel file,\n" +
                "manually delete the existing Cell_ID " + picNum + " row(s) from the\n" +
                "Summary and Detailed sheets, then press Shift again.\n \n" +
                "Click OK only if you intend to keep both rows.");
            if (!proceedAnyway) {
                exit("Stopped before writing a duplicate row for Cell " + picNum + ".\n" +
                     "Remove the existing row(s) for this cell from the Excel file,\n" +
                     "then press Shift again.");
            }
            print("WARNING: proceeding with a duplicate Cell_ID " + picNum +
                  " row per user confirmation.");
        }

        if (isOpen("Results")) { close("Results"); }

        if (calibrated) {
            setResult("Cell_ID",                   0, picNum);
            setResult("Soma_Area_um2",             0, somaArea_um2);
            setResult("Soma_Circularity",          0, somaCirc);
            setResult("Soma_AR",                   0, somaAR);
            setResult("Soma_Solidity",             0, somaSolid);
            setResult("Num_Branches",              0, numBranches);
            setResult("Total_Branch_Length_um",    0, totalBranchLen_um);
            setResult("Avg_Branch_Length_um",      0, avgBranchLen_um);
            setResult("Max_Branch_Length_um",      0, maxBranchLen_um);
            setResult("Num_Junctions",             0, numJunctions);
            setResult("Num_Endpoints",             0, numEndpoints);
            setResult("Num_Triple_Points",         0, numTriple);
            setResult("Num_Quadruple_Points",      0, numQuad);
            setResult("Ramification_Index",        0, ramificationIndex);
            setResult("Junction_Density",          0, junctionDensity);
            setResult("Endpoint_Density",          0, endpointDensity);
            setResult("Avg_Span_Ratio",            0, avgSpanRatio);
            setResult("Branch_Density",            0, branchDensity);
            setResult("Complexity_Index",          0, complexityIndex);
        } else {
            // Uncalibrated: keep px labels so the reader knows the unit
            setResult("Cell_ID",                   0, picNum);
            setResult("Soma_Area_px2",             0, somaArea_um2);
            setResult("Soma_Circularity",          0, somaCirc);
            setResult("Soma_AR",                   0, somaAR);
            setResult("Soma_Solidity",             0, somaSolid);
            setResult("Num_Branches",              0, numBranches);
            setResult("Total_Branch_Length_px",    0, totalBranchLen_um);
            setResult("Avg_Branch_Length_px",      0, avgBranchLen_um);
            setResult("Max_Branch_Length_px",      0, maxBranchLen_um);
            setResult("Num_Junctions",             0, numJunctions);
            setResult("Num_Endpoints",             0, numEndpoints);
            setResult("Num_Triple_Points",         0, numTriple);
            setResult("Num_Quadruple_Points",      0, numQuad);
            setResult("Ramification_Index",        0, ramificationIndex);
            setResult("Junction_Density",          0, junctionDensity);
            setResult("Endpoint_Density",          0, endpointDensity);
            setResult("Avg_Span_Ratio",            0, avgSpanRatio);
            setResult("Branch_Density",            0, branchDensity);
            setResult("Complexity_Index",          0, complexityIndex);
        }
        updateResults();
        selectWindow("Results");

        // "stack_results" makes the plugin add this row underneath the
        // existing data in the sheet. 
        run("Read and Write Excel",
            "no_count_column stack_results file=[" + pathway + "] " +
            "sheet=[Summary] " +
            "dataset_label=[]");
        close("Results");
        print("Excel summary written: " + pathway);
        markCellRecorded(mainDir, picNum);

        // ── Write Detailed sheet (one row per branch) ─────────────────────────
        if (branchCount_detail > 0) {
            for (r = 0; r < branchCount_detail; r++) {
                setResult("Cell_ID",                  r, picNum);
                setResult("Skeleton_ID",              r, branchSkelID[r]);
                if (calibrated) {
                    setResult("Branch_Length_um",         r, branchLen_arr[r]);
                    setResult("V1x_um",                   r, branchV1x[r]);
                    setResult("V1y_um",                   r, branchV1y[r]);
                    setResult("V2x_um",                   r, branchV2x[r]);
                    setResult("V2y_um",                   r, branchV2y[r]);
                    setResult("Euclidean_Distance_um",    r, branchEuclid[r]);
                    setResult("Running_Avg_Length_um",    r, branchRunAvg[r]);
                } else {
                    setResult("Branch_Length_px",         r, branchLen_arr[r]);
                    setResult("V1x_px",                   r, branchV1x[r]);
                    setResult("V1y_px",                   r, branchV1y[r]);
                    setResult("V2x_px",                   r, branchV2x[r]);
                    setResult("V2y_px",                   r, branchV2y[r]);
                    setResult("Euclidean_Distance_px",    r, branchEuclid[r]);
                    setResult("Running_Avg_Length_px",    r, branchRunAvg[r]);
                }
                setResult("Branch_Type",              r, branchType[r]);
            }
            updateResults();
            selectWindow("Results");

            run("Read and Write Excel",
                "no_count_column stack_results file=[" + pathway + "] " +
                "sheet=[Detailed] " +
                "dataset_label=[]");
            close("Results");
            print("Excel detailed written: " + pathway + "  (" + branchCount_detail + " branches)");
        } else {
            print("No branch data to write to Detailed sheet.");
        }

        // ── Save skeleton with scale bar ──────────────────────────────────────
        selectWindow(officialName + "(Skeleton)");
        addScaleBar();
        saveAs("Tiff", File.directory + officialName + "(Skeleton).tif");
        close();

        // ── Advance to next image or finish ───────────────────────────────────
        // Next cell lives in its own subfolder under mainDir, e.g. <baseName>-2/
        nextCellName   = baseName + "-" + (picNum + 1);
        nextCellFolder = mainDir + nextCellName + File.separator;
        nextImg        = nextCellFolder + nextCellName + ".tif";

        if (File.exists(nextImg)) {
            closeAllImages();
            open(nextImg);
            picNum++;

            waitForUser("Next image loaded: " + baseName + "-" + picNum +
                        "\n\nAdjust brightness/contrast now if needed — this affects" +
                        "\nboth soma detection and process skeletonization." +
                        "\n\nClick OK to skeletonize.");

            officialName = getTitle();
            dotIdx = officialName.lastIndexOf(".");
            if (dotIdx > 0) { officialName = officialName.substring(0, dotIdx); }
            rename(officialName);
            parsed    = parseCellFilename(officialName);
            splitIdx  = parsed.lastIndexOf("||");
            baseName  = parsed.substring(0, splitIdx);
            picNum    = parseInt(parsed.substring(splitIdx + 2, parsed.length()));

            // Re-read calibration from new image
            getVoxelSize(pixW, pixH, pixD, pixUnit);
            if (pixUnit == "microns" || pixUnit == "µm" || pixUnit == "um") {
                calibrated = true;
                px2um      = pixW;
                px2um2     = pixW * pixH;
                unitLabel  = "um";
                print("Calibration: " + pixW + " µm/px  (area factor: " + px2um2 + " µm²/px²)");
            } else {
                calibrated = false;
                px2um      = 1;
                px2um2     = 1;
                unitLabel  = "px";
                print("WARNING: No µm calibration found — measurements will be in pixels.");
                showMessage("WARNING: No pixel calibration found!\n \n" +
                    "All measurements will be recorded in pixels, not microns.\n \n" +
                    "To fix before continuing:\n" +
                    "  1. Close this dialog\n" +
                    "  2. Go to Image > Properties\n" +
                    "  3. Set Pixel Width, Pixel Height, and Unit to 'microns'\n" +
                    "  4. Press F2 again\n \n" +
                    "Click OK to continue anyway (pixel units will be used).");
            }

            // Lock/verify this cell's calibration against the rest of the batch.
            checkAndLockCalibration(mainDir, calibrated, px2um);

            runSkeletonizeAndPreparePreview();

            print("========================================");
            print("Image: " + officialName);
            print("Edit on the COMPOSITE window (red = skeleton).");
            print("  Channel 1 must be active (bottom slider).");
            print("  WHITE brush = draw | BLACK brush = erase");
            print("----------------------------------------");
            print("  Space  → re-skeletonize and refresh preview");
            print("  Shift  → collect data and continue");
            print("========================================");

        } else {
            closeAllImages();
            editing = false;
            print("========================================");
            print("All images processed. Pipeline complete.");
            print("Review the measurements above, then check your Excel file:");
            print("  " + mainDir + baseName + "-Data.xlsx");
            print("========================================");
            wait(500);
            break;
        }
    }
}
