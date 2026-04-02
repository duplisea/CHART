# =============================================================================
# CHART - Fish Habitat Compensation Analysis Tool
# R Library: chart_functions.r
#
# Dependencies: ggplot2, patchwork, data.table, openxlsx
# =============================================================================


# --- 1. TEMPORAL COMPENSATION MULTIPLIER (TCM) --------------------------------

#' Calculate Temporal Compensation Multiplier (TCM) Details
#'
#' Computes the Temporal Compensation Multiplier and the full year-by-year
#' benefit schedule used to derive it. The compensation habitat is assumed to
#' provide zero function during construction, then ramp up linearly to full
#' function, and remain at full function thereafter.
#'
#' @param time_lag_years      Numeric. Years from present until the compensation
#'                            habitat is complete (construction lag).
#' @param restoration_period_years Numeric. Additional years after completion
#'                            until full ecological function is achieved
#'                            (linear ramp-up period).
#' @param T_max               Integer. Maximum time horizon in years (default 50).
#'
#' @return A list with:
#' \item{dt_time}{A \code{data.table} with columns \code{t}, \code{DF}
#'   (discount factor, currently 1), \code{BenefitShare} (proportion of full
#'   function at year \code{t}), and \code{DiscountedBenefit}.}
#' \item{temporal_comp_multiplier}{Numeric. The TCM (ratio of undiscounted loss
#'   to discounted gain). Returns 1e6 if gain is negligible.}
#'
#' @details
#' The discount rate is currently set to zero (undiscounted). The TCM is:
#' \deqn{TCM = \frac{T_{max}}{\sum_{t=0}^{T_{max}-1} B_t}}
#' where \eqn{B_t} is the proportion of full ecological function at year \eqn{t}.
#'
#' @examples
#' calculate_tcm_details(time_lag_years = 2, restoration_period_years = 5, T_max = 50)
#'
#' @importFrom data.table data.table
#' @export
calculate_tcm_details <- function(time_lag_years,
                                  restoration_period_years,
                                  T_max = 50) {
  discount_rate <- 0
  T_start <- time_lag_years
  T_end   <- time_lag_years + restoration_period_years
  T_ramp  <- restoration_period_years

  dt_time <- data.table(t = 0:(T_max - 1))
  dt_time[, DF := 1 / (1 + discount_rate)^t]
  loss_discount_factor <- sum(dt_time$DF)

  dt_time[, BenefitShare := 0]
  if (T_ramp > 0) {
    dt_time[t >= T_start & t < T_end,
            BenefitShare := (t - T_start) / T_ramp]
  }
  dt_time[t >= T_end, BenefitShare := 1]

  dt_time[, DiscountedBenefit := BenefitShare * DF]
  gain_discount_factor <- sum(dt_time$DiscountedBenefit)

  temporal_comp_multiplier <- if (gain_discount_factor < 1e-6) {
    1e6
  } else {
    loss_discount_factor / gain_discount_factor
  }

  list(
    dt_time                  = dt_time,
    temporal_comp_multiplier = temporal_comp_multiplier
  )
}


# --- 2. MONTE CARLO COMPENSATION AREA -----------------------------------------

