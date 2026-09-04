/*
================================================================================
                                 SkeleSketch
================================================================================

SETUP
-----
1. Place the unzipped 'SkeleSketch' folder here:
      Fiji.app > scripts > Plugins

2. Install dependencies via:
      Help > Update... > Manage Update Sites
   Enable all of the following, then click Apply Changes:
      - ImageJ  
      - Fiji   
      - Java-8         
      - ResultsToExcel     

3. Restart Fiji (close and reopen).

4. Run this README file once to install keyboard shortcuts:
      Plugins > SkeleSketch > README

WORKFLOW
--------
  F1  →  Capture Images
  	1. Open your full image via File > Import > Bio-Formats. Make preprocessing 
  	   adjustments as needed, then press F1:
  		a. Convert to Grayscale: Select Image > Lookup Table > Grays.   
		b. Adjust Bit Depth: Convert images to 16-bit by selecting Image > 16-bit.   
		c. Invert Background: Ensure a dark background by going to Image > Lookup Table
		> Invert LUT.
		d. Increase Contrast: To improve detection of dim processes, select 
		Image > Adjust > Brightness/Contrast and change as needed.  
  	2. Draw around each cell with the polygon tool and press Space to capture.
  	3. Press Shift when done — files are saved automatically.
  	4. Each cell gets its own subfolder, e.g. BaseName-1/BaseName-1.tif
  	5. A scale bar is burned into each saved crop and the labeled overview.

  F2  →  Edit & Finalize
 	1. Open a captured cell image, then press F2.
    2. The macro will skeletonize it and detect the soma automatically.
    	a. Skeleton stage: Edit > Options > Colors, set foreground to black to
           remove excess skeleton parts or to white to add missing parts.
        b. Press Space to re-skeletonize and refresh the preview.
        c. Press Shift when the skeleton looks right - this moves on to the
           soma stage (see SOMA EDITING for extra details below).
        d. Soma stage: same brush pattern, now editing the soma mask instead of
       the skeleton. Press Space to sync your edits and see live stats in
       the Log, Shift to accept the soma.

PARAMETER REFERENCE — WHERE TO TUNE EACH SETTING
--------------------------------------------------
  Every tunable parameter is a named variable near the top of one
  file, under a "Tunable Parameters" comment block. Find the file below,
  open it, edit the variable, save, and restart Fiji (see NOTES).

  Capture_Images.ijm (F1) — Tunable Parameters section:
      SCALEBAR_WIDTH_UM, SCALEBAR_HEIGHT, SCALEBAR_FONT,
      SCALEBAR_COLOR, SCALEBAR_LOCATION
          Scale bar drawn on saved crops + the labeled overview.
          Keep these in sync with the matching set below in
          Edit_Finalize.ijm if you want crops and finalized outputs to
          look consistent — see SCALE BAR ON SAVED IMAGES below.

  Edit_Finalize.ijm (F2) — Tunable Parameters section:
      MICROGLIA_CHANNEL              — which channel is the microglia stain
                                        (see CHANNEL SELECTION below)
      SOURCE_INTENSITY_MAX           — 16→8-bit scaling mode
                                        (see SOURCE_INTENSITY_MAX below)
      SOMA_TOP_PERCENT               — soma detection sensitivity
      SOMA_ABS_MIN_INTENSITY         — soma detection floor
      SOMA_BLUR_RADIUS               — soma pre-threshold smoothing
      SOMA_ERODE_PASSES              — shrink soma mask
      SOMA_DILATE_PASSES             — grow soma mask
      SOMA_MIN_AREA / SOMA_MAX_AREA  — soma size filter (px²)
      SOMA_CIRCULARITY_MIN           — soma roundness filter
      CONTRAST_SATURATE              — process contrast stretch
      PROCESS_THRESHOLD_METHOD       — auto-threshold method for processes
      PROCESS_FIXED_THRESHOLD        — fixed threshold for processes (0=auto)
      PROCESS_BLUR_SIGMA             — process pre-threshold smoothing
      PROCESS_DESPECKLE_PASSES       — noise removal after thresholding
      MIN_BRANCH_LENGTH_UM           — spur-pruning threshold (see
                                        TROUBLESHOOTING — Inflated or
                                        Inconsistent Junction/Endpoint
                                        Counts below)
      SCALEBAR_WIDTH_UM, SCALEBAR_HEIGHT, SCALEBAR_FONT,
      SCALEBAR_COLOR, SCALEBAR_LOCATION
          Scale bar for all F2-saved outputs (Skeleton, Tagged-Skeleton,
          Composite, Soma-Mask, Soma-Overlay).

  Skeletonize_And_Detect_Soma.ijm — No parameters to edit here. It reads
      every value above from a temp config file that Edit_Finalize.ijm
      writes each time it calls this macro, so any edit made directly in
      this file is silently overwritten on the next F2 run. If a setting
      isn't listed above, it isn't user-tunable.

FOLDER STRUCTURE
----------------
  Everything for one source image lives under a single folder, created by F1:

      BaseName-Images/
        BaseName-Labeled.tif        (overview with numbered annotations)
        BaseName-Base.tif           (original image)
        BaseName-Data.xlsx          (Summary + Detailed sheets — ALL cells)
        BaseName-1/
          BaseName-1.tif                  (the crop, saved by F1)
          BaseName-1(Skeleton).tif        (saved by F2)
          BaseName-1(Tagged-Skeleton).tif (saved by F2)
          BaseName-1(Composite).tif       (saved by F2)
          BaseName-1(Soma-Mask).tif       (saved by F2)
          BaseName-1(Soma-Overlay).tif    (saved by F2)
        BaseName-2/
          BaseName-2.tif, ... (same pattern)

  Each cell's own images stay together in its numbered subfolder, while the
  one combined Excel file sits at the top, alongside the overview images, so
  it can collect rows from every cell in the batch.

FILE NAMING — IF YOU RENAME OR MOVE FILES BY HAND
---------------------------------------------------
  Capture_Images.ijm (F1) generates the "BaseName-N.tif" pattern above
  automatically. Be cautious renaming, copying, or moving a cell-crop file yourself before
  opening it for F2.

  The rule Edit_Finalize.ijm (F2) relies on: the open image's title must end
  in "-<N>" — a plain whole number — right before the file extension.
      Mouse1-3.tif              -> OK   (BaseName "Mouse1",            cell 3)
      2024-06-12_Mouse-1-7.tif  -> OK   (BaseName "2024-06-12_Mouse-1", cell 7)
      Mouse1-3_edited.tif       -> FAILS (extra text after the number)
      Mouse1-Series2.tif        -> FAILS (no number after the last dash)

  BaseName itself can contain as many dashes, underscores, or dates as you
  like — F2 always splits on the last dash in the title, so only the very
  last segment needs to be a clean integer. If it isn't, F2 stops with an
  on-screen message explaining what it expected.

CHANNEL SELECTION (multi-channel VSI exports)
---------------------------------------------
  If your image is a multi-channel export (e.g. FITC / TRITC / CY5), open
  Edit_Finalize.ijm and set MICROGLIA_CHANNEL to the channel number that
  contains your microglia stain:
      1 = FITC   (default)
      2 = TRITC
      3 = CY5

  This value is passed automatically to Skeletonize_And_Detect_Soma.ijm at
  run time — you only need to set it in one place.

SOURCE_INTENSITY_MAX — WHY MEASUREMENTS NEED THIS
--------------------------------------------------
  SOMA_ABS_MIN_INTENSITY and PROCESS_FIXED_THRESHOLD are 8-bit thresholds
  (0-255). If your source images are 16-bit, converting to 8-bit normally
  rescales using whatever Brightness/Contrast is currently on screen — which
  for this pipeline means the manual B/C adjustment you make in F1 while
  finding cells. Left alone, that would make the same real signal map to
  different 8-bit values on different images, breaking the
  absolute thresholds this pipeline relies on.

  Edit_Finalize.ijm resets the display range before every 16→8-bit
  conversion used for measurement, so your F1 Brightness/Contrast tweaks
  only affect what you see while cropping — not what gets measured. Two
  modes, set via SOURCE_INTENSITY_MAX at the top of Edit_Finalize.ijm:

      SOURCE_INTENSITY_MAX = 0     (default) "auto" — each image is scaled
                                     to its own actual min/max. Removes the
                                     dependency on manual B/C, but images
                                     with very different overall brightness
                                     are still each stretched independently.

      SOURCE_INTENSITY_MAX = 4095  (example) fixed absolute scale used for
                                     every image in the batch — set this to
                                     your camera's real max ADU/bit depth
                                     (e.g. 4095 for a 12-bit camera, 65535
                                     for true 16-bit) for the most rigorous,
                                     fully cross-image-comparable option.
                                     Recommended once you know your camera's
                                     specs — set it once per study.

MICRON CALIBRATION
------------------
  The pipeline reads pixel size from the image's own calibration metadata
  (visible under Image > Properties). VSI files opened via Bio-Formats carry
  this automatically (e.g. 0.5119 µm/px as shown in Image Properties).

  All Excel output columns are in µm / µm² when calibration is detected.
  If calibration is missing, column headers switch to _px / _px2 as a reminder.

  To set calibration manually before pressing F2:
      Image > Properties → set Pixel Width, Pixel Height, and Unit to "microns"

  A batch's calibration is now locked the first time any cell in that
  "<BaseName>-Images" folder is finalized (recorded in a hidden
  ".calibration.txt" file alongside the Excel output), and every later cell
  — including ones finalized in a later session, possibly days apart — is
  checked against it. If a cell doesn't match (calibrated vs. uncalibrated,
  or a µm/px scale that differs by more than 0.5%, e.g. from an accidental
  objective/zoom change), F2 stops with an on-screen explanation instead of
  writing data that would corrupt or silently misrepresent that sheet. If
  you deliberately need a different scale for some cells, use a separate
  output folder for them rather than continuing the same batch.

EXCEL OUTPUT
------------
  Each batch writes one combined file, one level above the cell subfolders:
  BaseName-Images/BaseName-Data.xlsx

  Sheet: "Summary"  (one row per cell)
    Cell_ID, Soma_Area_um2,
    Soma_Circularity, Soma_AR, Soma_Solidity,
    Num_Branches,
    Total_Branch_Length_um, Avg_Branch_Length_um, Max_Branch_Length_um,
    Num_Junctions, Num_Endpoints, Num_Triple_Points, Num_Quadruple_Points,
    Ramification_Index, Junction_Density, Endpoint_Density,
    Avg_Span_Ratio, Branch_Density, Complexity_Index

  Sheet: "Detailed"  (one row per branch — appended each cell)
    Cell_ID, Skeleton_ID, Branch_Length_um,
    V1x_um, V1y_um, V2x_um, V2y_um,
    Euclidean_Distance_um, Running_Avg_Length_um, Branch_Type

  REDOING A CELL: if you finalize the same cell twice (bad edit, wrong
  parameters, etc.), F2 now checks a hidden ".finalized_cells.txt" marker
  file in the batch folder and warns you before writing — since the Excel
  plugin can't overwrite an existing row from a macro, pressing Shift again
  would otherwise silently add a second row for the same Cell_ID. Choose
  Cancel to stop and manually delete the old row(s) first, or OK to keep
  both rows intentionally.

RESUMING A CAPTURE SESSION (F1)
--------------------------------
  If you close Fiji and come back later to capture more cells from the same
  base image, F1 now scans the output folder and resumes cell numbering
  after the highest existing "<BaseName>-N" subfolder, instead of
  restarting at 1 and overwriting what's already there. Note that the
  "-Labeled.tif" and "-Base.tif" overview images are still overwritten each
  run and only reflect cells captured in that session.

SCALE BAR ON SAVED IMAGES
--------------------------
  A scale bar is added to every saved .tif (crops, skeleton, tagged skeleton,
  composite, soma mask, soma overlay). Default is 10 µm, white, lower-right corner.

  To change the scale bar size or style, open Edit_Finalize.ijm and adjust
  the variables at the top of the Tunable Parameters section:
      SCALEBAR_WIDTH_UM  — bar length in microns (default 10)
      SCALEBAR_HEIGHT    — bar thickness in pixels (default 4)
      SCALEBAR_FONT      — label font size (default 14)
      SCALEBAR_COLOR     — color string (default "White")
      SCALEBAR_LOCATION  — corner: "Lower Right", "Lower Left", etc.

  For crop images (F1), the same defaults are used and can be changed via the
  matching SCALEBAR_* variables at the top of Capture_Images.ijm.

SOMA EDITING
------------
  Pressing Shift on the skeleton stage moves
  you into a second editing stage for the soma, using the exact same
  Space/Shift brush pattern as skeleton editing, just on a different
  Composite window:

      Channel 1 (RED)   = soma mask (this is what you edit)
      Channel 2 (GREEN) = the cell, for reference

      WHITE brush  → add to the soma
      BLACK brush  → erase from the soma
      Space        → sync your brush strokes into the mask and print live
                      Area / Circ / AR / Solidity to the Log, so you can
                      watch the numbers as you paint - the composite
                      refreshes with a clean (non-antialiased) version of
                      your edit, same as skeleton editing's preview refresh
      Shift        → accept the current mask, collect data, save the soma
                      images, and advance to the next cell

  If nothing was automatically detected, channel 1 just starts blank -
  paint the soma yourself with the white brush, or press Shift right away
  to accept an empty soma (Soma_Area = 0).

  Whatever you accept here is what gets saved
  to Soma-Mask.tif / Soma-Overlay.tif and measured for Soma_Area,
  Soma_Circularity, Soma_AR, and Soma_Solidity in the Excel output.

SOMA OUTPUT IMAGES
------------------
  Two extra images are saved per cell alongside the skeleton outputs:

  <name>-N(Soma-Mask).tif
    White soma blob on a black background — shows the exact region used for
    soma area / circularity / AR / solidity measurements.

  <name>-N(Soma-Overlay).tif
    The cell image in green with the soma region highlighted in cyan.
    Use this to verify the soma detection looks correct for each cell.

  If the automatic soma region is consistently too small, too large, or
  missed for MOST cells in a batch, it's worth adjusting the detection
  parameters rather than brush-correcting every single cell:
      SOMA_TOP_PERCENT       — raise to grow the mask, lower to shrink it
      SOMA_DILATE_PASSES     — raise to expand the mask outward (covers halo),
                               lower/zero if nearby process roots disappear
      SOMA_ABS_MIN_INTENSITY — lower if soma is too dim to be detected
  For the occasional cell that just needs a one-off correction, use the
  soma editing stage above instead of changing parameters for everything.

TROUBLESHOOTING — Soma Not Detected
-------------------------------------
  If the log prints "WARNING: No soma detected", the soma editing stage
  (see above) starts with a blank mask you can paint directly. 
  If it's happening on most/all cells in a batch, try these in order instead:

  1. Verify the channel: set MICROGLIA_CHANNEL to the correct channel number.

  2. Lower SOMA_ABS_MIN_INTENSITY (default 150): open Edit_Finalize.ijm
     and reduce to 120 or 100 if your soma appear dim.

  3. Raise SOMA_TOP_PERCENT (default 12) toward 20 to widen the bright-pixel window.

  4. Lower SOMA_CIRCULARITY_MIN (default 0.4) toward 0.2 if the soma is very irregular.

  5. Check manually: Image > Adjust > Threshold → set method to Otsu,
     tick "Dark background", and confirm the soma region is highlighted.
     If it isn't, the signal may be too dim — try adjusting brightness/contrast
     before pressing F2.

TROUBLESHOOTING — Soma Leaking into Skeleton (spurious junctions)
------------------------------------------------------------------
  If you see a tangle of skeleton lines inside or at the edge of the soma:

  1. Raise SOMA_DILATE_PASSES (default 2) to 3–4 to extend the soma mask
     outward and cover more of the bright halo around the soma core.

  2. Raise SOMA_TOP_PERCENT to cover a larger fraction of the bright core.

  3. If process roots start disappearing (over-masking), reduce SOMA_DILATE_PASSES
     back down and instead raise SOMA_TOP_PERCENT to grow the core mask
     without expanding it outward as aggressively.

TROUBLESHOOTING — Inflated or Inconsistent Junction/Endpoint Counts
---------------------------------------------------------------------
  Jagged mask edges and pixel-level noise commonly cause 
  reports of extra small "spur" branches that aren't real branching — these
  inflate Num_Junctions, Num_Triple_Points, and Num_Quadruple_Points even
  when Num_Branches looks reasonable.

  Edit_Finalize.ijm now handles this with pixel-level spur pruning
  (pruneShortSpurs(), called from the Helper Functions section): any
  terminal spur — a free endpoint walked inward to the nearest junction —
  shorter than MIN_BRANCH_LENGTH_UM is physically erased from the skeleton
  pixels before Analyze Skeleton ever measures it, not hidden from the
  stats afterward. The junction pixel at the far end is identified purely
  by its own pixel connectivity (3+ neighbouring skeleton pixels) and is
  never erased directly, so two real junctions that happen to sit close
  together are never merged or miscounted — only true dead-end-to-junction
  spurs are removed. Because pruning happens before the single Analyze
  Skeleton measurement, every reported number — Num_Branches, Num_Junctions,
  Num_Endpoints, Num_Triple_Points, Num_Quadruple_Points, and every row in
  the Detailed sheet — comes from one consistent reading of the same
  already-pruned skeleton. The saved (Skeleton).tif and (Tagged-Skeleton).tif
  files reflect the same pruned result you see in the live Space-key preview,
  so what you visually accept while editing always matches what gets measured.

  If junction/endpoint counts still look wrong after this:
  1. Raise MIN_BRANCH_LENGTH_UM (Edit_Finalize.ijm) if small noise spurs
     are still surviving — fewer, longer spurs get pruned at a higher value.
  2. Lower it if real short terminal twigs are being trimmed away.
  3. Watch the Log window during Finalize — it prints how many spurs were
     pruned per cell, so you can sanity-check whether the count looks
     reasonable for that image.
  4. Remaining tangles right at the soma boundary are usually a soma-mask
     issue, not a spur-pruning issue — see the section above instead.

TROUBLESHOOTING — No Skeleton / Poor Skeleton
----------------------------------------------
  All of these live in Edit_Finalize.ijm's Tunable Parameters section (see
  PARAMETER REFERENCE near the top of this file for the full list).

  1. Raise PROCESS_DESPECKLE_PASSES (default 1) if isolated noise pixels are
     surviving thresholding as fake short branches; lower it (to 0) if it's
     removing real dim process pixels along with the noise.

  2. Lower PROCESS_FIXED_THRESHOLD (default 32) to capture more/dimmer
     processes, or set it to 0 to fall back to auto-thresholding via
     PROCESS_THRESHOLD_METHOD instead of a fixed value.

  3. PROCESS_THRESHOLD_METHOD (default "Li") is already the most aggressive
     common option for lifting dim structures. If it's picking up too much
     background noise instead, try "Otsu" for a stricter threshold.

  4. Raise CONTRAST_SATURATE (default 0.05) if the contrast stretch before
     thresholding is over-saturating and washing out real signal; lower it
     for a more aggressive stretch that lifts dimmer distal tips.

  5. Reduce MIN_BRANCH_LENGTH_UM (default 5) to keep shorter branch tips —
     this is the spur-pruning threshold described below, not a detection
     parameter, but overly aggressive pruning can look like "no skeleton"
     on small/sparse cells.

LPS vs PBS DISCRIMINATION EXAMPLE — KEY METRICS
----------------------------------------
  Standard skeleton stats (branch count, total length, etc.) often fail to
  separate LPS-treated from PBS microglia on their own because they scale
  with cell size and image variability. The following derived metrics, now
  included in every Summary row, are the strongest discriminators:

  Ramification_Index  (Total_Branch_Length / Soma_Area)
    PBS (resting):  high — many long processes relative to a small soma.
    LPS (activated): low — processes retract, soma enlarges.
    → Usually the single best individual discriminator.

  Complexity_Index  ((Num_Endpoints × Total_Branch_Length) / Soma_Area)
    A compound measure; drops sharply with LPS activation.

  Junction_Density  (Num_Junctions / Total_Branch_Length)
    PBS cells have many branch points per µm — dense arborisation.
    LPS cells retain few, simple processes.

  Soma_Circularity  (0–1; 1 = perfect circle)
    LPS → rounder soma → higher circularity.
    PBS → irregular, processes pulling soma out → lower circularity.

  Soma_AR  (major axis / minor axis)
    LPS → closer to 1.0 (round).
    PBS → higher (elongated by process roots).

  Avg_Span_Ratio  (mean Euclidean_distance / Branch_length)
    0–1; 1 = straight, <1 = tortuous.
    Not always significant alone, but useful combined with other metrics.

NOTES
-----
  * Any changes to macro files require a Fiji restart to take effect.
  * Make sure the output Excel file is CLOSED before pressing Shift in F2,
    otherwise data cannot be written.
  * All tunable parameters are defined as named variables at the top of each
    macro file — no need to edit logic.
================================================================================
*/

