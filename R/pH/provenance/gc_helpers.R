## gc_helpers.R -------------------------------------------------------------
## Reusable functions for analyzing raw 384-well plate-reader data from the
## pH growth-curve assay. Sourced by GC_template.Rmd (and usable interactively).
##
## The assay layout: 16 strain rows (A-P) x 24 pH columns, where columns map to
## pH 3.2 .. 10.2 in 0.3 steps. Row P (the 16th) holds the blank/negative wells.
##
## Every function is pure: it takes data in and returns data out, with no
## reliance on global variables. Optional correction steps default to
## off/neutral so a plain call reproduces the basic workflow.
## --------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(ggplot2)
  library(reshape2)
  library(lubridate)
  library(growthcurver)
})

# Null-coalescing helper (returns b when a is NULL); used by the template config.
`%||%` <- function(a, b) if (is.null(a)) b else a


## ---- Shared aesthetics ---------------------------------------------------

#' Plot theme used across the assay figures.
#'
#' Falls back to the default font family when `family` is not installed, so the
#' template knits on machines without the original "Futura Medium" font.
#'
#' @param family Font family to use, if available.
#' @return A ggplot2 theme object.
gc_apatheme <- function(family = "Futura Medium") {
  available <- family %in% c("", "sans", "serif", "mono") ||
    (requireNamespace("systemfonts", quietly = TRUE) &&
       family %in% systemfonts::system_fonts()$family)
  if (!available) family <- ""

  theme_bw() +
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.border = element_blank(),
      axis.line = element_line(),
      text = element_text(family = family)
    )
}

#' Categorical color palette for isolates (supports up to ~33 strains).
#' @return A character vector of colors.
gc_taxa_colors <- function() {
  c(
    "#CBD588", "#5F7FC7", "orange", "#DA5724", "#508578", "#CD9BCD",
    "#AD6F3B", "#673770", "#D14285", "#652926", "#C84248",
    "#8569D5", "#5E738F", "#D1A33D", "#8A7C64", "#599861", "red",
    "blue", "#483D8B", "gray", "darkcyan", "darkgoldenrod4", "green", "#8B0000",
    "darkgreen", "yellow", "lightblue", "forestgreen", "darkorange4", "purple",
    "salmon", "steelblue", "pink"
  )
}


## ---- Data loading --------------------------------------------------------

#' Read a raw plate-reader CSV and tidy its time column.
#'
#' @param path Path to the plate-reader CSV export.
#' @param drop_temp Drop the second column (temperature) when TRUE.
#' @return A data frame with `Time` (decimal hours) and one column per well.
gc_load_plate_reads <- function(path, drop_temp = TRUE) {
  data <- read.csv(file = path, header = TRUE, stringsAsFactors = FALSE)
  if (drop_temp) data <- data[, -2]
  data$Time <- period_to_seconds(hms(data$Time)) / 3600
  data
}


## ---- Plate map -----------------------------------------------------------

#' Build a plate map matching strain, pH, and replicate to each well.
#'
#' @param well_names Character vector of well IDs (the data columns after Time),
#'   in row-major order A1..A24, B1..B24, ...
#' @param strains Character vector of strain IDs, one entry per strain row
#'   (typically length 15). Repeat a strain to encode in-plate replicates.
#' @param ph_levels Numeric pH levels for the 24 columns.
#' @param replicates One of "auto" (compute a replicate index from repeated
#'   strain names), "none" (replicate = NA), or an integer vector giving the
#'   replicate number for each strain row (same length as `strains`).
#' @param neg_label Label for the blank/negative row appended after the strains.
#' @return A data frame with columns `strain`, `pH`, `replicate`, `well`.
gc_build_platemap <- function(well_names,
                              strains,
                              ph_levels = seq(3.2, 10.2, 0.3),
                              replicates = "auto",
                              neg_label = "NEG") {
  n_col <- length(ph_levels)
  n_row <- length(strains)

  # pH repeats across every occupied row plus the NEG row.
  phlist <- rep(ph_levels, n_row + 1)

  # One strain label per well, then a block of NEG wells.
  strainlist <- c(
    rep(strains, each = n_col),
    rep(neg_label, n_col)
  )

  # Replicate index per strain row.
  if (identical(replicates, "auto")) {
    f <- factor(strains, levels = unique(strains))
    rep_idx <- ave(seq_along(f), f, FUN = function(x) cumsum(!duplicated(x)))
  } else if (identical(replicates, "none")) {
    rep_idx <- rep(NA_integer_, n_row)
  } else {
    if (length(replicates) != n_row) {
      stop("`replicates` must be 'auto', 'none', or length(strains).",
           call. = FALSE)
    }
    rep_idx <- as.integer(replicates)
  }
  replicate <- factor(c(rep(rep_idx, each = n_col), rep(NA, n_col)))

  platemap <- data.frame(
    strain = strainlist,
    pH = phlist,
    replicate = replicate,
    stringsAsFactors = FALSE
  )

  if (length(well_names) != nrow(platemap)) {
    stop(
      sprintf(
        "well_names (%d) does not match strains x pH + NEG (%d).",
        length(well_names), nrow(platemap)
      ),
      call. = FALSE
    )
  }
  platemap$well <- well_names
  platemap
}