#' Calculate Compensation Area via Monte Carlo Simulation
#'
#' Estimates the required compensation area for a fish-habitat HADD (Harmful
#' Alteration, Disruption, or Destruction) using a Monte Carlo simulation over
#' five ecosystem-service factors. Supports three HADD types: permanent
#' destruction, partial deterioration, and temporary perturbation.
#'
#' @param destruction_area          Positive numeric. Area (m²) affected by the HADD.
#' @param factor_ranges_destroyed   List of 5 numeric vectors of length 2
#'                                  (\code{c(min, max)}) for each factor score
#'                                  in the destroyed habitat.
#' @param factor_ranges_compensated List of 5 numeric vectors of length 2 for
#'                                  each factor score in the compensation habitat.
#' @param weights                   Numeric vector of length 5. Relative
#'                                  importance of each factor (normalised
#'                                  internally to sum to 1). If all weights are
#'                                  zero, equal weights (0.2 each) are used.
#' @param temporal_comp_multiplier  Numeric. TCM from
#'                                  \code{\link{calculate_tcm_details}}.
#' @param baseline_function_pct     Numeric 0–<100. Existing ecological function
#'                                  (%) at the compensation site before
#'                                  improvement. Adjusts the required area by
#'                                  \eqn{1 / (1 - baseline\%/100)}. Default 0.
#' @param num_simulations           Integer. Number of Monte Carlo draws
#'                                  (default 500).
#' @param quantiles                 Numeric vector of length 2.
#'                                  Confidence-interval quantiles (default
#'                                  \code{c(0.025, 0.975)}).
#' @param habitat_names_en          Character vector of length 2. English names
#'                                  for \code{c(destroyed, compensation)}
#'                                  habitats.
#' @param habitat_names_fr          Character vector of length 2. French names.
#' @param factor_names_en           Character vector of length 5. English factor
#'                                  names (default generic labels).
#' @param factor_names_fr           Character vector of length 5. French factor
#'                                  names.
#' @param hadd_type                 Character. One of \code{"destruction"},
#'                                  \code{"deterioration"}, or
#'                                  \code{"perturbation"} (default
#'                                  \code{"destruction"}).
#' @param impact_duration_years     Numeric. For \code{hadd_type =
#'                                  "perturbation"}: years the habitat is fully
#'                                  blocked (default 1).
#' @param recovery_time_years       Numeric. For \code{hadd_type =
#'                                  "perturbation"}: years to return to baseline
#'                                  after impact (default 1).
#' @param deterioration_pct         Numeric 1–99. For \code{hadd_type =
#'                                  "deterioration"}: percentage of habitat
#'                                  function permanently lost (default 50).
#' @param T_max                     Integer. Time horizon in years, used in the
#'                                  perturbation service-years calculation
#'                                  (default 50).
#'
#' @return A named list containing:
#' \item{destruction_area}{Input destruction area.}
#' \item{mean_adjusted_area}{Mean simulated compensation area.}
#' \item{median_adjusted_area}{Median simulated compensation area.}
#' \item{confidence_interval}{Named numeric vector with the CI bounds.}
#' \item{simulated_areas}{All finite simulated compensation areas.}
#' \item{habitat_names_en, habitat_names_fr}{Habitat name vectors.}
#' \item{factor_names_en, factor_names_fr}{Factor name vectors.}
#' \item{weights}{Raw input weights.}
#' \item{weights_standardized}{Weights normalised to sum to 1.}
#' \item{factor_ranges_destroyed, factor_ranges_compensated}{Named input
#'   ranges.}
#' \item{temporal_comp_multiplier}{Input TCM value.}
#' \item{baseline_function_pct}{Input baseline percentage.}
#' \item{baseline_adjustment}{Computed baseline adjustment factor.}
#' \item{hadd_type}{HADD type string.}
#' \item{impact_duration_years, recovery_time_years}{Perturbation parameters.}
#' \item{deterioration_pct}{Deterioration parameter.}
#'
#' @details
#' \strong{HADD types and formulae:}
#' \describe{
#'   \item{destruction}{Permanent, complete loss.
#'     \eqn{A_{comp} = A_{HADD} \times (S_{dest}/S_{comp}) \times TCM
#'     \times B_{adj}}}
#'   \item{deterioration}{Permanent, partial loss. Only the lost fraction is
#'     compensated:
#'     \eqn{A_{comp} = A_{HADD} \times f_{det} \times (S_{dest}/S_{comp})
#'     \times TCM \times B_{adj}}}
#'   \item{perturbation}{Temporary loss, balanced in service-years.
#'     \eqn{gain\_years = T_{max} / TCM};
#'     \eqn{A_{comp} = (A_{HADD} \times S_{dest} \times (t_{impact} +
#'     t_{recovery})) / (S_{comp} \times gain\_years) \times B_{adj}}.
#'     This formulation is dimensionally consistent with the other HADD types
#'     and avoids near-zero denominators.}
#' }
#'
#' @examples
#' tcm <- calculate_tcm_details(2, 5)$temporal_comp_multiplier
#' calculate_compensation_area(
#'   destruction_area          = 1000,
#'   factor_ranges_destroyed   = list(c(3,5), c(2,4), c(1,3), c(2,5), c(4,5)),
#'   factor_ranges_compensated = list(c(1,2), c(2,3), c(3,4), c(1,3), c(2,4)),
#'   weights                   = c(0.2, 0.3, 0.1, 0.2, 0.2),
#'   temporal_comp_multiplier  = tcm,
#'   num_simulations           = 1000,
#'   habitat_names_en          = c("Zostera", "Laminaria"),
#'   habitat_names_fr          = c("Zostère", "Laminaires")
#' )
#'
#' @importFrom data.table data.table
#' @export
calculate_compensation_area <- function(
  destruction_area,
  factor_ranges_destroyed,
  factor_ranges_compensated,
  weights,
  temporal_comp_multiplier,
  baseline_function_pct     = 0,
  num_simulations           = 500,
  quantiles                 = c(0.025, 0.975),
  habitat_names_en          = c("Destroyed Habitat", "Compensation Habitat"),
  habitat_names_fr          = c("Habitat détruit",   "Habitat de compensation"),
  factor_names_en           = c("factor1", "factor2", "factor3", "factor4", "factor5"),
  factor_names_fr           = c("facteur1", "facteur2", "facteur3", "facteur4", "facteur5"),
  hadd_type                 = "destruction",
  impact_duration_years     = 1,
  recovery_time_years       = 1,
  deterioration_pct         = 50,
  T_max                     = 50
) {
  # --- Input validation -------------------------------------------------------
  if (!is.numeric(destruction_area) || destruction_area <= 0)
    stop("destruction_area must be a positive number.")
  if (!is.list(factor_ranges_destroyed) || length(factor_ranges_destroyed) != 5)
    stop("factor_ranges_destroyed must be a list of length 5.")
  if (!is.list(factor_ranges_compensated) || length(factor_ranges_compensated) != 5)
    stop("factor_ranges_compensated must be a list of length 5.")
  if (length(weights) != 5 || !is.numeric(weights) || any(weights < 0))
    stop("weights must be a non-negative numeric vector of length 5.")
  if (!hadd_type %in% c("destruction", "deterioration", "perturbation"))
    stop("hadd_type must be one of: 'destruction', 'deterioration', 'perturbation'.")

  # --- Weight standardisation -------------------------------------------------
  weights_standardized <- if (sum(weights) == 0) rep(0.2, 5) else weights / sum(weights)

  names(factor_ranges_destroyed)   <- factor_names_en
  names(factor_ranges_compensated) <- factor_names_en

  # --- Baseline adjustment factor ---------------------------------------------
  baseline_adjustment <- if (baseline_function_pct >= 100) {
    1e6
  } else {
    1 / (1 - baseline_function_pct / 100)
  }

  # --- Vectorised Monte Carlo simulation (data.table) -------------------------
  dt_sim <- data.table(sim_id = 1:num_simulations)

  for (j in 1:5) {
    dt_sim[, paste0("dest_", j) := runif(.N,
                                          factor_ranges_destroyed[[j]][1],
                                          factor_ranges_destroyed[[j]][2])]
    dt_sim[, paste0("comp_", j) := runif(.N,
                                          factor_ranges_compensated[[j]][1],
                                          factor_ranges_compensated[[j]][2])]
  }

  dt_sim[, destroyed_weighted :=
           dest_1 * weights_standardized[1] +
           dest_2 * weights_standardized[2] +
           dest_3 * weights_standardized[3] +
           dest_4 * weights_standardized[4] +
           dest_5 * weights_standardized[5]]

  dt_sim[, compensated_weighted :=
           comp_1 * weights_standardized[1] +
           comp_2 * weights_standardized[2] +
           comp_3 * weights_standardized[3] +
           comp_4 * weights_standardized[4] +
           comp_5 * weights_standardized[5]]

  dt_sim[, S_ratio := destroyed_weighted / compensated_weighted]
  dt_sim[compensated_weighted < 1e-6, S_ratio := 1e6]

  # --- HADD-type area calculation ---------------------------------------------
  if (hadd_type == "destruction") {
    # Permanent complete loss: full area × quality ratio × TCM × baseline adj
    dt_sim[, simulated_area :=
             destruction_area * S_ratio * temporal_comp_multiplier * baseline_adjustment]

  } else if (hadd_type == "deterioration") {
    # Permanent partial loss: only the lost fraction needs compensating
    deterioration_fraction <- deterioration_pct / 100
    dt_sim[, simulated_area :=
             destruction_area * deterioration_fraction * S_ratio *
             temporal_comp_multiplier * baseline_adjustment]

  } else if (hadd_type == "perturbation") {
    # Temporary loss: balance service-years lost against service-years gained.
    #
    # gain_years  = T_max / TCM  (effective years of full function over horizon)
    # gain_per_m2 = compensated_weighted × gain_years
    # area        = (A_HADD × destroyed_weighted × (impact + recovery))
    #               / gain_per_m2  ×  baseline_adjustment
    #
    # This is dimensionally consistent with destruction/deterioration and
    # avoids near-zero denominators from baseline subtraction.
    gain_years <- T_max / temporal_comp_multiplier

    dt_sim[, service_years_lost :=
             destruction_area * destroyed_weighted *
             (impact_duration_years + recovery_time_years)]

    dt_sim[, gain_per_m2 := pmax(compensated_weighted * gain_years, 1e-6)]

    dt_sim[, simulated_area := (service_years_lost / gain_per_m2) * baseline_adjustment]
  }

  # --- Summary statistics -----------------------------------------------------
  simulated_areas <- dt_sim$simulated_area
  simulated_areas <- simulated_areas[is.finite(simulated_areas)]
  ci              <- quantile(simulated_areas, quantiles, na.rm = TRUE)

  # --- Return -----------------------------------------------------------------
  list(
    destruction_area          = destruction_area,
    mean_adjusted_area        = mean(simulated_areas, na.rm = TRUE),
    median_adjusted_area      = median(simulated_areas, na.rm = TRUE),
    confidence_interval       = ci,
    simulated_areas           = simulated_areas,
    habitat_names_en          = habitat_names_en,
    habitat_names_fr          = habitat_names_fr,
    factor_names_en           = factor_names_en,
    factor_names_fr           = factor_names_fr,
    weights                   = weights,
    weights_standardized      = weights_standardized,
    factor_ranges_destroyed   = factor_ranges_destroyed,
    factor_ranges_compensated = factor_ranges_compensated,
    temporal_comp_multiplier  = temporal_comp_multiplier,
    baseline_function_pct     = baseline_function_pct,
    baseline_adjustment       = baseline_adjustment,
    hadd_type                 = hadd_type,
    impact_duration_years     = impact_duration_years,
    recovery_time_years       = recovery_time_years,
    deterioration_pct         = deterioration_pct
  )
}


