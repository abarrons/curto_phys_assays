# Analysis scripts

The run instructions for these scripts live in the project-root
[`USAGE.md`](../USAGE.md), and the repository overview is in
[`README.md`](../README.md).

Quick map of what's here:

- `pH/01_ph_curves_analysis.Rmd` — pH assay (run first)
- `temp/01_temp_performance_curves.Rmd` — temperature assay (needs pH `output/rds/`)
- `biofilm/01_biofilm.Rmd` — biofilm assay (independent)
- `shared/01_strain_assay_summary.Rmd` — cross-assay summary (run last)
- `pH/potassium_phosphate_buffer.R` — buffer-recipe helper (bench prep)
- `*/provenance/` — how the committed `GC_values_*.txt` inputs were generated from
  raw plate reads (only needed to add/reprocess runs; see `USAGE.md`)
