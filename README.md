# Welcome to SkeleSketch!

**An Open-Source Tool for Quantifying Microglial Morphology in Fiji/ImageJ**

SkeleSketch is a semi-automated pipeline for reconstructing individual microglia and extracting morphometric features (e.g., soma size, branch length, branching complexity) from standard 2D epifluorescence images. It combines automated skeletonization and soma segmentation with an optional, quick manual correction step. It runs entirely within Fiji, needs only standard computing resources, and exports results to Excel for downstream analysis.

It is built for labs that want reproducible, single-cell morphometrics without confocal imaging, proprietary software, or coding.

## Installation

1. Download this repository and unzip it. Place the unzipped `SkeleSketch Macros` folder in:

   ```
   Fiji.app > scripts > Plugins
   ```

2. In Fiji, go to **Help > Update... > Manage Update Sites**. Enable all of the following, then click **Apply Changes**:
   - ImageJ
   - Fiji
   - Java-8
   - ResultsToExcel

3. Restart Fiji (close and reopen).

4. Run the Welcome macro once to install the keyboard shortcuts:

   ```
   Plugins > SkeleSketch Macros > Welcome
   ```

   This registers **F1** (Capture Images) and **F2** (Edit Finalize) and opens a welcome dialog. The Welcome macro also contains the full documentation, including tunable parameter settings and troubleshooting advice.

## How to use

SkeleSketch has two steps: **F1** captures individual cells from a full image, and **F2** skeletonizes each cell, detects the soma, and exports measurements.

### F1: Capture Images

1. Open your full image via **File > Import > Bio-Formats**.
2. Make preprocessing adjustments as needed, then press **F1**:
   - **Convert to grayscale:** Image > Lookup Table > Grays
   - **Adjust bit depth:** convert to 16-bit via Image > 16-bit
   - **Invert background:** make sure the background is dark via Image > Lookup Table > Invert LUT
   - **Increase contrast:** use Image > Adjust > Brightness/Contrast to improve detection of dim processes
3. Draw around each cell with the **polygon tool** and press **Space** to capture it.
4. Press **Shift** when done. Files are saved automatically.

Each cell gets its own subfolder, and a scale bar is optionally overlaid onto each saved crop and the labeled overview.

### F2: Edit & Finalize

1. Open a captured cell image and press **F2**. The macro skeletonizes the cell and detects the soma automatically.
2. **Skeleton stage:** edit the skeleton with the brush tool. Set the foreground color (**Edit > Options > Colors**) to:
   - **Black** to remove excess skeleton parts
   - **White** to add missing parts
3. Press **Space** to re-skeletonize and refresh the preview.
4. Press **Shift** when the skeleton looks right. This moves on to the soma stage.
5. **Soma stage:** the same brush pattern, now editing the soma mask. The Composite window shows the soma mask in red (channel 1, the one you edit) and the cell in green (channel 2, for reference).
   - **White brush** adds to the soma; **black brush** erases from it.
   - Press **Space** to sync your edits and see live stats (area, circularity, aspect ratio, solidity) in the Log.
   - Press **Shift** to accept the soma, save the outputs, and advance.

If no soma is detected automatically, the mask starts blank. Paint it with the white brush, or press Shift to accept an empty soma.

### Key summary

| Key | Action |
|-----|--------|
| **F1** | Capture Images |
| **F2** | Edit & Finalize |
| **Space** | F1: capture the outlined cell. F2: refresh the skeleton preview or sync soma edits. |
| **Shift** | F1: finish and save. F2: accept the current stage and move on. |
| **Brush (black / white)** | Remove from / add to the skeleton or soma mask |

## Output organization

Everything for one source image lives in a single folder created by F1. Each cell's images stay together in a numbered subfolder, and one combined Excel file sits at the top.