# --- 3. PLOTTING UTILITIES ----------------------------------------------------

#' Rescale Alpha Values to the Range [0.3, 1]
#'
#' Maps a vector of raw alpha (weight) values onto the interval [0.3, 1],
#' treating zeros as transparent (alpha = 0).
#'
#' @param alpha Numeric vector of non-negative values.
#' @return Numeric vector of rescaled alpha values.
#' @export
rescale_alpha <- function(alpha) {
  non_zero_alpha <- alpha[alpha > 0]
  if (length(non_zero_alpha) == 0) return(rep(0, length(alpha)))
  max_alpha <- max(non_zero_alpha)
  ifelse(alpha == 0,
         0,
         0.3 + ((alpha / max_alpha) * 0.7))
}


#' Create Factor Axis Labels Including Standardised Weights
#'
#' Shortens factor names longer than 15 characters and appends the standardised
#' weight in parentheses for use as plot axis labels.
#'
#' @param factor_names         Character vector of factor names.
#' @param weights_standardized Numeric vector of standardised weights (same
#'                             length as \code{factor_names}).
#' @return Character vector of formatted labels.
#' @export
create_factor_labels <- function(factor_names, weights_standardized) {
  factor_names_shortened <- sapply(factor_names, function(x) {
    if (is.null(x) || is.na(x) || nchar(x) == 0) return("Factor")
    ifelse(nchar(x) > 15, paste0(substr(x, 1, 15), "..."), x)
  })
  paste0(factor_names_shortened, " (", format(weights_standardized, digits = 2), ")")
}


