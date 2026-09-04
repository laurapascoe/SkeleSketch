/*
================================================================================
  Skeletonize_And_Detect_Soma.ijm
  Called internally by Edit_Finalize.ijm — do not run directly.
================================================================================
  Pipeline:
    1. Detect soma using a high percentile threshold — bright core only
    2. Mask soma out so it doesn't corrupt the skeleton
    3. Contrast-stretch the process image, threshold, skeletonize
    4. Produce a composite overlay for review

  Parameters are passed from Edit_Finalize.ijm via a temp config file
  (SkeleSoma_params.txt) written to the system temp directory before this
  macro is called. Do not run this macro directly — it will exit with an
  error if the config file is missing.
================================================================================
*/

// ── Parameters — read from config file written by Edit_Finalize.ijm ──────────
//
// All tunable parameters live in Edit_Finalize.ijm (the single source of truth).
// Edit_Finalize.ijm writes them to a temp config file before calling
// run("Skeletonize And Detect Soma"), and this block reads them back.
// IJ macro has no shared variable scope between macros launched with run(),
// so a temp file is the standard mechanism for passing multiple values.
// Never add a duplicate parameter block here.

cfgPath = getDirectory("temp") + "SkeleSoma_params.txt";
if (!File.exists(cfgPath)) {
    exit("SkeleSoma_params.txt not found in temp directory.\n" +
         "Run this macro via F2 in Edit_Finalize.ijm, not directly.");
}
cfgLines = split(File.openAsString(cfgPath), "\n");
for (ci = 0; ci < cfgLines.length; ci++) {
    line = cfgLines[ci];
    line = replace(line, "\r", "");   // strip Windows CR if present
    eqIdx = indexOf(line, "=");
    if (eqIdx < 1) { continue; }
    cfgKey = substring(line, 0, eqIdx);
    cfgVal = substring(line, eqIdx + 1);
    if      (cfgKey == "MICROGLIA_CHANNEL")         { MICROGLIA_CHANNEL         = parseInt(cfgVal);   }
    else if (cfgKey == "SOURCE_INTENSITY_MAX")       { SOURCE_INTENSITY_MAX      = parseFloat(cfgVal); }
    else if (cfgKey == "SOMA_TOP_PERCENT")           { SOMA_TOP_PERCENT          = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_ABS_MIN_INTENSITY")     { SOMA_ABS_MIN_INTENSITY    = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_BLUR_RADIUS")           { SOMA_BLUR_RADIUS          = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_ERODE_PASSES")          { SOMA_ERODE_PASSES         = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_DILATE_PASSES")         { SOMA_DILATE_PASSES        = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_MIN_AREA")              { SOMA_MIN_AREA             = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_MAX_AREA")              { SOMA_MAX_AREA             = parseInt(cfgVal);   }
    else if (cfgKey == "SOMA_CIRCULARITY_MIN")       { SOMA_CIRCULARITY_MIN      = parseFloat(cfgVal); }
    else if (cfgKey == "CONTRAST_SATURATE")          { CONTRAST_SATURATE         = parseFloat(cfgVal); }
    else if (cfgKey == "PROCESS_THRESHOLD_METHOD")   { PROCESS_THRESHOLD_METHOD  = cfgVal;             }
    else if (cfgKey == "PROCESS_FIXED_THRESHOLD")    { PROCESS_FIXED_THRESHOLD   = parseInt(cfgVal);   }
    else if (cfgKey == "PROCESS_BLUR_SIGMA")         { PROCESS_BLUR_SIGMA        = parseFloat(cfgVal); }
    else if (cfgKey == "PROCESS_DESPECKLE_PASSES")   { PROCESS_DESPECKLE_PASSES  = parseInt(cfgVal);   }
}

// ── End of Parameter Block ────────────────────────────────────────────────────

// ── Helper Functions ──────────────────────────────────────────────────────────

// This macro is launched via run() from Edit_Finalize.ijm, which has no
// shared variable scope with it, so this hider is duplicated here rather
// than shared. Ensures the ROI Manager exists (used below for soma blob
// detection) and keeps its window hidden - see the fuller comment on the
// matching function in Edit_Finalize.ijm. Harmless / a no-op if
// Edit_Finalize.ijm already hid it earlier in the session.
function hideRoiManager() {
    if (!isOpen("ROI Manager")) {
        run("ROI Manager...");
    }
    eval("script",
        "importClass(Packages.ij.plugin.frame.RoiManager);" +
        "rm = RoiManager.getInstance();" +
        "if (rm != null) rm.setVisible(false);");
}

// Converts the current image to 8-bit independent of any manual
// Brightness/Contrast left on screen from F1 preprocessing - see the
// SOURCE_INTENSITY_MAX comment in Edit_Finalize.ijm (the single source of
// truth for this parameter) for why that matters. No-op if already 8-bit.
// Must produce identical results to Edit_Finalize.ijm's copy of this
// function, since the same source pixels are measured against the same
// absolute thresholds (SOMA_ABS_MIN_INTENSITY, PROCESS_FIXED_THRESHOLD) in
// both files.
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