```
BaseName-Images/
  BaseName-Labeled.tif        (overview with numbered annotations)
  BaseName-Base.tif           (original image)
  BaseName-Data.xlsx          (Summary + Detailed sheets, all cells)
  BaseName-1/
    BaseName-1.tif                   (the crop, saved by F1)
    BaseName-1(Skeleton).tif         (saved by F2)
    BaseName-1(Tagged-Skeleton).tif  (saved by F2)
    BaseName-1(Composite).tif        (saved by F2)
    BaseName-1(Soma-Mask).tif        (saved by F2)
    BaseName-1(Soma-Overlay).tif     (saved by F2)
  BaseName-2/
    ... (same pattern)
```

## Excel output

Each batch writes one file, `BaseName-Images/BaseName-Data.xlsx`, with two sheets. Values are in µm / µm² when the image is calibrated.

**Summary** (one row per cell):

`Cell_ID`, `Soma_Area_um2`, `Soma_Circularity`, `Soma_AR`, `Soma_Solidity`, `Num_Branches`, `Total_Branch_Length_um`, `Avg_Branch_Length_um`, `Max_Branch_Length_um`, `Num_Junctions`, `Num_Endpoints`, `Num_Triple_Points`, `Num_Quadruple_Points`, `Ramification_Index`, `Junction_Density`, `Endpoint_Density`, `Avg_Span_Ratio`, `Branch_Density`, `Complexity_Index`

**Detailed** (one row per branch):

`Cell_ID`, `Skeleton_ID`, `Branch_Length_um`, `V1x_um`, `V1y_um`, `V2x_um`, `V2y_um`, `Euclidean_Distance_um`, `Running_Avg_Length_um`, `Branch_Type`

> Close the Excel file before pressing Shift in F2, otherwise data cannot be written.

## Derived metrics

<table>
  <thead>
    <tr>
      <th width="15%">Category</th>
      <th width="25%">Metric</th>
      <th width="40%">Definition</th>
      <th width="20%">Expected change with reduced ramification</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td rowspan="2" valign="top"><b>Soma</b></td>
      <td>Soma area</td>
      <td>Area of the segmented soma (µm²)</td>
      <td>Increases</td>
    </tr>
    <tr>
      <td>Soma shape (circularity, aspect ratio, solidity)</td>
      <td>Circularity (0–1; 1 = perfect circle); aspect ratio (major axis / minor axis); solidity (area / convex hull area)</td>
      <td>Little change</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td rowspan="3" valign="top"><b>Process extent</b></td>
      <td>Total branch length</td>
      <td>Summed length of all skeleton branches (µm)</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Maximum branch length</td>
      <td>Length of the longest branch (µm)</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Average branch length</td>
      <td>Mean length of skeleton branches (µm)</td>
      <td>Decreases</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td rowspan="6" valign="top"><b>Branching</b></td>
      <td>Number of branches</td>
      <td>Count of skeleton branches</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Junctions, triple points, quadruple points</td>
      <td>Counts of branch points in the skeleton; triple and quadruple points are junctions where three or four branches meet</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Number of endpoints</td>
      <td>Count of branch termini</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Branch density</td>
      <td>Number of branches / soma area</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Junction density</td>
      <td>Number of junctions / total branch length</td>
      <td>Increases</td>
    </tr>
    <tr>
      <td>Endpoint density</td>
      <td>Number of endpoints / total branch length</td>
      <td>Increases</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td rowspan="3" valign="top"><b>Composite</b></td>
      <td>Ramification index</td>
      <td>Total branch length / soma area</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Complexity index</td>
      <td>(Number of endpoints × total branch length) / soma area</td>
      <td>Decreases</td>
    </tr>
    <tr>
      <td>Average span ratio</td>
      <td>Mean, across branches, of the Euclidean distance between a branch's end vertices divided by its path length (0–1; 1 = straight, &lt;1 = tortuous)</td>
      <td>Slightly increases</td>
    </tr>
  </tbody>
</table>
