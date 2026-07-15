# Intel Laminar RM1 — Conjugate Heat Transfer Validation in OpenFOAM

A five-region conjugate heat transfer (CHT) simulation of the **Intel Laminar RM1** stock CPU cooler (radial downblow, copper core + 120 aluminum blades), built and validated in **OpenFOAM v2512** (`chtMultiRegionSimpleFoam`) against published experimental thermal data.

The entire case — geometry, meshing, interface coupling, boundary conditions, and post-processing — runs on a **base M2 MacBook Air (8 GB RAM, 4 performance cores)**. Total mesh size is ~2.3M cells.

## Validation Results

| Run | Die power | Predicted die T (max) | Thermal resistance | Experimental anchor | Agreement |
|---|---|---|---|---|---|
| 65 W TDP case | 59 W | 331.77 K (58.62 °C) | **0.638 K/W** | 0.617 K/W (±6%) | **+3.4%** |
| 81 W blind prediction | 81 W | 345.93 K (72.78 °C) | 0.639 K/W | Bracket [70, 73] °C → R ∈ [0.617, 0.654] K/W | **Inside bracket** |

- The 59 W run also lands **−1.3%** against the HWCooling 65 W TDP-limited wind-tunnel test (controlled 21 °C intake, known CPU stepping) — the stronger of the two anchors.
- The 81 W anchor derives from 电脑吧评测室 test data (via 163.com / TechPowerUp): 70 °C temporal average / 73 °C peak over an 8-minute AIDA64 FPU load at 81 W average / 89 W peak, 20 °C ambient. Integer-degree reporting and the ±8 W power fluctuation smear the anchor by roughly ±2.6%.
- Convergence verified by Aitken / 3-parameter exponential extrapolation on the die-max temperature and interface flux series (coupling time constant τ ≈ 1,460 iterations; residual drift at stop 0.037 K).
- **Energy conservation:** 80.80 W of 81 W accounted for through the full interface chain. Total pair mismatch 0.27% (0.18% at ihs↔core AMI + 0.09% at core↔fins), which is the floor set by AMI interpolation — every conformal pair conserves to <0.1 W.

The framing is deliberate: **calibrated at 59 W, blind-predicted at 81 W**, with agreement inside both anchors' uncertainty at both points.

## Model Description

### Thermal stack (5 coupled regions)

```
        fan plenum (swirl inlet, y = 29.3–50.3 mm)
                 │  air, downblow
   ┌─────────────▼──────────────┐
   │  fins   Al 6061 (k=167)    │  120 blades, r = 17.5–50 mm, 3° pitch
   │                            │  0.5 mm blade / ~0.35 mm gap
   ├──── core–fin joint ────────┤  40 µm, k = 0.5 W/m·K   (press-fit contact)
   │  core   Cu (k=390)         │  r = 0–17.5 mm, y = 3.3–28.3 mm
   ├──── TIM2 ──────────────────┤  100 µm, k = 4 W/m·K    (paste)
   │  IHS    Cu (k=390)         │  y = 0.8–3.3 mm
   ├──── TIM1 ──────────────────┤  75 µm, k = 50 W/m·K    (solder/high-k TIM)
   │  die    Si (k=100)         │  y = 0–0.8 mm, 81 W applied at die_bottom
   └────────────────────────────┘
```

All TIM/joint layers are **zero-thickness thermal resistances** (`thicknessLayers`/`kappaLayers` on the coupled boundary conditions), not meshed volumes. The layer specification is **byte-identical on both sides of every coupled pair** — this is mandatory; asymmetric specs produce mismatched series conductances and non-conservative phantom flux at every interface (this bug alone accounted for ~100 W of invented energy before it was found).

### Flow model

- **Laminar.** The fin channels run at Re ≈ 300–500 (gap ~0.35 mm); this is unambiguously laminar. k-ω SST was tested and rejected — it inflates the channel heat transfer coefficient ~40× and drives the die far below the experimental anchor.
- **Inlet:** `swirlFlowRateInletVelocity` on `plenum_top` — 0.01 m³/s (36 CMH) with 1200 RPM effective swirl (assumed 40% of the 3000 RPM fan blade speed; an Euler-turbomachinery estimate brackets the effective value at 1000–1600 RPM). The 36 CMH operating point comes from intersecting the fan P-Q curve with the computed system impedance.
- **Outlet:** `pressureInletOutletVelocity` on the outer rim (tolerates transient backflow).
- **Fluid thermo:** `heRhoThermo` / `perfectGas` / `sensibleEnthalpy` — compressible, so buoyancy and density variation with temperature are captured.
- **Heat load:** `externalWallHeatFluxTemperature` with `mode power; Q $dieInputPower` on `die_bottom`. All other external surfaces adiabatic (documented as a ~0.2 K third-order approximation).
- Radiation disabled (`qr none` on coupled BCs) — negligible at these temperatures.