## ---- Reshape to long -----------------------------------------------------

#' Melt wide plate reads to long form and attach the plate map.
#'
#' @param data Wide data from [gc_load_plate_reads()].
#' @param platemap Plate map from [gc_build_platemap()].
#' @return Long data frame with `well`, `Time`, `value`, `strain`, `pH`,
#'   `replicate`.
gc_to_long <- function(data, platemap) {
  mdata <- reshape2::melt(data, id = "Time", variable.name = "well")
  mdata$well <- as.character(mdata$well)
  merge(mdata, platemap, by = "well", all.y = TRUE)
}


## ---- Background correction ----------------------------------------------

#' Subtract blank (NEG) readings from each well's OD.
#'
#' Method "match" subtracts, per time point and pH, the mean NEG reading at that
#' same time and pH (Method 1 in the original script). Method "mean" subtracts a
#' single per-pH mean blank averaged over time (Method 2).
#'
#' @param mdata_long Long data from [gc_to_long()].
#' @param method "match" or "mean".
#' @param neg_label Label identifying blank wells.
#' @param floor_zero Clamp negative corrected OD values to 0 when TRUE.
#' @param drop_neg_ph Numeric pH levels whose NEG wells should be excluded from
#'   the blank set (e.g. negatives that showed growth).
#' @return Long data frame of non-NEG wells with a corrected `OD` column.
gc_subtract_blanks <- function(mdata_long,
                               method = c("match", "mean"),
                               neg_label = "NEG",
                               floor_zero = TRUE,
                               drop_neg_ph = NULL) {
  method <- match.arg(method)

  neg <- mdata_long |> dplyr::filter(.data$strain == neg_label)
  if (!is.null(drop_neg_ph)) {
    neg <- neg |> dplyr::filter(!.data$pH %in% drop_neg_ph)
  }

  samples <- mdata_long |> dplyr::filter(.data$strain != neg_label)

  if (method == "match") {
    blanks <- neg |>
      dplyr::group_by(.data$Time, .data$pH) |>
      dplyr::summarise(blank = mean(.data$value), .groups = "drop")
    out <- samples |>
      dplyr::left_join(blanks, by = c("Time", "pH")) |>
      dplyr::mutate(OD = .data$value - .data$blank) |>
      dplyr::select(-"value", -"blank")
  } else {
    blanks <- neg |>
      dplyr::group_by(.data$pH) |>
      dplyr::summarise(blank = mean(.data$value), .groups = "drop")
    out <- samples |>
      dplyr::left_join(blanks, by = "pH") |>
      dplyr::mutate(OD = .data$value - .data$blank) |>
      dplyr::select(-"value", -"blank")
  }

  if (floor_zero) out$OD[out$OD < 0] <- 0
  out |> dplyr::arrange(.data$well, .data$Time)
}


#' Zero-offset specific wells by subtracting each well's own minimum OD.
#'
#' Useful when some wells sit on a raised baseline (e.g. condensation). A no-op
#' when `offset_wells` is NULL.
#'
#' @param mdata_long Long data with an `OD` column.
#' @param offset_wells Character vector of wells to offset, or NULL.
#' @return The data with adjusted `OD` for the listed wells.
gc_apply_offset <- function(mdata_long, offset_wells = NULL) {
  if (is.null(offset_wells)) return(mdata_long)
  mdata_long |>
    dplyr::group_by(.data$well) |>
    dplyr::mutate(
      OD = dplyr::if_else(
        .data$well %in% offset_wells,
        .data$OD - min(.data$OD),
        .data$OD
      )
    ) |>
    dplyr::ungroup()
}