#' Build HADD-Type Display Strings for Plots (English and French)
#'
#' Returns a named list with human-readable HADD type labels and a colour code
#' used consistently across all three plot panels. Centralising these strings
#' ensures that the HADD type is communicated identically in panel titles, bar
#' labels, annotation boxes, and the overall plot subtitle.
#'
#' @param hadd_type         Character. One of \code{"destruction"},
#'                          \code{"deterioration"}, or \code{"perturbation"}.
#' @param lang              Character. \code{"en"} (default) or \code{"fr"}.
#' @param deterioration_pct Numeric. Appended to the label only when
#'                          \code{hadd_type == "deterioration"} (default 50).
#'
#' @return A list with three elements:
#' \item{label}{Short human-readable label for the HADD type, e.g.
#'   \code{"Deterioration (50%)"} / \code{"Détérioration (50%)"}.}
#' \item{colour}{Hex colour associated with the HADD type:
#'   red (\code{"#D62728"}) for destruction,
#'   orange (\code{"#FF7F0E"}) for deterioration,
#'   purple (\code{"#9467BD"}) for perturbation.}
#' \item{hadd_bar_label}{Label used for the HADD-area bar in panel p2, e.g.
#'   \code{"HADD Area (Destruction)"} / \code{"Zone APDN (Destruction)"}.}
#'
#' @examples
#' hadd_type_strings("deterioration", lang = "en", deterioration_pct = 30)
#' hadd_type_strings("perturbation",  lang = "fr")
#'
#' @export
hadd_type_strings <- function(hadd_type,
                              lang              = "en",
                              deterioration_pct = 50) {
  if (lang == "fr") {
    label <- switch(hadd_type,
      destruction   = "Destruction",
      deterioration = paste0("D\u00e9t\u00e9rioration (", deterioration_pct, "%)"),
      perturbation  = "Perturbation",
      "Inconnu"
    )
    hadd_bar_label <- switch(hadd_type,
      destruction   = "Zone APDN (Destruction)",
      deterioration = paste0("Zone APDN (D\u00e9t\u00e9rioration ", deterioration_pct, "%)"),
      perturbation  = "Zone APDN (Perturbation)",
      "Zone APDN"
    )
  } else {
    label <- switch(hadd_type,
      destruction   = "Destruction",
      deterioration = paste0("Deterioration (", deterioration_pct, "%)"),
      perturbation  = "Perturbation",
      "Unknown"
    )
    hadd_bar_label <- switch(hadd_type,
      destruction   = "HADD Area (Destruction)",
      deterioration = paste0("HADD Area (Deterioration ", deterioration_pct, "%)"),
      perturbation  = "HADD Area (Perturbation)",
      "HADD Area"
    )
  }

  colour <- switch(hadd_type,
    destruction   = "#D62728",   # red
    deterioration = "#FF7F0E",   # orange
    perturbation  = "#9467BD",   # purple
    "#333333"
  )

  list(label = label, colour = colour, hadd_bar_label = hadd_bar_label)
}


# --- 4. VISUALISATION ---------------------------------------------------------