run("Add Shortcut... ", "shortcut=F1 command=[Capture Images]");
run("Add Shortcut... ", "shortcut=F2 command=[Edit Finalize]");

// =============================================================================
// WELCOME SPLASH
// =============================================================================
// Finds the SkeleSketch folder 
// and shows a welcome dialog with the logo embedded inside it.
// No Log window: all print() calls have been removed intentionally.

macroDir = "";

function findSkeleSketchDir(searchParent) {
    if (!File.isDirectory(searchParent)) return "";
    entries = getFileList(searchParent);
    for (k = 0; k < entries.length; k++) {
        entryName = replace(entries[k], "/", "");
        fullPath = searchParent + File.separator + entryName;
        if (startsWith(entryName, "SkeleSketch") && File.isDirectory(fullPath)) {
            return fullPath;
        }
    }
    return "";
}

// Strategy 1: derive from macro.filepath (works from editor or AutoRun).
macroPath = getInfo("macro.filepath");
if (macroPath != "" && macroPath != "null" && File.exists(macroPath)) {
    resolvedDir = File.getParent(macroPath);
    folderName = File.getName(resolvedDir);
    if (startsWith(folderName, "SkeleSketch")) {
        macroDir = resolvedDir;
    } else {
        parentDir = File.getParent(resolvedDir);
        macroDir = findSkeleSketchDir(parentDir);
    }
}