// Duplicates the microglia channel from the named source window, renamed to
// newName. Falls back to a plain duplicate of the whole image when the
// source isn't multi-channel. Used both when normalising the source image
// to 8-bit grayscale (STEP 0) and when rebuilding the preview overlay
// (STEP 4), so both stay in sync with MICROGLIA_CHANNEL.
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

// Belt-and-suspenders: Edit_Finalize.ijm already hides the ROI Manager
// before calling this macro, but keep it hidden here too in case this ever
// runs in a context where that didn't happen.
hideRoiManager();

sourceName = getTitle();
zoom = getZoom() * 100;

// ── STEP 0: Normalise to 8-bit grayscale ─────────────────────────────────────
Stack.getDimensions(sw, sh, sc, ss, sf);

print("----------------------------------------");
print("Image: " + sourceName);
print("Dimensions: " + sw + " x " + sh + " px  |  Channels: " + sc);

duplicateMicrogliaChannel(sourceName, "work");
selectWindow("work");
run("Grays");

// ── STEP 1: Soma Detection ────────────────────────────────────────────────────
// Strategy: threshold only the top N% brightest pixels — this isolates the
// bright soma core without pulling in dim process roots.
//
// NOTE ON DUPLICATION: this percentile-threshold detection is intentionally
// re-run in Edit_Finalize.ijm's "Soma re-measurement" step. ImageJ macro has
// no include/module mechanism for sharing a function between two files
// launched with run(), so keeping one copy in each file (both driven by the
// same SOMA_* parameters from the single config file) is the practical
// option here. The two are allowed to reach different final answers now:
// this copy only needs a reasonable mask to subtract from the process image
// before skeletonizing (a small soma-boundary error just leaves a short
// stub for the user to trim with the brush tool); Edit_Finalize.ijm's copy
// feeds the soma brush-editing stage (Space/Shift on the Composite, see
// rebuildSomaComposite() in Edit_Finalize.ijm) and produces the
// authoritative Soma_Area/Circularity/AR/Solidity written to Excel. Don't
// try to make this copy "smarter" to match - accuracy for the numbers that
// matter belongs in Edit_Finalize.ijm, where the user can see and correct it.

run("Duplicate...", " ");
rename("soma_detect");
selectWindow("soma_detect");
run("Gaussian Blur...", "sigma=" + SOMA_BLUR_RADIUS);

// Find the intensity value at the (100 - SOMA_TOP_PERCENT) percentile
getStatistics(imgArea, mean, imgMin, imgMax, std, histogram);
totalPx  = imgArea;
targetPx = totalPx * (SOMA_TOP_PERCENT / 100.0);
cumulative    = 0;
somaThreshLow = imgMax;
i = 255;
while (i >= 0 && cumulative < targetPx) {
    cumulative += histogram[i];
    if (cumulative >= targetPx) { somaThreshLow = i; }
    i--;
}
// Clamp: never let the threshold drop below the absolute minimum.
// This prevents dim images from qualifying faint debris as soma.
if (somaThreshLow < SOMA_ABS_MIN_INTENSITY) {
    print("Soma threshold clamped: percentile gave " + somaThreshLow +
          ", raised to SOMA_ABS_MIN_INTENSITY=" + SOMA_ABS_MIN_INTENSITY);
    somaThreshLow = SOMA_ABS_MIN_INTENSITY;
}
print("Soma threshold: " + somaThreshLow + " – 255" +
      "  (top " + SOMA_TOP_PERCENT + "% brightest pixels)");
setThreshold(somaThreshLow, 255);
setOption("BlackBackground", true);
run("Convert to Mask");
run("Fill Holes");

run("Set Measurements...", "area centroid shape redirect=None decimal=3");
run("Analyze Particles...",
    "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
    " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 show=Masks display exclude clear");

somaArea  = 0;
somaCount = nResults;
largestIdx = -1;

if (somaCount > 0) {
    // Always keep only the single largest candidate — there is exactly one soma
    // per image. Discarding smaller blobs eliminates bright debris that passed
    // the circularity/size filters.
    for (r = 0; r < nResults; r++) {
        a = getResult("Area", r);
        if (a > somaArea) { somaArea = a; largestIdx = r; }
    }
    if (somaCount > 1) {
        print("Soma: " + somaCount + " candidate(s) found — keeping largest only (" +
              somaArea + " px²). Discarding " + (somaCount - 1) + " smaller blob(s).");
    } else {
        print("Soma detected — Area: " + somaArea + " px²");
    }
} else {
    somaArea = 0;
    print("WARNING: No soma detected.");
    print("  → Try raising SOMA_TOP_PERCENT (currently " + SOMA_TOP_PERCENT + ")");
    print("  → Try lowering SOMA_CIRCULARITY_MIN (currently " + SOMA_CIRCULARITY_MIN + ")");
    print("  → Try lowering SOMA_ABS_MIN_INTENSITY (currently " + SOMA_ABS_MIN_INTENSITY + ")");
}