## ---- Model fitting -------------------------------------------------------

#' Fit a logistic growth model to every well with growthcurver.
#'
#' @param mdata_corrected Long, blank-corrected data with `Time`, `well`, `OD`.
#' @param t_trim Passed to [growthcurver::SummarizeGrowth()].
#' @param bg_correct Passed to [growthcurver::SummarizeGrowth()].
#' @return A list with `models` (per-well growthcurver objects), `wide` (Time x
#'   well OD matrix), and `summary` (tidy per-well parameter table).
gc_fit_models <- function(mdata_corrected, t_trim = 0, bg_correct = "none") {
  wide <- reshape2::dcast(
    mdata_corrected[, c("Time", "well", "OD")],
    Time ~ well,
    value.var = "OD"
  )

  well_cols <- setdiff(names(wide), "Time")
  models <- lapply(wide[well_cols], function(x) {
    SummarizeGrowth(wide$Time, x, t_trim = t_trim, bg_correct = bg_correct)
  })

  summary <- purrr::map_dfr(well_cols, function(w) {
    v <- models[[w]]$vals
    data.frame(
      sample = w,
      k = v$k, n0 = v$n0, r = v$r,
      t_mid = v$t_mid, t_gen = v$t_gen,
      auc_l = v$auc_l, auc_e = v$auc_e,
      sigma = v$sigma, note = v$note,
      stringsAsFactors = FALSE
    )
  })

  list(models = models, wide = wide, summary = summary)
}


#' Build a long data frame of predicted OD values from fitted models.
#'
#' Wells that could not be fit are filled with `fallback`.
#'
#' @param fit Output of [gc_fit_models()].
#' @param fallback Constant predicted OD for wells with note "cannot fit data".
#' @return Long data frame with `Time`, `well`, `pred.OD`.
gc_predicted <- function(fit, fallback = 0.085) {
  wide <- fit$wide
  well_cols <- setdiff(names(wide), "Time")
  not_fit <- fit$summary$sample[fit$summary$note == "cannot fit data"]

  pred <- data.frame(Time = wide$Time)
  for (w in setdiff(well_cols, not_fit)) {
    pred[[w]] <- predict(fit$models[[w]]$model)
  }
  for (w in not_fit) {
    pred[[w]] <- rep(fallback, nrow(pred))
  }

  reshape2::melt(pred, id.vars = "Time", variable.name = "well",
                 value.name = "pred.OD") |>
    dplyr::mutate(well = as.character(.data$well))
}


#' Apply post-fit corrections to growth parameters.
#'
#' Joins the plate map, drops NEG wells, records each well's observed max OD, and
#' corrects implausible fits:
#'   * k < blank_baseline  -> r = 0, k = 0 (no real growth above blank)
#'   * k > high_k          -> "zero": r = 0, k = 0; "rescue": keep r, k = max.OD
#'   * problem_wells       -> r = 0, k = 0 (e.g. condensation artifacts)
#'
#' @param summary Tidy parameter table from [gc_fit_models()].
#' @param platemap Plate map from [gc_build_platemap()].
#' @param wide Wide OD matrix from [gc_fit_models()] (for max OD).
#' @param blank_baseline Lower k cutoff (mean blank OD).
#' @param high_k Upper k cutoff for implausible carrying capacity.
#' @param high_k_action "zero" or "rescue".
#' @param problem_wells Character vector of wells to force to zero, or NULL.
#' @param neg_label Blank label to drop.
#' @return Corrected parameter table with `strain`, `pH`, `replicate`, `max.OD`.
gc_correct_params <- function(summary,
                              platemap,
                              wide,
                              blank_baseline = 0.085,
                              high_k = 1,
                              high_k_action = c("zero", "rescue"),
                              problem_wells = NULL,
                              neg_label = "NEG") {
  high_k_action <- match.arg(high_k_action)

  max_od <- data.frame(
    sample = setdiff(names(wide), "Time"),
    max.OD = vapply(wide[setdiff(names(wide), "Time")], max, numeric(1)),
    row.names = NULL
  )

  out <- summary |>
    merge(platemap, by.x = "sample", by.y = "well", all.y = TRUE) |>
    dplyr::filter(.data$strain != neg_label) |>
    merge(max_od, by = "sample")

  out <- out |>
    dplyr::mutate(
      r = dplyr::case_when(
        .data$k < blank_baseline ~ 0,
        .data$k > high_k & high_k_action == "zero" ~ 0,
        TRUE ~ .data$r
      ),
      k = dplyr::case_when(
        .data$k < blank_baseline ~ 0,
        .data$k > high_k & high_k_action == "zero" ~ 0,
        .data$k > high_k & high_k_action == "rescue" ~ .data$max.OD,
        TRUE ~ .data$k
      )
    )

  if (!is.null(problem_wells)) {
    out <- out |>
      dplyr::mutate(
        r = dplyr::if_else(.data$sample %in% problem_wells, 0, .data$r),
        k = dplyr::if_else(.data$sample %in% problem_wells, 0, .data$k)
      )
  }
  out
}