#' Plot Compensation Analysis Results
#'
#' Produces a three-panel figure summarising a compensation analysis:
#' \enumerate{
#'   \item Factor comparison bar chart with uncertainty ranges. Panel title and
#'         colour reflect the HADD type.
#'   \item Horizontal bar chart comparing the HADD area and the required median
#'         compensation area. The HADD bar is coloured by HADD type; bars carry
#'         numeric value labels.
#'   \item Density plot of the Monte Carlo simulated compensation areas. An
#'         annotation box states the HADD type, type-specific parameters,
#'         median, and 95 \% CI.
#' }
#' Supports bilingual (English / French) output via the \code{lang} argument.
#'
#' @param result    A list returned by \code{\link{calculate_compensation_area}}.
#' @param quantiles Numeric vector of length 2 for the CI (default
#'                  \code{c(0.025, 0.975)}).
#' @param lang      Character. \code{"en"} (default) or \code{"fr"} for French
#'                  labels.
#'
#' @return A \code{patchwork} combined plot object.
#'
#' @details
#' \strong{Axis scaling:} The shared x-axis limit for panels p2 and p3 is set
#' to 110 \% of the 99th percentile of simulated areas, with a floor of
#' 120 \% of the larger of the HADD area and the median compensation area.
#' This suppresses extreme outliers (common in perturbation scenarios) while
#' always keeping both bars fully visible. \code{coord_cartesian()} is used
#' instead of \code{xlim()} so the density curve is not clipped.
#'
#' \strong{HADD-type colour coding:}
#' \describe{
#'   \item{Destruction}{Red — permanent complete loss.}
#'   \item{Deterioration}{Orange — permanent partial loss; percentage shown.}
#'   \item{Perturbation}{Purple — temporary loss; impact and recovery years
#'     shown.}
#' }
#'
#' @examples
#' tcm  <- calculate_tcm_details(2, 5)$temporal_comp_multiplier
#' res  <- calculate_compensation_area(
#'   destruction_area          = 1000,
#'   factor_ranges_destroyed   = list(c(3,5), c(2,4), c(1,3), c(2,5), c(4,5)),
#'   factor_ranges_compensated = list(c(1,2), c(2,3), c(3,4), c(1,3), c(2,4)),
#'   weights                   = c(0.2, 0.3, 0.1, 0.2, 0.2),
#'   temporal_comp_multiplier  = tcm,
#'   habitat_names_en          = c("Zostera", "Laminaria"),
#'   habitat_names_fr          = c("Zostère", "Laminaires")
#' )
#' plot_compensation_analysis(res, lang = "en")
#' plot_compensation_analysis(res, lang = "fr")
#'
#' @importFrom ggplot2 ggplot aes geom_bar geom_col geom_errorbar geom_density
#'   geom_vline geom_text annotate labs theme_minimal coord_cartesian
#'   scale_fill_brewer scale_fill_manual scale_colour_brewer
#'   scale_alpha_identity scale_y_continuous element_text
#' @importFrom patchwork plot_layout plot_annotation
#' @export
plot_compensation_analysis <- function(result,
                                       quantiles = c(0.025, 0.975),
                                       lang      = "en") {

  # --- HADD-type display strings ---------------------------------------------
  hts          <- hadd_type_strings(result$hadd_type,
                                    lang              = lang,
                                    deterioration_pct = result$deterioration_pct)
  hadd_label   <- hts$label
  hadd_colour  <- hts$colour
  hadd_bar_lbl <- hts$hadd_bar_label

  # --- Language-specific strings ---------------------------------------------
  if (lang == "fr") {
    habitat_names <- result$habitat_names_fr
    factor_names  <- result$factor_names_fr

    baseline_note <- if (result$baseline_function_pct > 0) {
      paste0("\n*Surface de compensation ajust\u00e9e pour ",
             result$baseline_function_pct, "% fonction de base existante")
    } else ""

    title_p1 <- paste0(
      "Services \u00e9cosyst\u00e9miques par type d'habitat",
      " \u2014 APDN\u00a0: ", hadd_label,
      "\n(Poids standardis\u00e9 entre parenth\u00e8ses)", baseline_note)
    x_p1     <- "Facteur de service \u00e9cosyst\u00e9mique"
    y_p1     <- "Score de contribution (\u00e9valuation utilisateur)"
    fill_p1  <- "Habitat"

    title_p2 <- paste0("APDN et zone de compensation requise  [", hadd_label, "]")
    y_p2     <- "Type d'habitat"
    x_p2     <- expression(Surface ~ (m^2))

    title_p3 <- paste0("Distribution de la zone de compensation requise  [",
                       hadd_label, "]")
    x_p3     <- expression(Surface ~ (m^2))
    y_p3     <- "Densit\u00e9 de Probabilit\u00e9"

    p3_note <- if (result$hadd_type == "perturbation") {
      paste0("Impact\u00a0: ", result$impact_duration_years,
             " an(s) | R\u00e9cup\u00e9ration\u00a0: ",
             result$recovery_time_years, " an(s)")
    } else if (result$hadd_type == "deterioration") {
      paste0("Perte fonctionnelle\u00a0: ", result$deterioration_pct, "%")
    } else {
      "Perte permanente compl\u00e8te"
    }

    anno_title   <- "Analyse de compensation d'habitat de poisson"
    anno_sub     <- paste0("Bas\u00e9 sur ",
                           format(result$destruction_area, big.mark = ","),
                           " m\u00b2 APDN dans ", habitat_names[1],
                           "  |  Type d'APDN\u00a0: ", hadd_label)
    comp_bar_lbl <- "Zone de Compensation"
    median_lbl   <- "M\u00e9diane"
    ci_lbl       <- "IC 95%"

  } else {
    habitat_names <- result$habitat_names_en
    factor_names  <- result$factor_names_en

    baseline_note <- if (result$baseline_function_pct > 0) {
      paste0("\n*Compensation area adjusted for ",
             result$baseline_function_pct, "% existing baseline function")
    } else ""

    title_p1 <- paste0(
      "Ecosystem services by habitat type",
      " \u2014 HADD: ", hadd_label,
      "\n(Standardized Weight in Parentheses)", baseline_note)
    x_p1     <- "Ecosystem service factor"
    y_p1     <- "Contribution score (user assessment)"
    fill_p1  <- "Habitat"

    title_p2 <- paste0("HADD & required compensation area  [", hadd_label, "]")
    y_p2     <- "Habitat type"
    x_p2     <- expression(Area ~ (m^2))

    title_p3 <- paste0("Distribution of required compensation area  [",
                       hadd_label, "]")
    x_p3     <- expression(Area ~ (m^2))
    y_p3     <- "Probability Density"

    p3_note <- if (result$hadd_type == "perturbation") {
      paste0("Impact: ", result$impact_duration_years,
             " yr(s) | Recovery: ", result$recovery_time_years, " yr(s)")
    } else if (result$hadd_type == "deterioration") {
      paste0("Functional loss: ", result$deterioration_pct, "%")
    } else {
      "Permanent complete loss"
    }

    anno_title   <- "Fish Habitat Compensation Analysis"
    anno_sub     <- paste0("Based on ",
                           format(result$destruction_area, big.mark = ","),
                           " m\u00b2 HADD in ", habitat_names[1],
                           "  |  HADD type: ", hadd_label)
    comp_bar_lbl <- "Compensation Area"
    median_lbl   <- "Median"
    ci_lbl       <- "95% CI"
  }

  # --- Factor comparison data (p1) -------------------------------------------
  factor_data <- data.frame(
    Factor  = rep(factor_names, times = 2),
    Habitat = rep(habitat_names, each = length(factor_names)),
    Value   = c(unlist(lapply(result$factor_ranges_destroyed,   mean)),
                unlist(lapply(result$factor_ranges_compensated, mean))),
    Lower   = c(unlist(lapply(result$factor_ranges_destroyed,   function(r) r[1])),
                unlist(lapply(result$factor_ranges_compensated, function(r) r[1]))),
    Upper   = c(unlist(lapply(result$factor_ranges_destroyed,   function(r) r[2])),
                unlist(lapply(result$factor_ranges_compensated, function(r) r[2]))),
    Alpha   = rep(result$weights, times = 2)
  )

  weighted_factor_labels <- create_factor_labels(factor_names, result$weights_standardized)
  factor_data$WeightedFactor <- factor(factor_data$Factor,
                                       levels = factor_names,
                                       labels = weighted_factor_labels)

  p1 <- ggplot(factor_data,
               aes(x = WeightedFactor, y = Value,
                   fill = Habitat, alpha = rescale_alpha(Alpha))) +
    geom_bar(stat = "identity",
             position = position_dodge(width = 0.8),
             width = 0.7,
             aes(colour = Habitat),
             linewidth = 0.7) +
    geom_errorbar(aes(ymin = Lower, ymax = Upper),
                  position = position_dodge(width = 0.8),
                  width = 0.2, linewidth = 1) +
    scale_fill_brewer(palette = "Set2") +
    scale_colour_brewer(palette = "Set2", guide = "none") +
    scale_alpha_identity(guide = "none") +
    labs(title = title_p1, x = x_p1, y = y_p1, fill = fill_p1) +
    theme_minimal(base_size = 20) +
    theme(legend.position = "top",
          axis.text.x     = element_text(angle = 0, hjust = 0.5),
          plot.title      = element_text(colour = hadd_colour, face = "bold")) +
    scale_y_continuous(limits = c(0, 5))

  # --- Robust axis limit ------------------------------------------------------
  area_quantiles <- quantile(result$simulated_areas, probs = quantiles, na.rm = TRUE)
  p99            <- quantile(result$simulated_areas, probs = 0.99,      na.rm = TRUE)

  x_max_limit <- max(p99 * 1.10,
                     result$destruction_area     * 1.20,
                     result$median_adjusted_area * 1.20,
                     na.rm = TRUE)

  # --- Area comparison (p2) ---------------------------------------------------
  bar_labels <- c(hadd_bar_lbl, comp_bar_lbl)

  comparison_data <- data.frame(
    Habitat   = factor(bar_labels, levels = bar_labels),
    Area      = c(result$destruction_area, result$median_adjusted_area),
    Lower     = c(NA, area_quantiles[1]),
    Upper     = c(NA, area_quantiles[2]),
    BarColour = c(hadd_colour, "#4DAF4A"),
    stringsAsFactors = FALSE
  )

  p2 <- ggplot(comparison_data,
               aes(y = Habitat, x = Area, fill = Habitat)) +
    geom_col(alpha = 0.85) +
    geom_errorbar(aes(xmin = Lower, xmax = Upper),
                  width = 0.2, linewidth = 1, color = "black", na.rm = TRUE) +
    geom_text(aes(label = format(round(Area), big.mark = ",")),
              hjust = -0.15, size = 5, fontface = "bold") +
    scale_fill_manual(
      values = setNames(comparison_data$BarColour, bar_labels),
      guide  = "none") +
    labs(title = title_p2, y = y_p2, x = x_p2) +
    theme_minimal(base_size = 20) +
    theme(legend.position = "none",
          plot.title      = element_text(colour = hadd_colour, face = "bold")) +
    coord_cartesian(xlim = c(0, x_max_limit))

  # --- Distribution (p3) ------------------------------------------------------
  # Clip to x_max_limit so the density shape is not dominated by outliers
  areas_clipped <- result$simulated_areas[result$simulated_areas <= x_max_limit]

  p3 <- ggplot(data.frame(Area = areas_clipped), aes(x = Area)) +
    geom_density(fill = "lightblue", alpha = 0.5) +
    geom_vline(xintercept = result$median_adjusted_area,
               linetype = "dashed", color = "darkred", linewidth = 1) +
    geom_vline(xintercept = area_quantiles[area_quantiles <= x_max_limit],
               linetype = "dotted", color = "darkgreen", linewidth = 1) +
    annotate("label",
             x         = x_max_limit * 0.60,
             y         = Inf,
             vjust     = 1.2,
             label     = paste0(
               if (lang == "fr") "Type d'APDN : " else "HADD type: ",
               hadd_label, "\n", p3_note,
               "\n", median_lbl, ": ",
               format(round(result$median_adjusted_area), big.mark = ","), " m\u00b2",
               "\n", ci_lbl, ": [",
               format(round(area_quantiles[1]), big.mark = ","), ", ",
               format(round(area_quantiles[2]), big.mark = ","), "] m\u00b2"),
             colour     = hadd_colour,
             fill       = "white",
             label.size = 0.6,
             size       = 4,
             fontface   = "bold") +
    labs(title = title_p3, x = x_p3, y = y_p3) +
    theme_minimal(base_size = 20) +
    theme(plot.title = element_text(colour = hadd_colour, face = "bold")) +
    coord_cartesian(xlim = c(0, x_max_limit))

  # --- Combine ----------------------------------------------------------------
  combined_plot <- p1 / (p2 + p3) +
    plot_layout(heights = c(1, 1), widths = c(1, 1)) +
    plot_annotation(
      title    = anno_title,
      subtitle = anno_sub,
      theme    = theme_minimal(base_size = 25)
    )

  return(combined_plot)
}


