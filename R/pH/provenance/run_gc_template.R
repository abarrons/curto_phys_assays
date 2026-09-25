### Run file for the consolidated 384-well pH-assay template ###################
#
# Drives R/pH/provenance/report_sources/GC_template.Rmd. Paths are resolved with
# here::here(); place raw plate-reader CSVs under data-raw/pH/ (git-ignored).
#
# Edit the settings below and source this file (or run interactively).
###############################################################################

# ---- Settings ---------------------------------------------------------------

# Set the names of the strains in this plate (one per strain row A..O).
# Repeat a strain to encode in-plate replicates; the template computes the
# replicate index when `replicates = "auto"`.
S1  <- "Wood-1"     # Strain in Row A
S2  <- "Wood-2"     # Strain in Row B
S3  <- "Wood-11"    # Strain in Row C
S4  <- "Wood-31"    # Strain in Row D
S5  <- "Wood-46"    # Strain in Row E
S6  <- "Wood-47"    # Strain in Row F
S7  <- "Wood-52"    # Strain in Row G
S8  <- "Pine-20"    # Strain in Row H
S9  <- "Desert-30"  # Strain in Row I
S10 <- "Mmlr14-006" # Strain in Row J
S11 <- "Mcba15-009" # Strain in Row K
S12 <- "Mcba15-003" # Strain in Row L
S13 <- "23G3A05"    # Strain in Row M
S14 <- "23G1B05"    # Strain in Row N
S15 <- "Wood-1"     # Strain in Row O

strains <- c(S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15)

raw_file <- "data-raw/pH/pHassay_110725_rep2.csv"  # relative to project root
date     <- "2025-11-07"

# ---- Render -----------------------------------------------------------------

rmarkdown::render(
  input = here::here("R/pH/provenance/report_sources/GC_template.Rmd"),
  output_file = stringr::str_glue(
    here::here("output/reports/pH_assay_Report_{date}.html")
  ),
  params = list(
    raw_file      = raw_file,
    date          = date,
    strains       = strains,
    replicates    = "auto",   # "auto", "none", or an integer vector
    blank_method  = "match",  # "match" (by time+pH) or "mean"
    drop_neg_ph   = NULL,     # e.g. c(6.2, 6.5) if some blanks show growth
    offset_wells  = NULL,     # wells to baseline-offset (condensation)
    problem_wells = NULL,     # wells to force r = k = 0
    high_k_action = "zero",   # "zero" or "rescue" implausibly high k
    blank_baseline = 0.085
  )
)

# ---- Example: no in-plate replicates ----------------------------------------
#
# S1  <- "35G1A08"  # Strain in Row A
# S2  <- "23D06"    # Strain in Row B
# S3  <- "35G2B04"  # Strain in Row C
# S4  <- "23G1B05"  # Strain in Row D
# S5  <- "35G2A07"  # Strain in Row E
# S6  <- "28D03"    # Strain in Row F
# S7  <- "26G3B03"  # Strain in Row G
# S8  <- "23G1B10"  # Strain in Row H
# S9  <- "25D05"    # Strain in Row I
# S10 <- "26G4B12"  # Strain in Row J
# S11 <- "28G1A01"  # Strain in Row K
# S12 <- "28G4B03"  # Strain in Row L
# S13 <- "23G4B11"  # Strain in Row M
# S14 <- "25G2A02"  # Strain in Row N
# S15 <- "35G3B04"  # Strain in Row O
# strains <- c(S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15)
# rmarkdown::render(
#   input = here::here("R/pH/provenance/report_sources/GC_template.Rmd"),
#   output_file = stringr::str_glue(
#     here::here("output/reports/pH_assay_Report_{date}.html")),
#   params = list(raw_file = raw_file, date = date, strains = strains,
#                 replicates = "none")
# )