#' Join corrected parameters back to the long observed/predicted data.
#'
#' @param mdata_corrected Long blank-corrected data (`well`, `Time`, `OD`, ...).
#' @param predicted Long predicted data from [gc_predicted()].
#' @param platemap Plate map from [gc_build_platemap()].
#' @param params Corrected parameters from [gc_correct_params()].
#' @param neg_label Blank label to drop.
#' @return Long data frame with observed `OD`, `pred.OD`, `r`, `k`, `sigma`,
#'   `note`, and a `strain.rep` key for faceting.
gc_join_final <- function(mdata_corrected, predicted, platemap, params,
                          neg_label = "NEG") {
  df <- merge(
    mdata_corrected[, c("well", "Time", "OD")],
    predicted,
    by = c("Time", "well")
  ) |>
    merge(platemap, by = "well", all.y = TRUE) |>
    merge(
      params[, c("sample", "note", "r", "k", "sigma")],
      by.x = "well", by.y = "sample"
    ) |>
    dplyr::filter(.data$strain != neg_label)

  df$strain.rep <- paste(df$strain, df$replicate, sep = ".")
  df
}


## ---- Plots ---------------------------------------------------------------

#' pH text-annotation frame used to label facets.
#' @param mdata_long Long data with a `pH` column.
#' @param x,y Annotation coordinates.
#' @return A data frame with `pH`, `label`, `x`, `y`.
gc_phlabs <- function(mdata_long, x = 10, y = 0.5) {
  levels <- sort(unique(mdata_long$pH))
  data.frame(pH = levels, label = levels, x = x, y = y)
}

#' Raw (blank-corrected) growth curves for one strain.
#' @return A ggplot object.
gc_plot_raw <- function(mdata_long, strain, date, phlabs) {
  mdata_long |>
    dplyr::filter(.data$strain == !!strain) |>
    ggplot(aes(x = .data$Time, y = .data$OD)) +
    geom_text(phlabs, mapping = aes(x = .data$x, y = .data$y,
                                    label = paste("pH", .data$label)),
              family = "mono") +
    geom_point(aes(colour = .data$replicate), alpha = 0.3, size = 0.7) +
    ylim(0, 0.6) +
    xlab("Time (hrs)") +
    facet_wrap(~pH, ncol = 6) +
    labs(title = paste("pH assay for isolate", strain), subtitle = date) +
    gc_apatheme() +
    theme(
      strip.background = element_blank(),
      strip.text.x = element_blank(),
      plot.title = element_text(color = "black", size = 12),
      plot.subtitle = element_text(color = "black", size = 10)
    )
}

#' QC plot of the blank/negative wells.
#' @return A ggplot object.
gc_plot_neg <- function(mdata_neg, date, phlabs) {
  ggplot(mdata_neg, aes(x = .data$Time, y = .data$value)) +
    geom_point(alpha = 0.7) +
    ylim(0, 0.6) +
    xlab("Time (hrs)") +
    geom_text(phlabs, mapping = aes(x = .data$x, y = .data$y - 0.35,
                                    label = paste("pH", .data$label)),
              family = "mono") +
    facet_wrap(~pH, ncol = 6) +
    labs(title = "pH assay NEG", subtitle = date) +
    gc_apatheme() +
    theme(
      strip.background = element_blank(),
      strip.text.x = element_blank(),
      plot.title = element_text(color = "black", size = 12),
      plot.subtitle = element_text(color = "black", size = 10)
    )
}