// Rebuild the particle mask keeping only the largest blob.
// Analyze Particles with "show=Masks" already produced "Mask of soma_detect";
// if there were multiple candidates we need to blank all but the largest one.
selectWindow("soma_detect");
close();

somasMaskName = "Mask of soma_detect";
if (isOpen(somasMaskName)) {
    selectWindow(somasMaskName);
    rename("soma_mask");

    // If more than one candidate was found, keep only the largest ROI.
    if (somaCount > 1 && largestIdx >= 0) {
        // Re-run Analyze Particles into the ROI manager to get individual ROIs.
        selectWindow("soma_mask");
        run("Duplicate...", " ");
        rename("soma_mask_tmp");
        roiManager("reset");
        run("Analyze Particles...",
            "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
            " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 add exclude clear");
        // Blank the mask, then fill only the largest ROI back in.
        selectWindow("soma_mask");
        run("Select All");
        setForegroundColor(0, 0, 0);
        fill();
        run("Select None");
        if (roiManager("count") > largestIdx) {
            roiManager("select", largestIdx);
            setForegroundColor(255, 255, 255);
            fill();
            run("Select None");
        }
        roiManager("reset");
        close("soma_mask_tmp");
    }
} else {
    selectWindow("work");
    run("Duplicate...", " ");
    run("Multiply...", "value=0");
    rename("soma_mask");
    print("WARNING: Soma mask creation failed — using blank mask.");
}

selectWindow("soma_mask");
for (e = 0; e < SOMA_ERODE_PASSES;  e++) { run("Erode");  }
for (d = 0; d < SOMA_DILATE_PASSES; d++) { run("Dilate"); }

close("Results");

// ── STEP 2: Isolate Processes ─────────────────────────────────────────────────
selectWindow("work");
run("Duplicate...", " ");
rename("processes");

imageCalculator("Subtract create", "processes", "soma_mask");
selectWindow("Result of processes");
rename("processes_no_soma");
close("processes");

// Contrast-stretch to lift dim distal processes
selectWindow("processes_no_soma");
run("Enhance Contrast", "saturated=" + CONTRAST_SATURATE);
run("Apply LUT");
print("Contrast stretch: saturated=" + CONTRAST_SATURATE + "%");

if (PROCESS_BLUR_SIGMA > 0) {
    run("Gaussian Blur...", "sigma=" + PROCESS_BLUR_SIGMA);
}

// Threshold
if (PROCESS_FIXED_THRESHOLD > 0) {
    setThreshold(PROCESS_FIXED_THRESHOLD, 255);
    print("Process threshold: fixed=" + PROCESS_FIXED_THRESHOLD);
} else {
    setAutoThreshold(PROCESS_THRESHOLD_METHOD + " dark no-reset");
    getThreshold(pLow, pHigh);
    print("Process threshold: " + pLow + " – " + pHigh +
          "  (method: " + PROCESS_THRESHOLD_METHOD + ")");
    if (pLow < 0 || (pLow == 0 && pHigh == 255)) {
        print("WARNING: threshold degenerate — try PROCESS_FIXED_THRESHOLD=30");
    }
}
setOption("BlackBackground", true);
run("Convert to Mask");
for (d = 0; d < PROCESS_DESPECKLE_PASSES; d++) { run("Despeckle"); }

// ── STEP 3: Skeletonize ───────────────────────────────────────────────────────
// Single skeletonize — no prune step. At small image sizes (< 200px),
// "shortest branch" pruning removes real fine process tips, not just noise.
// Manual cleanup with the brush tool is more reliable for this image size.
run("Skeletonize (2D/3D)");
rename("Skeleton");

// ── STEP 4: Composite Preview ─────────────────────────────────────────────────
// Analyze Skeleton is run here solely to produce the Tagged skeleton colormap
// for the composite preview — the Results table it generates is not needed and
// is discarded immediately. Edit_Finalize.ijm runs its own separate measurement
// on the final pruned skeleton after the user accepts their edits.
run("Analyze Skeleton (2D/3D)", "prune=none");
close("Results");

if (isOpen("Tagged skeleton")) {
    duplicateMicrogliaChannel(sourceName, "source_8bit");
    run("Grays");

    run("Merge Channels...",
        "c1=[Tagged skeleton] c2=[source_8bit] create keep");
    close("Tagged skeleton");
    close("source_8bit");
    if (isOpen("Composite")) {
        selectWindow("Composite");
        run("Set... ", "zoom=" + zoom + " x=0 y=0");
    }
}

selectWindow(sourceName);
run("Set... ", "zoom=" + zoom + " x=0 y=0");
selectWindow("Skeleton");
run("Set... ", "zoom=" + zoom + " x=0 y=0");

close("soma_mask");
close("processes_no_soma");
close("work");