# --- 5. EXCEL IMPORT / EXPORT -------------------------------------------------

#' Save Shiny App Inputs to an Excel Workbook
#'
#' Writes the current Shiny input state to a three-sheet Excel file:
#' \code{General_Setup}, \code{Factor_Names}, and \code{Factor_Values}.
#' Intended to be called inside a Shiny \code{downloadHandler}.
#'
#' @param input    The Shiny \code{input} object.
#' @param filepath Character. Destination file path (including \code{.xlsx}).
#'
#' @return Invisibly \code{NULL}. The file is written as a side-effect.
#'
#' @importFrom openxlsx createWorkbook addWorksheet writeData saveWorkbook
#' @export
save_inputs_to_excel <- function(input, filepath) {
  wb <- createWorkbook()

  addWorksheet(wb, "General_Setup")
  general_data <- data.frame(
    Parameter = c("project_title", "destruction_area",
                  "destroyed_name_en", "destroyed_name_fr",
                  "compensated_name_en", "compensated_name_fr",
                  "num_simulations", "baseline_function_pct",
                  "time_lag_years", "restoration_period_years", "t_max_years",
                  "hadd_type", "impact_duration_years",
                  "recovery_time_years", "deterioration_pct"),
    Value = c(input$project_title, input$destruction_area,
              input$destroyed_name_en, input$destroyed_name_fr,
              input$compensated_name_en, input$compensated_name_fr,
              input$num_simulations, input$baseline_function_pct,
              input$time_lag_years, input$restoration_period_years,
              input$t_max_years, input$hadd_type,
              input$impact_duration_years, input$recovery_time_years,
              input$deterioration_pct)
  )
  writeData(wb, "General_Setup", general_data)

  addWorksheet(wb, "Factor_Names")
  factor_names_data <- data.frame(
    Factor  = paste0("Factor", 1:5),
    English = c(input$factor1_name_en, input$factor2_name_en,
                input$factor3_name_en, input$factor4_name_en,
                input$factor5_name_en),
    French  = c(input$factor1_name_fr, input$factor2_name_fr,
                input$factor3_name_fr, input$factor4_name_fr,
                input$factor5_name_fr)
  )
  writeData(wb, "Factor_Names", factor_names_data)

  addWorksheet(wb, "Factor_Values")
  factor_values_data <- data.frame(
    Factor        = paste0("Factor", 1:5),
    Weight        = c(input$weight1, input$weight2, input$weight3,
                      input$weight4, input$weight5),
    Destroyed_Min = c(input$factor1_destroyed_range[1],
                      input$factor2_destroyed_range[1],
                      input$factor3_destroyed_range[1],
                      input$factor4_destroyed_range[1],
                      input$factor5_destroyed_range[1]),
    Destroyed_Max = c(input$factor1_destroyed_range[2],
                      input$factor2_destroyed_range[2],
                      input$factor3_destroyed_range[2],
                      input$factor4_destroyed_range[2],
                      input$factor5_destroyed_range[2]),
    Compensated_Min = c(input$factor1_compensated_range[1],
                        input$factor2_compensated_range[1],
                        input$factor3_compensated_range[1],
                        input$factor4_compensated_range[1],
                        input$factor5_compensated_range[1]),
    Compensated_Max = c(input$factor1_compensated_range[2],
                        input$factor2_compensated_range[2],
                        input$factor3_compensated_range[2],
                        input$factor4_compensated_range[2],
                        input$factor5_compensated_range[2])
  )
  writeData(wb, "Factor_Values", factor_values_data)

  saveWorkbook(wb, filepath, overwrite = TRUE)
  invisible(NULL)
}