#' Observed points + fitted curve with parameter annotations for one strain.rep.
#' @return A ggplot object.
gc_plot_fitted <- function(df_final, strain_rep, date, phlabs) {
  d <- df_final |> dplyr::filter(.data$strain.rep == !!strain_rep)
  tmp <- d |>
    dplyr::select("well", "pH", "note", "r", "k", "sigma") |>
    dplyr::distinct(.data$pH, .keep_all = TRUE) |>
    merge(phlabs, by = "pH")

  ggplot(d, aes(x = .data$Time, y = .data$OD)) +
    geom_point(alpha = 0.3) +
    geom_line(aes(y = .data$pred.OD), color = "red") +
    ylim(0, 0.6) +
    xlab("Time (hrs)") +
    geom_text(tmp, mapping = aes(x = .data$x, y = .data$y,
                                 label = paste("pH", .data$label)), family = "mono") +
    geom_text(tmp, mapping = aes(x = .data$x + 10, y = .data$y - 0.05,
                                 label = .data$note), family = "mono") +
    geom_text(tmp, mapping = aes(x = .data$x, y = .data$y + 0.05,
                                 label = .data$well), family = "mono") +
    geom_text(tmp, mapping = aes(x = .data$x, y = .data$y - 0.1,
                                 label = paste("r:", round(.data$r, 3))), family = "mono") +
    geom_text(tmp, mapping = aes(x = .data$x + 10, y = .data$y - 0.15,
                                 label = paste("K:", round(.data$k, 3))), family = "mono") +
    geom_text(tmp, mapping = aes(x = .data$x + 10, y = .data$y - 0.20,
                                 label = paste("sigma:", round(.data$sigma, 3))), family = "mono") +
    facet_wrap(~pH, ncol = 6) +
    labs(title = paste("pH assay for isolate", strain_rep), subtitle = date) +
    gc_apatheme() +
    theme(
      strip.background = element_blank(),
      strip.text.x = element_blank(),
      plot.title = element_text(color = "black", size = 12),
      plot.subtitle = element_text(color = "black", size = 10)
    )
}

#' pH response curve: growth rate (r) or carrying capacity (k) vs pH.
#'
#' @param growth_values Corrected values with `pH`, `strain`, `replicate`, and
#'   the response column.
#' @param y "r" or "k".
#' @param date Subtitle date.
#' @param taxa_colors Color palette.
#' @param facet "wrap" (replicate ~ strain) or "grid".
#' @return A ggplot object.
gc_plot_ph_curve <- function(growth_values,
                             y = c("r", "k"),
                             date,
                             taxa_colors = gc_taxa_colors(),
                             facet = c("wrap", "grid")) {
  y <- match.arg(y)
  facet <- match.arg(facet)
  ylab <- if (y == "r") "Growth rate (r)" else "Carrying capacity (K)"

  p <- ggplot(
    growth_values,
    aes(x = .data$pH, color = .data$strain, group = .data$strain,
        y = .data[[y]])
  ) +
    scale_color_manual(values = taxa_colors, name = "Isolate") +
    geom_smooth(aes(fill = .data$strain)) +
    scale_fill_manual(values = taxa_colors, name = "Isolate") +
    geom_point(size = 2) +
    scale_x_continuous(breaks = seq(3.2, 10.1, 0.3)) +
    ylim(0, 0.6) +
    labs(title = "pH curve", subtitle = date) +
    ylab(ylab) +
    gc_apatheme() +
    theme(
      axis.text.x = element_text(angle = 90, hjust = 0, vjust = 0.5),
      plot.title = element_text(color = "black", size = 12),
      plot.subtitle = element_text(color = "black", size = 10),
      legend.position = "none"
    )

  if (facet == "wrap") {
    p + facet_wrap(replicate ~ strain)
  } else {
    p + facet_grid(replicate ~ strain)
  }
}


## ---- Export --------------------------------------------------------------

#' Write the per-run growth-value table.
#'
#' @param growth_values Corrected values (from [gc_correct_params()], with a
#'   `date` column added).
#' @param path Output file path.
#' @return `path`, invisibly.
gc_export_values <- function(growth_values, path) {
  write.table(
    growth_values,
    file = path,
    sep = "\t",
    row.names = FALSE,
    quote = FALSE
  )
  invisible(path)
}