// Strategy 2: scan Fiji scripts/Plugins/.
if (macroDir == "" || !File.isDirectory(macroDir)) {
    fijiDir = getDirectory("imagej");
    macroDir = findSkeleSketchDir(fijiDir + "scripts" + File.separator + "Plugins");
}

// Strategy 3: scan Fiji plugins/.
if (macroDir == "" || !File.isDirectory(macroDir)) {
    macroDir = findSkeleSketchDir(getDirectory("plugins"));
}

// Find welcome image and build a file:// URI for embedding in the dialog.
welcomePath = "";
exts = newArray("png", "jpg", "jpeg", "tif", "tiff");
for (i = 0; i < exts.length; i++) {
    candidate = macroDir + File.separator + "welcome." + exts[i];
    if (File.exists(candidate) && welcomePath == "") {
        welcomePath = candidate;
    }
}

imgURI = "file:///" + replace(welcomePath, " ", "%20");
imgURI = replace(imgURI, "file:////", "file:///");

if (welcomePath != "") {
    imgTag = "<img src='" + imgURI + "' width='110' " +
             "style='display:block; margin:0 auto 12px auto;'>";
} else {
    imgTag = "";
}

showMessage("SkeleSketch",
    "<html>" +
    "<body style='font-family:sans-serif; padding:20px; width:400px;'>" +

    imgTag +

    "<h2 style='text-align:center; font-size:20px; margin:0 0 4px 0;'>" +
        "Welcome to SkeleSketch" +
    "</h2>" +
    "<p style='text-align:center; color:#666; font-size:11px; margin:0 0 16px 0;'>" +
        "A Microglia Morphological Analysis Pipeline" +
    "</p>" +

    "<hr style='border:none; border-top:1px solid #ddd; margin:0 0 14px 0;'/>" +

    "<table cellpadding='7' style='width:100%; font-size:13px;'>" +
        "<tr>" +
            "<td style='width:28px; vertical-align:top; padding-top:9px;'><b>F1</b></td>" +
            "<td style='vertical-align:top;'>" +
                "<b>Capture Images</b>" +
                "<br/><span style='color:#555; font-size:12px;'>" +
                    "Open a full image and press F1 to crop and save individual cells." +
                "</span>" +
            "</td>" +
        "</tr>" +
        "<tr>" +
            "<td style='vertical-align:top; padding-top:9px;'><b>F2</b></td>" +
            "<td style='vertical-align:top;'>" +
                "<b>Edit &amp; Finalize</b>" +
                "<br/><span style='color:#555; font-size:12px;'>" +
                    "Press F2 on each crop to skeletonize, detect the soma, and export measurements." +
                "</span>" +
            "</td>" +
        "</tr>" +
    "</table>" +

    "<hr style='border:none; border-top:1px solid #ddd; margin:14px 0 10px 0;'/>" +

    "<p style='font-size:10px; color:#999; text-align:center; margin:0;'>" +
        "Full documentation is in this README file" +
    "</p>" +

    "</body></html>");