#' Save Calculation Results to an Excel Workbook
#'
#' Writes a summary statistics sheet and a full simulated-areas sheet to an
#' Excel file. Intended to be called inside a Shiny \code{downloadHandler}.
#'
#' @param result   A list returned by \code{\link{calculate_compensation_area}}
#'                 with additional fields \code{time_lag_years},
#'                 \code{restoration_period_years}, and \code{t_max_years}
#'                 attached by the server (see app.r).
#' @param filepath Character. Destination file path (including \code{.xlsx}).
#'
#' @return Invisibly \code{NULL}. The file is written as a side-effect.
#'
#' @importFrom openxlsx createWorkbook addWorksheet writeData saveWorkbook
#' @export
save_results_to_excel <- function(result, filepath) {
  wb <- createWorkbook()

  addWorksheet(wb, "Summary_Statistics")

  metrics <- c("HADD Type",
               "Destruction Area (m\u00b2)",
               "Median Required Area (m\u00b2)",
               "Mean Required Area (m\u00b2)",
               "95% CI Lower Bound (m\u00b2)",
               "95% CI Upper Bound (m\u00b2)",
               "Temporal Multiplier (TCM)",
               "Years to Full Compliance (Lag)",
               "Restoration Period (Years)",
               "Time horizon (Tmax)",
               "Baseline Function at Site (%)",
               "Effective Improvement Factor")

  values <- c(
    result$hadd_type,
    result$destruction_area,
    result$median_adjusted_area,
    result$mean_adjusted_area,
    result$confidence_interval[1],
    result$confidence_interval[2],
    result$temporal_comp_multiplier,
    result$time_lag_years,
    result$restoration_period_years,
    result$t_max_years,
    result$baseline_function_pct,
    result$baseline_adjustment
  )

  if (result$hadd_type == "perturbation") {
    metrics <- c(metrics, "Impact Duration (years)", "Recovery Time (years)")
    values  <- c(values,  result$impact_duration_years, result$recovery_time_years)
  } else if (result$hadd_type == "deterioration") {
    metrics <- c(metrics, "Deterioration Percentage (%)")
    values  <- c(values,  result$deterioration_pct)
  }

  writeData(wb, "Summary_Statistics",
            data.frame(Metric = metrics, Value = values))

  addWorksheet(wb, "Simulated_Areas")
  writeData(wb, "Simulated_Areas",
            data.frame(Simulation = seq_along(result$simulated_areas),
                       Area_m2    = result$simulated_areas))

  saveWorkbook(wb, filepath, overwrite = TRUE)
  invisible(NULL)
}


