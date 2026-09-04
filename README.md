# Welcome to SkeleSketch!

**An Open-Source Tool for Quantifying Microglial Morphology in Fiji/ImageJ**

SkeleSketch is a semi-automated pipeline for reconstructing individual microglia and extracting morphometric features (e.g., soma size, branch length, branching complexity) from standard 2D epifluorescence images. It combines automated skeletonization and soma segmentation with an optional, quick manual correction step. It runs entirely within Fiji, needs only standard computing resources, and exports results to Excel for downstream analysis.

It is built for labs that want reproducible, single-cell morphometrics without confocal imaging, proprietary software, or coding.

## How It Works

The workflow is two keystrokes:

- **`F1` — Capture Images.** Open a full field, trace around each microglia with the polygon tool, and press `Space` to save each as its own numbered crop. Each cell gets its own subfolder.
- **`F2` — Edit & Finalize.** On a captured cell, SkeleSketch automatically skeletonizes the processes and detects the soma. Optionally correct the skeleton and soma mask with the brush (white to add, black to erase), then accept. Measurements are written to a per-folder Excel file, and the next cell opens automatically for batch processing.

## Installation

1. Place the unzipped `SkeleSketch` folder in `Fiji.app > scripts > Plugins`.
2. In Fiji, go to `Help > Update... > Manage Update Sites` and enable **ImageJ**, **Fiji**, **Java-8**, and **ResultsToExcel**, then click *Apply Changes*.
3. Restart Fiji.
4. Run `Plugins > SkeleSketch > README` once to install the `F1`/`F2` shortcuts.

Tested on Windows and macOS with Fiji (ImageJ 1.54p).

## Documentation

The bundled **README** macro (`Plugins > SkeleSketch > README`) documents the complete workflow, every tunable parameter and where to set it, the output folder structure and file-naming rules, channel selection, intensity handling, troubleshooting, and the metrics captured. Start there for anything beyond the quick start above.

## Citing SkeleSketch

If you use SkeleSketch in your work, please cite:

> Pascoe, L.A.\*, Masegosa, V.M.\*, Liu, S., Zhu, Q. SkeleSketch: An Open-Source Tool for Quantifying Microglial Morphology in Fiji/ImageJ. 

The accompanying paper describes the pipeline in detail and validates it against two labeling strategies (CX3CR1-GFP and Iba1) and the commercial platform Imaris, using an LPS-induced neuroinflammation model.

## License

See the `LICENSE` file in this repository.
