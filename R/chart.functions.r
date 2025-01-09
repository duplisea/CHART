#' Calculate Compensation Area
#'
#' This function performs a Monte Carlo simulation to estimate the required compensation area for habitat destruction.
#' It accounts for multiple ecological factors by simulating scores for the destroyed and compensated habitat areas along specified ranges.
#'
#' @param destruction_area A positive numeric value representing the area (in appropriate units) of habitat destruction.
#' @param factor_ranges_destroyed A list of length 5, where each element is a numeric vector of length 2 specifying the minimum and maximum possible values of each factor for the destroyed habitat.
#' @param factor_ranges_compensated A list of length 5, where each element is a numeric vector of length 2 specifying the minimum and maximum possible values of each factor for the compensated habitat.
#' @param weights A numeric vector of length 5 specifying the relative importance of each ecological factor. The weights will be normalized to sum to 1.
#' @param num_simulations An integer specifying the number of Monte Carlo simulations to run. Default is 5000.
#' @param quantiles A numeric vector specifying the quantiles to use for the confidence interval of the adjusted compensation area. Default is c(0.025, 0.975).
#' @param habitat_names A character vector of length 2 specifying the names of the destroyed and compensated habitats, respectively. Default is c("Destroyed Habitat", "Compensation Habitat").
#' @param factor_names A character vector of length 5 specifying the names of the ecological factors being evaluated. Default is c("factor1", "factor2", "factor3", "factor4", "factor5").
#'
#' @return A list containing the following elements:
#' \item{destruction_area}{The input destruction area.}
#' \item{mean_adjusted_area}{The mean adjusted compensation area based on the simulations.}
#' \item{median_adjusted_area}{The median adjusted compensation area based on the simulations.}
#' \item{sd_adjusted_area}{The standard deviation of the adjusted compensation areas.}
#' \item{confidence_interval}{The confidence interval for the adjusted compensation area based on the specified quantiles.}
#' \item{simulated_areas}{A numeric vector of all simulated compensation areas.}
#' \item{summary_stats}{A summary of the distribution of simulated compensation areas.}
#' \item{habitat_names}{The names of the destroyed and compensated habitats.}
#' \item{factor_names}{The names of the ecological factors.}
#' \item{factor_ranges_destroyed}{The ranges of factor values for the destroyed habitat.}
#' \item{factor_ranges_compensated}{The ranges of factor values for the compensated habitat.}
#' \item{weights}{The normalized weights for each ecological factor.}
#'
#' @details The function simulates habitat destruction and compensation scores across multiple ecological factors and calculates an adjusted compensation area for each simulation. The compensation area is scaled based on the ratio of weighted ecological scores for destroyed and compensated habitats. The function removes any infinite or non-finite simulation results to ensure accurate summary statistics.
#'
#' @examples
#' destruction_area <- 1000
#' factor_ranges_destroyed <- list(c(3, 5), c(2, 4), c(1, 3), c(2, 5), c(4, 5))
#' factor_ranges_compensated <- list(c(1, 2), c(2, 3), c(3, 4), c(1, 3), c(2, 4))
#' weights <- c(0.2, 0.3, 0.1, 0.2, 0.2)
#' calculate_compensation_area(
#'   destruction_area,
#'   factor_ranges_destroyed,
#'   factor_ranges_compensated,
#'   weights,
#'   num_simulations = 1000
#' )
#'
#' @export
calculate_compensation_area <- function(
  destruction_area,
  factor_ranges_destroyed,
  factor_ranges_compensated,
  weights,
  num_simulations = 5000,
  quantiles = c(0.025, 0.975),
  habitat_names = c("Destroyed Habitat", "Compensation Habitat"),
  factor_names = c("factor1", "factor2", "factor3", "factor4", "factor5")
) {
  # Input validation
  if (!is.numeric(destruction_area) || destruction_area <= 0) {
    stop("destruction_area must be a positive number")
  }

  if (!is.list(factor_ranges_destroyed) || length(factor_ranges_destroyed) != 5) {
    stop("factor_ranges_destroyed must be a list of length 5 with named elements for each factor")
  }

  if (!is.list(factor_ranges_compensated) || length(factor_ranges_compensated) != 5) {
    stop("factor_ranges_compensated must be a list of length 5 with named elements for each factor")
  }

  # Rename factor ranges to match factor_names
  names(factor_ranges_destroyed) <- factor_names
  names(factor_ranges_compensated) <- factor_names

  weights <- weights/sum(weights) # standardise them so they sum to 1
  if (length(weights) != 5 || abs(sum(weights) - 1) > 1e-10) {
    stop("weights must be a vector of length 5")
  }

  # Initialize simulation results
  simulated_areas <- numeric(num_simulations)

  # Monte Carlo simulation
  for (i in 1:num_simulations) {
    # Sample values for destroyed habitat from the specified ranges
    destroyed_scores <- sapply(factor_ranges_destroyed, function(range) runif(1, range[1], range[2]))

    # Sample values for compensated habitat from the specified ranges
    compensated_scores <- sapply(factor_ranges_compensated, function(range) runif(1, range[1], range[2]))

    # Calculate weighted scores
    destroyed_weighted <- sum(destroyed_scores * weights)
    compensated_weighted <- sum(compensated_scores * weights)

    # Calculate adjusted area
    simulated_areas[i] <- destruction_area * (destroyed_weighted / compensated_weighted)
  }

  # Remove any NA or infinite values
  simulated_areas <- simulated_areas[is.finite(simulated_areas)]

  # Calculate statistics
  ci <- quantile(simulated_areas, quantiles, na.rm = TRUE)

  # Return comprehensive results
  list(
    destruction_area = destruction_area,
    mean_adjusted_area = mean(simulated_areas, na.rm = TRUE),
    median_adjusted_area = median(simulated_areas, na.rm = TRUE),
    sd_adjusted_area = sd(simulated_areas, na.rm = TRUE),
    confidence_interval = ci,
    simulated_areas = simulated_areas,
    summary_stats = summary(simulated_areas),
    habitat_names = habitat_names,  # Add habitat names
    factor_names = factor_names,  # Add factor names
    factor_ranges_destroyed = factor_ranges_destroyed,  # Add factor ranges for destroyed habitat
    factor_ranges_compensated = factor_ranges_compensated,  # Add factor ranges for compensated habitat
    weights = weights

  )
}

