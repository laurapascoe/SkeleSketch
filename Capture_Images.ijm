/*
================================================================================
  Capture_Images.ijm
  Triggered by: F1
================================================================================
  Lets you draw rectangles around individual microglia cells on a base image,
  saving each crop as a numbered .tif. Also saves a labeled overview and the
  original base image into an organized folder.

  Controls:
    Space  →  Capture the current rectangle selection
    Shift  →  Finish capturing and close

  Output files saved to: <chosen directory>/<imageName>-Images/
    <name>-Labeled.tif                (overview with numbered annotations + scale bar)
    <name>-Base.tif                   (original image)
    <name>-1/<name>-1.tif, <name>-2/<name>-2.tif, ...
        (each cell crop, with scale bar, in its own numbered subfolder —
         F2 later adds that cell's skeleton/soma/composite outputs alongside it)

  Re-running F1 on the same base image (e.g. resuming a partially-captured
  image in a later session) automatically resumes numbering after the
  highest existing "<name>-N" subfolder instead of restarting at 1, so
  earlier captures are never overwritten. The Labeled/Base overview images
  are still overwritten each run and only reflect the current session.
================================================================================
*/

setTool("rectangle");

// ── Tunable Parameters ─────────────────────────────────────────────────────────
// Scale bar settings for saved images (keep in sync with Edit_Finalize.ijm)
SCALEBAR_WIDTH_UM  = 10;   // length of scale bar in microns
SCALEBAR_HEIGHT    = 4;    // thickness in pixels
SCALEBAR_FONT      = 14;   // label font size
SCALEBAR_COLOR     = "White";
SCALEBAR_LOCATION  = "Lower Right";

// ── Helper Functions ──────────────────────────────────────────────────────────

// Draws the standard scale bar using the SCALEBAR_* settings above.
function addScaleBar() {
    run("Scale Bar...",
        "width=" + SCALEBAR_WIDTH_UM +
        " height=" + SCALEBAR_HEIGHT +
        " thickness=" + SCALEBAR_HEIGHT +
        " font=" + SCALEBAR_FONT +
        " color=" + SCALEBAR_COLOR +
        " background=None location=[" + SCALEBAR_LOCATION + "] bold overlay");
}

// Derive a clean base name from the open image title (strip extension)
officialName = getTitle();
dotIdx = officialName.lastIndexOf(".");
if (dotIdx > 0) { officialName = officialName.substring(0, dotIdx); }

// Duplicate base image and create a labeled RGB copy for annotations
run("Duplicate...", " ");
rename(officialName + "-Labeled");
location = getDirectory("Select a directory to save the captured images");
folder = location + officialName + "-Images";
File.makeDirectory(folder);
run("RGB Color");

// ── Capture loop ─────────────────────────────────────────────────────────────
// Numbering doesn't blindly start at 1: if this base image was already
// (partially) captured in an earlier session, restarting at 1 would silently
// overwrite existing "<officialName>-N" subfolders - including any F2
// skeleton/soma output already saved inside them. So the folder is scanned
// for existing subfolders that match the naming pattern first, and numbering
// resumes right after the highest one found.
num = 1;
if (File.exists(folder)) {
    existingEntries = getFileList(folder);
    highestExisting = 0;
    cellPrefix = officialName + "-";
    for (e = 0; e < existingEntries.length; e++) {
        entryName = replace(existingEntries[e], "/", "");
        entryPath = folder + File.separator + entryName;
        if (File.isDirectory(entryPath) && startsWith(entryName, cellPrefix)) {
            suffix = substring(entryName, lengthOf(cellPrefix), lengthOf(entryName));
            n = parseInt(suffix);
            if (!isNaN(n) && n > highestExisting) {
                highestExisting = n;
            }
        }
    }
    if (highestExisting > 0) {
        num = highestExisting + 1;
        print("Existing captures found for \"" + officialName + "\" -- resuming at cell " + num + ".");
        showMessage("Resuming capture",
            "Found " + highestExisting + " cell(s) already captured for \"" + officialName + "\".\n \n" +
            "New cells will be numbered starting at " + num + " so nothing already\n" +
            "on disk gets overwritten.\n \n" +
            "Note: the labeled overview (\"-Labeled.tif\") only shows cells\n" +
            "captured in THIS session -- it will not include the rectangle\n" +
            "annotations from your earlier session when it's saved.");
    }
}

sessionCaptured = 0; // cells captured in this run, as distinct from `num`
                      // which may now resume above 1 (see Capture loop above)

print("========================================");
print("Draw a rectangle around each cell.");
print("  Space  → capture selection");
print("  Shift  → finish and save");
print("========================================");

while (true) {
    interruptMacro = isKeyDown("shift");
    captureMacro   = isKeyDown("space");

    // CAPTURE: save the selected crop and annotate the labeled image
    if (captureMacro) {
        setBatchMode("hide");
        getSelectionBounds(x, y, w, h);

        run("Duplicate...", " ");
        addScaleBar();

        // ── Each cell gets its own subfolder, e.g. <folder>/<name>-1/ ──────────
        // F2 (Edit_Finalize.ijm) later saves that cell's skeleton/soma/composite
        // outputs alongside this crop, in the same subfolder.
        cellName   = officialName + "-" + num;
        cellFolder = folder + "/" + cellName;
        File.makeDirectory(cellFolder);
        saveAs("Tiff", cellFolder + "/" + cellName + ".tif");
        close();

        setBatchMode("exit and display");
        print("Captured: " + officialName + "-" + num);

        // Draw rectangle outline + label number onto the Labeled image
        setFont("SansSerif", 28, "antialiased");
        setColor("red");
        drawRect(x, y, w, h);
        drawString("" + num, x + (2 * w / 5), y + (3 * h / 4));

        setKeyDown("none");
        num++;
        sessionCaptured++;
        wait(400); // debounce: prevents a single key-hold from triggering two captures
    }

    // STOP: add scale bar to labeled overview, save both overview images and exit
    if (interruptMacro) {
        setKeyDown("none");

        // Scale bar on labeled overview
        addScaleBar();

        saveAs("Tiff", folder + "/" + officialName + "-Labeled.tif");
        close();
        saveAs("Tiff", folder + "/" + officialName + "-Base.tif");
        close();

        print("Done — " + sessionCaptured + " cell(s) captured this session (" +
              (num - 1) + " total for this image).");
        wait(1000);
        close("Log");
        break;
    }
}

showMessage(
    "Capture complete!\n" +
    sessionCaptured + " cell image(s) saved this session\n" +
    "(" + (num - 1) + " total captured for this image so far).\n\n" +
    "Open each cell image and press [F2] to begin skeletonization.\n\n" +
    "Files saved to:\n" + folder
);