### Interface coupling

| Interface | Mapping | Layer | Notes |
|---|---|---|---|
| die ↔ ihs | `nearestPatchFace` (conformal) | TIM1: 75 µm / 50 W/m·K | |
| ihs ↔ core | **AMI** (`faceAreaWeightAMI` / `nearestPatchFaceAMI`) | TIM2: 100 µm / 4 W/m·K | 6960 ↔ 6000 faces; the only imperfect-coverage pair (min weights 0.682 / 0.504) |
| core ↔ fins | `nearestPatchFace` (conformal) | joint: 40 µm / 0.5 W/m·K | |
| fins ↔ fluid | `nearestPatchFace` (conformal) | none | The natural conservation control pair |

All coupled patches are `mappedWall` with `compressible::turbulentTemperatureRadCoupledMixed`. AMI is used **only** where two independently-built meshes meet; every split-half interface from `splitMeshRegions` is conformal by construction and uses `nearestPatchFace`.

### Mesh

- **die, ihs:** structured `blockMesh` bricks (die/IHS are square — they cannot share the cylindrical symmetry of the sink).
- **core:** structured `blockMesh` O-grid around a butterfly-style center — no polar axis singularity, no small-determinant cells near r = 0.
- **fin_fluid:** a butterfly-centered polar `blockMesh` background (Cartesian hub square transitioning to annular rings — kills the r→0 cell collapse), carved by a single `snappyHexMesh` pass against `Radial_Fins.stl` (surface level (2 2), feature-edge snapping, `strictRegionSnap`), then separated into `fins` (solid) and `fluid` cellZones by `splitMeshRegions -cellZones`.
- One known snappy failure mode is handled permanently in the pipeline: snappy can misclassify a sliver of fin-root contact faces at r = 17.5 mm into an orphan `fins` wall patch (880 faces ≈ 2.1% of the contact annulus in one run → a measurable 1.28 W energy leak). `Allboundary` now folds any such orphan patch back into `fins_to_core` via `createPatch`, so the defect fails loudly instead of silently leaking energy.

### Solver settings that matter

- `chtMultiRegionSimpleFoam`, steady-state SIMPLE, 4-way Scotch decomposition.
- **Solid enthalpy relaxation 0.99** — 0.5 causes slow linear creep instead of the correct exponential decay toward steady state; solids are linear and need almost no relaxation.
- Fluid: U 0.5, h 0.99, p_rgh 0.5, rho 0.3; `p_rgh relTol 0` for clean mass conservation; solid h tolerance 1e-7 / relTol 0.
- Solids use `div none` (pure conduction); fluid carries the bounded convection set.
- Expect ≥ ~1,500 iterations minimum before reading anything as converged — the inter-region coupling time constant on this mesh is ≈ 1,440–1,460 iterations. Runs shorter than τ sample a relaxation transient, not the answer.

## Repository Structure

```
├── 0.orig/                  # pristine initial/boundary fields per region (die, ihs, core, fins, fluid)
├── constant/
│   ├── caseSettings         # single source of truth: power, flow rate, TIM specs, ambient, cores
│   ├── regionProperties     # fluid (fluid) / solid (core die ihs fins)
│   ├── triSurface/          # Radial_Fins.stl (+ low/med variants), Core.stl, IHS.stl, Microchip_Die.stl, eMesh files
│   └── g
├── system/
│   ├── controlDict          # incl. wallHeatFlux + surfaceFieldValue function objects (the energy ledger)
│   ├── decomposeParDict     # 4 subdomains, scotch (synced per-region by the scripts)
│   ├── <region>/            # per-region blockMeshDict, fvSchemes, fvSolution, decomposeParDict
│   ├── fin_fluid/           # background blockMeshDict + snappyHexMeshDict
│   ├── ihs/ fluid/ fins/    # topoSetDict / createPatchDict for interface patch construction
│   └── surfaceFeatureExtractDict
├── templates/               # thermophysicalProperties, radiationProperties, turbulenceProperties per region
├── monitorFlux.gp           # live gnuplot monitors (see below)
├── monitorResiduals.gp
├── monitorTemps.gp
├── Allblockmesh … Allrestart  # pipeline scripts (see next section)
└── project.foam             # ParaView anchor
```