#' Load Shiny App Inputs from an Excel Workbook
#'
#' Reads the three-sheet workbook produced by
#' \code{\link{save_inputs_to_excel}} and returns a structured list suitable
#' for updating Shiny inputs via \code{updateTextInput} etc.
#'
#' @param filepath Character. Path to the \code{.xlsx} file.
#'
#' @return A list with three elements:
#' \item{general}{Named list of general setup parameters.}
#' \item{factor_names}{Data frame with columns \code{Factor}, \code{English},
#'   \code{French}.}
#' \item{factor_values}{Data frame with columns \code{Factor}, \code{Weight},
#'   \code{Destroyed_Min}, \code{Destroyed_Max}, \code{Compensated_Min},
#'   \code{Compensated_Max}.}
#'
#' @importFrom openxlsx loadWorkbook read.xlsx
#' @export
load_inputs_from_excel <- function(filepath) {
  wb <- loadWorkbook(filepath)

  general_data <- read.xlsx(wb, sheet = "General_Setup")
  general_list <- setNames(as.list(general_data$Value), general_data$Parameter)

  factor_names_data  <- read.xlsx(wb, sheet = "Factor_Names")
  factor_values_data <- read.xlsx(wb, sheet = "Factor_Values")

  list(
    general       = general_list,
    factor_names  = factor_names_data,
    factor_values = factor_values_data
  )
}


# --- 6. FILE NAMING UTILITY ---------------------------------------------------

#' Create a Clean Timestamped Filename
#'
#' Sanitises the project title for use in a filename, then combines it with
#' the HADD type, a suffix, and today's date.
#'
#' @param project_title Character. User-supplied project name.
#' @param hadd_type     Character. HADD type string (e.g.
#'                      \code{"destruction"}).
#' @param suffix        Character. File purpose tag (default
#'                      \code{"inputs"}).
#'
#' @return A character string of the form
#'   \code{"<title>_<hadd_type>_<suffix>_<date>.xlsx"}.
#'
#' @examples
#' create_filename("My Seagrass Project", "destruction", "inputs")
#' # "My_Seagrass_Project_destruction_inputs_2025-06-01.xlsx"
#'
#' @export
create_filename <- function(project_title,
                            hadd_type,
                            suffix = "inputs") {
  clean_title <- gsub("[^A-Za-z0-9_-]", "_", project_title)
  clean_title <- gsub("_{2,}", "_", clean_title)
  if (nchar(clean_title) > 30) clean_title <- substr(clean_title, 1, 30)
  if (clean_title == "" || is.null(clean_title)) clean_title <- "project"

  paste0(clean_title, "_", hadd_type, "_", suffix, "_", Sys.Date(), ".xlsx")
}


# --- 7. TEMPORAL COMPENSATION CURVE PLOT --------------------------------------

#' Plot the Temporal Compensation Curve
#'
#' Visualises the year-by-year ecological function ramp-up schedule produced by
#' \code{\link{calculate_tcm_details}}, with vertical lines marking the
#' completion and full-function milestones. Suitable for use both standalone
#' and inside a Shiny \code{renderPlot()} call.
#'
#' @param tcm_details              A list returned by
#'   \code{\link{calculate_tcm_details}}, containing \code{dt_time} and
#'   \code{temporal_comp_multiplier}.
#' @param time_lag_years           Numeric. Years to compensation completion
#'   (used to position the "Completion" annotation).
#' @param restoration_period_years Numeric. Years from completion to full
#'   function (used to position the "Full Function" annotation).
#'
#' @return A \code{ggplot} object.
#'
#' @examples
#' tcm <- calculate_tcm_details(time_lag_years = 2, restoration_period_years = 5)
#' plot_tcm_curve(tcm, time_lag_years = 2, restoration_period_years = 5)
#'
#' @importFrom ggplot2 ggplot aes geom_line geom_vline annotate labs
#'   theme_minimal scale_y_continuous element_text
#' @importFrom data.table data.table
#' @export
plot_tcm_curve <- function(tcm_details,
                           time_lag_years,
                           restoration_period_years) {
  dt      <- tcm_details$dt_time
  T_max   <- max(dt$t) + 1
  T_start <- time_lag_years
  T_end   <- time_lag_years + restoration_period_years
  tcm_val <- round(tcm_details$temporal_comp_multiplier, 3)

  dt_plot <- data.table(
    t     = dt$t,
    Value = dt$BenefitShare,
    Type  = "Proportion of full ecological function"
  )
  y_max <- max(dt_plot$Value, na.rm = TRUE) * 1.15

  ggplot(dt_plot, aes(x = t, y = Value, color = Type)) +
    geom_line(linewidth = 1.2) +
    geom_vline(xintercept = T_start,
               linetype = "dashed", color = "darkgreen", linewidth = 1) +
    geom_vline(xintercept = T_end,
               linetype = "dotted", color = "darkgreen", linewidth = 1) +
    annotate("text", x = T_start, y = y_max * 0.95,
             label = "Completion",    hjust = -0.1,
             color = "darkgreen", size = 4) +
    annotate("text", x = T_end,   y = y_max * 0.80,
             label = "Full Function", hjust = -0.1,
             color = "darkgreen", size = 4) +
    annotate("text", x = T_max * 0.65, y = y_max * 0.4,
             label    = paste0("TCM = ", tcm_val),
             color    = "darkred", size = 5, fontface = "bold") +
    labs(
      title    = "Temporal Compensation Effect (Linear Ramp-up)",
      subtitle = paste0("Time Horizon (Tmax): ", T_max, " years  |  ",
                        "Completion: ", T_start, "y  |  ",
                        "Full Function: ", T_end, "y"),
      x     = "Year (t)",
      y     = "Proportion of full ecological function",
      color = ""
    ) +
    theme_minimal(base_size = 14) +
    scale_y_continuous(limits = c(0, y_max)) +
    theme(legend.position = "bottom",
          plot.title      = element_text(size = 16, face = "bold"),
          plot.subtitle   = element_text(size = 11))
}