#' Plot Compensation Analysis Results
#'
#' This function generates visualizations based on the results of the compensation area analysis.
#' The plots provide a summary of ecological factor comparisons, compensation area requirements, and the distribution of simulated compensation areas.
#'
#' @param result A list containing the output of the `calculate_compensation_area` function. It must include the following fields:
#' - `habitat_names`: A character vector of length 2 specifying the names of the destroyed and compensated habitats.
#' - `factor_ranges_destroyed`: A list of length 5 specifying the factor ranges for the destroyed habitat.
#' - `factor_ranges_compensated`: A list of length 5 specifying the factor ranges for the compensated habitat.
#' - `factor_names`: A character vector of length 5 specifying the names of the ecological factors.
#' - `weights`: A numeric vector of length 5 specifying the weights for each factor.
#' - `simulated_areas`: A numeric vector containing simulated compensation areas.
#' - `destruction_area`: A numeric value representing the initial destruction area.
#' - `median_adjusted_area`: The median adjusted compensation area from the simulations.
#'
#' @param quantiles A numeric vector specifying the quantiles for the confidence interval of the compensation area. Default is `c(0.025, 0.975)` (i.e., 95% confidence interval).
#'
#' @return A combined plot (using `patchwork`) with three subplots:
#' \item{Factor Comparison Plot}{A bar plot comparing the mean values of ecological factors between the destroyed and compensated habitats, with error bars showing factor ranges.}
#' \item{Area Comparison Plot}{A horizontal bar chart showing the destruction area and the required compensation area, with a confidence interval.}
#' \item{Distribution Plot}{A density plot showing the distribution of simulated compensation areas, with vertical lines for the median and confidence interval bounds.}
#'
#' @details The function visualizes three key components:
#' - **Factor Comparison Plot**: Shows the mean, minimum, and maximum values of ecological factors for both habitats.
#' - **Area Comparison Plot**: Compares the habitat destruction area (HADD) to the required compensation area.
#' - **Distribution Plot**: Displays the distribution of compensation area values generated by the Monte Carlo simulation.
#'
#' The plots are arranged vertically using the `patchwork` library.
#'
#' @examples
#' # Example usage:
#' result <- list(
#'   destruction_area = 1000,
#'   simulated_areas = rnorm(1000, mean = 1500, sd = 300),
#'   median_adjusted_area = 1500,
#'   habitat_names = c("Destroyed Habitat", "Compensation Habitat"),
#'   factor_names = c("Productivity", "Biodiversity", "Resilience", "Connectivity", "Complexity"),
#'   factor_ranges_destroyed = list(c(3, 5), c(2, 4), c(1, 3), c(2, 5), c(4, 5)),
#'   factor_ranges_compensated = list(c(1, 2), c(2, 3), c(3, 4), c(1, 3), c(2, 4)),
#'   weights = c(0.2, 0.3, 0.1, 0.2, 0.2)
#' )
#' plot_compensation_analysis(result)
#'
#' @importFrom ggplot2 ggplot aes geom_bar geom_errorbar labs theme_minimal scale_fill_brewer
#' @importFrom patchwork plot_layout plot_annotation
#' @export
plot_compensation_analysis <- function(result, quantiles = c(0.025, 0.975)) {
  # Extract and validate habitat names
  habitat_names <- result$habitat_names
  if (is.null(habitat_names) || length(habitat_names) != 2) {
    stop("The result object must contain a valid 'habitat_names' field with exactly two names.")
  }

  # Extract and validate factor ranges
  factor_ranges_destroyed <- result$factor_ranges_destroyed
  factor_ranges_compensated <- result$factor_ranges_compensated
  if (is.null(factor_ranges_destroyed) || is.null(factor_ranges_compensated)) {
    stop("The result object must contain valid 'factor_ranges_destroyed' and 'factor_ranges_compensated' fields.")
  }

  # Extract and validate factor names
  factor_names <- result$factor_names
  if (is.null(factor_names) || length(factor_names) != 5) {
    stop("The result object must contain valid 'factor_names' with exactly five names.")
  }

  # Extract weights
  weights <- result$weights
  if (is.null(weights) || length(weights) != 5) {
    stop("The result object must contain valid 'weights' of length 5.")
  }

  # Manually construct factor_data to ensure correct alignment
  factor_data <- data.frame(
    Factor = rep(factor_names, times = 2),  # Repeat factor names for each habitat
    Habitat = rep(habitat_names, each = length(factor_names)),  # Repeat habitat names
    Value = c(
      unlist(lapply(factor_ranges_destroyed, mean)),  # Mean of destroyed habitat ranges
      unlist(lapply(factor_ranges_compensated, mean)) # Mean of compensated habitat ranges
    ),
    Lower = c(
      unlist(lapply(factor_ranges_destroyed, function(range) range[1])),  # Lower bounds for destroyed habitat
      unlist(lapply(factor_ranges_compensated, function(range) range[1])) # Lower bounds for compensated habitat
    ),
    Upper = c(
      unlist(lapply(factor_ranges_destroyed, function(range) range[2])),  # Upper bounds for destroyed habitat
      unlist(lapply(factor_ranges_compensated, function(range) range[2])) # Upper bounds for compensated habitat
    ),
    Alpha = rep(weights, times = 2)  # Repeat weights for both habitats
  )

  # Create factor comparison plot
# Custom rescaling function to spread alpha values across the range 0.3 to 1
rescale_alpha <- function(alpha) {
  max_alpha <- max(alpha[alpha > 0])  # Get the max non-zero alpha value
  scaled_alpha <- ifelse(alpha == 0, 0, alpha / max_alpha)  # Normalize non-zero alpha
  0.3 + (scaled_alpha * 0.7)  # Rescale normalized alpha to range 0.3 to 1
}

# Plot with updated alpha scaling
p1 <- ggplot(factor_data, aes(x = Factor, y = Value, fill = Habitat, alpha = rescale_alpha(Alpha))) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7, aes(colour = Habitat), linewidth = 0.7) +
  geom_errorbar(aes(ymin = Lower, ymax = Upper),
                position = position_dodge(width = 0.8),
                width = 0.2, linewidth = 1) +  # Align error bars with bars
  scale_fill_brewer(palette = "Set2") +
  scale_colour_brewer(palette = "Set2", guide = "none") +  # Match outlines to the bar colors
  scale_alpha_identity(guide = "none") +  # Use the raw alpha values after rescaling
  labs(
    title = "Ecosystem services by habitat type",
    x = "Ecosystem service factor",
    y = "Contribution score (user input)",
    fill = "Habitat"
  ) +
  theme_minimal(base_size = 20) +
  theme(legend.position = "top") +
  scale_y_continuous(limits = c(0, 5))  # Keep y-axis limit fixed


  # Calculate quantiles for area comparison
  area_quantiles <- quantile(result$simulated_areas, probs = quantiles, na.rm = TRUE)

  # Area comparison plot (horizontal bar chart)
  comparison_data <- data.frame(
    Habitat = habitat_names,
    Area = c(result$destruction_area, result$median_adjusted_area),
    Lower = c(NA, area_quantiles[1]),
    Upper = c(NA, area_quantiles[2])
  )

  p2 <- ggplot(comparison_data, aes(y = Habitat, x = Area, fill = Habitat)) +
    geom_col(alpha = 0.7) +
    geom_errorbar(aes(xmin = Lower, xmax = Upper),
                  width = 0.2, linewidth = 1, color = "black", na.rm = TRUE) +
    scale_fill_brewer(palette = "Set2") +
    labs(
      title = "HADD & required compensation area",
      y = "Habitat type",
      x = expression(Area~(m^2))
    ) +
    theme_minimal(base_size = 20) +
    theme(legend.position = "none")

  # Distribution plot
  p3 <- ggplot(data.frame(Area = result$simulated_areas), aes(x = Area)) +
    geom_density(fill = "lightblue", alpha = 0.5) +
    geom_vline(xintercept = result$median_adjusted_area,
               linetype = "dashed", color = "darkred", linewidth = 1) +
    geom_vline(xintercept = area_quantiles,
               linetype = "dotted", color = "darkgreen", linewidth = 1) +
    labs(
      title = "Distribution of required compensation area",
      x = expression(Area~(m^2)),
      y = "Density"
    ) +
    theme_minimal(base_size = 20)

  # Combine plots
  combined_plot <- p1 / p2 / p3 +
    plot_layout(heights = c(1, 1, 1)) +
    plot_annotation(
      title = "Fish Habitat Compensation Analysis",
      subtitle = paste("Based on", format(result$destruction_area, big.mark = ","),
                       "m² HADD in Zostera"),
      theme = theme_minimal(base_size = 25)
    )

  return(combined_plot)
}