`constant/caseSettings` is `#include`d by every `0.orig` field file — power, flow rate, swirl RPM, ambient temperature, and all TIM thickness/conductivity pairs are changed in exactly one place.

## How to Run

Requires OpenFOAM v2512 (ESI fork; on Apple Silicon, [gerlero's arm64 build](https://github.com/gerlero/openfoam-app) is what this case was developed on). Source your OpenFOAM environment first.

```sh
./Allrun        # full pipeline, end to end
```

or stage by stage, which is how the case was actually developed:

| Script | What it does |
|---|---|
| **`Allblockmesh`** | Runs `Allclean`, then `blockMesh` + `checkMesh -allGeometry` for each structured region (`core`, `ihs`, `die`) and the `fin_fluid` background. Logs to `logs/`. |
| **`Allsnappy`** | `snappyHexMesh -region fin_fluid -overwrite` (carves the 120 blades from `Radial_Fins.stl`), then `splitMeshRegions -cellZones -overwrite` to separate `fins` and `fluid`, then a final `checkMesh -allRegions -allGeometry`. |
| **`Allboundary`** | Wires all region-interface patches into coupled `mappedWall` pairs. Builds `ihs_to_core` and `fluid_to_core` patches via `topoSet` + `createPatch`, folds any snappy-orphaned fin-root sliver patch back into `fins_to_core`, then sets only the semantic coupling keys (`type`, `sampleMode`, `sampleRegion`, `samplePatch`, `AMIMethod`) by patch name through `foamDictionary` — `nFaces`/`startFace` are never touched, so re-running is idempotent. |
| **`Allthermo`** | Copies `thermophysicalProperties` + `radiationProperties` from `templates/<region>/` into `constant/<region>/` for all five regions, plus the fluid `turbulenceProperties`. |
| **`Allsolve`** | **Cold start.** Wipes solve data (`cleanSolveData`), restores fields from `0.orig`, `decomposePar -allRegions -force`, `mpirun -np <N> chtMultiRegionSimpleFoam -parallel`, `reconstructPar -allRegions -latestTime`. Core count is read from `decomposeParDict`, not hardcoded. Everything streams live to the terminal *and* to `logs/` via `tee` — no wrapper functions, no silent redirects. |
| **`Allrestart`** | **Warm restart** — continues from `latestTime` without touching field history. Use this (never `Allsolve`) to extend a run. |
| **`Allclean`** | Removes all generated meshes (`constant/<region>`), `0/`, `processor*`, `logs/`, `postProcessing/`. Back to a pristine checkout. |
| **`cleanSolveData`** | Lighter clean: removes only solve artifacts (`0/`, `processor*`, `postProcessing/`, solver logs), keeping the mesh. Called by `Allsolve`. |
| **`Allrun`** | `Allblockmesh → Allsnappy → Allboundary → Allthermo → Allsolve` in sequence. |

Two operational rules learned the hard way, baked into the scripts but worth knowing:

1. **The solver reads `processor*/`, not `constant/` or `0/`.** Any edit to fields or boundary files after decomposition is invisible until you re-decompose. `decomposePar -allRegions` in v2512 requires a `system/<region>/decomposeParDict` per region (no fallback to the global dict once per-region `system/` dirs exist) — the scripts sync one authoritative copy into each region.
2. **To change die power on a warm restart**, don't reconstruct/re-decompose — `sed` the resolved heat-flux literal directly in the processor time directories (e.g. 59 W: `q=362519.2` → 81 W: `q=497695.3` W/m²) and verify both sides with `foamDictionary` before relaunching. Editing `caseSettings` does nothing to already-decomposed fields.

### Live monitoring

Three gnuplot scripts watch the run in real time (self-refreshing `pause`-loop idiom):

- `monitorFlux.gp` — integrated `wallHeatFlux` per interface patch (die_bottom, die_to_ihs, ihs_to_core, fins_to_core, fluid_to_fins, …). **This is the primary convergence signal**: every coupled pair must (a) balance its partner and (b) sum to the applied power. Flux closure converges later and more honestly than temperature curves.
- `monitorTemps.gp` — die max temperature trend.
- `monitorResiduals.gp` — per-region residuals. Note: solid enthalpy residuals plateauing at 1e-2–1e-3 is a known artifact of `mappedWall` coupled BCs, not divergence.

The `wallHeatFlux` function objects in `controlDict` write on `writeControl writeTime` (co-located with solution writes); `surfaceFieldValue` integrals sample every 20 steps into `postProcessing/`.

### Post-processing

`paraFoam` / ParaView via `project.foam` (multi-region: load each region's decomposed or reconstructed case). Useful diagnostics that earned their keep during development: thresholding `wallHeatFlux` at extreme values to locate defective interface faces, and `foamToVTK -faceSet` exports for programmatic face-set analysis.

## Verification Methodology (what "validated" means here)

- **Uniform-field autopsy:** before any long solve on a freshly coupled mesh, run one iteration on a uniform temperature field — every coupled pair must read ≈ 0 W. This single test caught the un-normalized AMI interpolation defect (Σw = 0.504 faces reading a 148 K phantom neighbor on a uniform 294 K field) that had a cold start destroying 69 W at ihs↔core.
- **Energy ledger:** integrated flux at every interface, both sides, every write. A structural imbalance is a bookkeeping bug to be fixed regardless of magnitude (the 1.28 W core↔fins leak was traced to 880 misclassified faces = 2.08% of contact area, predicting 1.23 W — matched to within 4%); only irreducible AMI interpolation error (0.27% total here) is accepted as model-form.
- **Convergence:** Aitken Δ² / 3-parameter exponential extrapolation on die-max and flux series rather than eyeballing flatness; runs judged against the measured coupling time constant.
- **Error taxonomy:** model-form error (documented, accepted — e.g. adiabatic external walls, assumed swirl fraction) vs. bookkeeping error (fixed unconditionally). The two are never traded against each other.

## Fusion 360 Bracketing Study (pre-OpenFOAM, qualitative)

Before the OpenFOAM build, Fusion 360's EC thermal solver was used to bracket the expected die temperature (81 W, bonded contacts, TIM1 = 50 W/m·K, TIM2 = 6 W/m·K):

- All-copper sink (k = 390): die 73.2 °C — lower bound
- All-aluminum sink (k = 167): die 78.5 °C — upper bound
- The system is **convection-limited** above k ≈ 230 W/m·K (copper vs. 230-grade Al differ by ~0.2 °C); the fin alloy is a ~5 °C second-order lever, subordinate to airflow and contact-resistance uncertainty.

A re-solve with identical inputs later shifted results by 4–6 °C (mesh-scatter, non-reproducible), which is why Fusion was demoted to **qualitative bracketing only** and the quantitative source-stack ΔT claim rests entirely on the OpenFOAM model with analytic contact resistances. The Fusion bracket (real bi-metal cooler expected ~77–78 °C) is consistent with the final OpenFOAM 72.78 °C prediction given the bracketing runs' stiffer TIM2 and bonded joints.

## Known Limitations / Open Items

- Die temperature reported as **volume max**; the 81 W anchor's 70 °C is a temporal-mean DTS reading — a die volume-average extraction (one `postProcess` call) would tighten the comparison basis.
- TIM2 bond-line thickness (100 µm used) sensitivity not swept (50/75 µm cases pending).
- Inlet swirl fraction (40% of blade speed) is an assumption; Euler analysis brackets 1000–1600 RPM effective.
- A ~93 W unrestricted-mode bracketing run against the HWCooling dataset is the highest-value remaining validation point.
- External case surfaces adiabatic (~0.2 K effect, documented).
- ihs↔core AMI coverage is imperfect (min Σw 0.504 on edge faces) — the 0.27% flux non-conservation floor lives here.

## Hardware / Software

- OpenFOAM **v2512** (ESI/openfoam.com fork), Apple Silicon arm64 build
- Apple M2 MacBook Air, 8 GB RAM — 4-way MPI on performance cores; practical ceiling ~3.4M cells
- ParaView 6.1.1 (native arm64), gnuplot, Python (mesh verification: signed hex volumes, face-normal audits, VTK face-set analysis)
- Geometry: Fusion 360 → STL export (mm units, `scale 0.001` in dictionaries)
