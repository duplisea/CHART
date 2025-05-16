library(shiny)
library(ggplot2)
library(patchwork)

# Define the calculation function
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
    habitat_names = habitat_names,
    factor_names = factor_names,
    factor_ranges_destroyed = factor_ranges_destroyed,
    factor_ranges_compensated = factor_ranges_compensated,
    weights = weights
  )
}

# Define the English plotting function
plot_compensation_analysis_en <- function(result, quantiles = c(0.025, 0.975)) {
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
                       "m² HADD in", result$habitat_names[1]),
      theme = theme_minimal(base_size = 25)
    )

  return(combined_plot)
}

# Define the French plotting function
plot_compensation_analysis_fr <- function(result, quantiles = c(0.025, 0.975)) {
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
      title = "Services écosystémiques par type d'habitat",
      x = "Facteur de service écosystémique",
      y = "Score de contribution (entrée utilisateur)",
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
      title = "HADD et zone de compensation requise",
      y = "Type d'habitat",
      x = expression(Surface~(m^2))
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
      title = "Distribution de la zone de compensation requise",
      x = expression(Surface~(m^2)),
      y = "Densité"
    ) +
    theme_minimal(base_size = 20)

  # Combine plots
  combined_plot <- p1 / p2 / p3 +
    plot_layout(heights = c(1, 1, 1)) +
    plot_annotation(
      title = "Analyse de compensation d'habitat de poisson",
      subtitle = paste("Basé sur", format(result$destruction_area, big.mark = ","),
                       "m² HADD dans", result$habitat_names[1]),
      theme = theme_minimal(base_size = 25)
    )

  return(combined_plot)
}

ui <- fluidPage(
  titlePanel(
    div(
      span("Compensation Area Calculator", style = "color: black;"),
      " / ",
      span("Calculateur de zone de compensation", style = "color: #00008B;")
    )
  ),

  tabsetPanel(
    # DESCRIPTION TAB
    tabPanel(
      "Description / Description",
      fluidRow(
        column(
          width = 12,
          h2("About CHART / À propos de CHART"),
          hr()
        )
      ),

      fluidRow(
        # English description
        column(
          width = 6,
          h3("Summary"),
          p("A simulation tool has been developed to support decision-making on fish habitat compensation projects in Canada consistent with the Fisheries Act. The tool considers the fish habitat support capacity of the HADD habitat and the potential compensation habitat along several axes. Those capacities are scored on a Likert Scale from 0 to 5 along each axis by an analyst using evidence from the scientific literature, previous compensation projects and expert knowledge. The analyst also scores the relative importance of each axis for its contribution the decision making process on compensation. Simulations are performed accounting for the uncertainty in the scores provided by the analysts and a distribution of compensation ratios results to inform the scale of the compensation project(s) required to offset the HADD. The distribution of outcomes allows the work to be interpreted within a risk framework consistent with policy following from the Fisheries Act. In addition to considering direct compensation projects, this tool can be used to derive compensation ratios between any number of habitat pairs as well as determine the compensation value of previously banked habitats at the time of 'withdrawal' to offset a HADD."),

          h3("Acronym and explanation"),
          p(strong("C.H.A.R.T. – Compensation Habitat Assessment and Ratio Tool")),
          tags$ul(
            tags$li("Compensation: the primary focus of the tool."),
            tags$li("Habitat: central to the Fisheries Act mandate."),
            tags$li("Assessment: structured scoring approach."),
            tags$li("Ratio: derived compensation ratios between habitat pairs."),
            tags$li("Tool: decision-support simulation framework.")
          ),

          h3("Introduction"),
          p("Under the Fisheries Act, any work undertaking or activity (WUA - see definition below) resulting in a harmful alteration, disruption or destruction of fish habitat (HADD see definition below) above a threshold level requires compensation/offset. The ecosystem service factor (ESF) considered in the compensation are partially outlined in the Fisheries Act but not all potential ESFs. The method outlined here is an example of how various ESFs could be integrated in a scoring-based approach to determine the scale of compensation required given the characteristics of the HADD owing to a WUA and the proposed compensation project to offset that HADD. Thus, this decision support tool was developed to make that process more transparent and to include uncertainty in knowledge of the biological processes."),

          div(
            style = "background-color: #f8f8f8; padding: 10px; border-left: 4px solid #ccc; margin-bottom: 20px;",
            h4("Disclaimer"),
            p("This is just a proof of concept and not based on data, a thorough review of the literature or knowledge from multiple experts. It is designed to show how a decision-making process could include a scoring-based tool as support to inform the scale of the compensation project required to offset a HADD. This should not be used as is and needs proper checking and parameterisation before real-world usage.")
          )
        ),

        # French description
        column(
          width = 6,
          h3("Sommaire", style = "color: #003366;"),
          p(style = "color: #003366;", "Un outil de simulation a été développé pour soutenir la prise de décision dans les projets de compensation d'habitats pour les poissons au Canada, conformément à la Loi sur les pêches. L'outil prend en compte la capacité de soutien de l'habitat HADD et de l'habitat de compensation potentiel selon plusieurs axes. Ces capacités sont évaluées sur une échelle de Likert de 0 à 5 pour chaque axe par un analyste, en s'appuyant sur des données issues de la littérature scientifique, des projets de compensation précédents et des connaissances expertes. L'analyste attribue également un score à l'importance relative de chaque axe en fonction de sa contribution au processus décisionnel en matière de compensation. Des simulations sont réalisées en tenant compte de l'incertitude des scores fournis par les analystes, et une distribution des ratios de compensation en résulte pour informer l'ampleur des projets de compensation nécessaires afin de compenser le HADD. La distribution des résultats permet d'interpréter le travail dans un cadre de gestion des risques conforme à la politique découlant de la Loi sur les pêches. En plus d'évaluer les projets de compensation directs, cet outil peut être utilisé pour dériver des ratios de compensation entre plusieurs paires d'habitats et pour déterminer la valeur de compensation d'habitats préalablement « bancarisés » lors de leur « retrait » afin de compenser un HADD."),

          h3("Acronyme et explication", style = "color: #003366;"),
          p(style = "color: #003366;", strong("C.H.A.R.T. – Compensation, Habitat, Analyse, Ratios, et Trame")),
          tags$ul(
            tags$li(style = "color: #003366;", "Compensation : l'objectif principal de l'outil."),
            tags$li(style = "color: #003366;", "Habitat : central au mandat de la Loi sur les pêches."),
            tags$li(style = "color: #003366;", "Analyse : approche structurée de notation des critères."),
            tags$li(style = "color: #003366;", "Ratios : ratios de compensation dérivés entre les habitats comparés."),
            tags$li(style = "color: #003366;", "Trame : cadre de simulation et de soutien à la prise de décision.")
          ),

          h3("Introduction", style = "color: #003366;"),
          p(style = "color: #003366;", "En vertu de la Loi sur les pêches, tout travail, entreprise ou activité (WUA - voir définition ci-dessous) entraînant une détérioration, perturbation ou destruction nuisible de l'habitat du poisson (HADD voir définition ci-dessous) au-dessus d'un niveau seuil nécessite une compensation/compensation. Le facteur de service écosystémique (ESF) pris en compte dans la compensation est partiellement décrit dans la Loi sur les pêches, mais pas tous les ESF potentiels. La méthode décrite ici est un exemple de la façon dont divers ESF pourraient être intégrés dans une approche basée sur la notation pour déterminer l'échelle de compensation requise compte tenu des caractéristiques du HADD dû à un WUA et du projet de compensation proposé pour compenser ce HADD. Ainsi, cet outil d'aide à la décision a été développé pour rendre ce processus plus transparent et pour inclure l'incertitude dans la connaissance des processus biologiques."),

          div(
            style = "background-color: #f8f8f8; padding: 10px; border-left: 4px solid #ccc; margin-bottom: 20px; color: #003366;",
            h4("Avertissement", style = "color: #003366;"),
            p(style = "color: #003366;", "Il ne s'agit que d'une preuve de concept qui n'est pas basée sur des données, une revue approfondie de la littérature ou les connaissances de plusieurs experts. Il est conçu pour montrer comment un processus de prise de décision pourrait inclure un outil basé sur la notation pour soutenir l'information sur l'échelle du projet de compensation nécessaire pour compenser un HADD. Cela ne devrait pas être utilisé tel quel et nécessite une vérification et un paramétrage appropriés avant une utilisation dans le monde réel.")
          )
        )
      )
    ),

    # User Input Tab
    tabPanel(
      div(
        span("User Input", style = "color: black;"),
        " / ",
        span("Entrée utilisateur", style = "color: #00008B;")
      ),

      fluidRow(
        column(12, align = "center",
          br(),
          actionButton("calculate",
                      div(
                        span("Calculate Compensation Area", style = "color: black;"),
                        " / ",
                        span("Calculer la zone de compensation", style = "color: #00008B;")
                      ),
                      class = "btn-primary btn-lg")
        )
      ),

      hr(),

      fluidRow(
        column(6,
          h4(div(
            span("Basic Parameters", style = "color: black;"),
            " / ",
            span("Paramètres de base", style = "color: #00008B;")
          )),

          numericInput("destruction_area",
                      div(
                        span("Destruction Area (m²)", style = "color: black;"),
                        " / ",
                        span("Zone de destruction (m²)", style = "color: #00008B;")
                      ),
                      value = 1000, min = 0),

          textInput("destroyed_habitat_name",
                   div(
                     span("Destroyed Habitat Name", style = "color: black;"),
                     " / ",
                     span("Nom de l'habitat détruit", style = "color: #00008B;")
                   ),
                   value = "Zostera"),

          textInput("compensated_habitat_name",
                   div(
                     span("Compensation Habitat Name", style = "color: black;"),
                     " / ",
                     span("Nom de l'habitat de compensation", style = "color: #00008B;")
                   ),
                   value = "Compensation Habitat"),

          hr(),

          h4(div(
            span("Factor Names", style = "color: black;"),
            " / ",
            span("Noms des facteurs", style = "color: #00008B;")
          )),

          textInput("factor1_name",
                   div(
                     span("Factor 1 Name", style = "color: black;"),
                     " / ",
                     span("Nom du facteur 1", style = "color: #00008B;")
                   ),
                   value = "Productivity"),

          textInput("factor2_name",
                   div(
                     span("Factor 2 Name", style = "color: black;"),
                     " / ",
                     span("Nom du facteur 2", style = "color: #00008B;")
                   ),
                   value = "Biodiversity"),

          textInput("factor3_name",
                   div(
                     span("Factor 3 Name", style = "color: black;"),
                     " / ",
                     span("Nom du facteur 3", style = "color: #00008B;")
                   ),
                   value = "Resilience"),

          textInput("factor4_name",
                   div(
                     span("Factor 4 Name", style = "color: black;"),
                     " / ",
                     span("Nom du facteur 4", style = "color: #00008B;")
                   ),
                   value = "Connectivity"),

          textInput("factor5_name",
                   div(
                     span("Factor 5 Name", style = "color: black;"),
                     " / ",
                     span("Nom du facteur 5", style = "color: #00008B;")
                   ),
                   value = "Complexity")
        ),

        column(6,
          h4(div(
            span("Factor Weights", style = "color: black;"),
            " / ",
            span("Poids des facteurs", style = "color: #00008B;")
          )),

          uiOutput("factor1_weight_ui"),
          uiOutput("factor2_weight_ui"),
          uiOutput("factor3_weight_ui"),
          uiOutput("factor4_weight_ui"),
          uiOutput("factor5_weight_ui")
        )
      ),

      hr(),

      fluidRow(
        column(6,
          h4(div(
            span("Destroyed Habitat Scores", style = "color: black;"),
            " / ",
            span("Scores d'habitat détruit", style = "color: #00008B;")
          )),

          # Factor 1 Destroyed
          h5(uiOutput("factor1_destroyed_label")),
          fluidRow(
            column(6, numericInput("factor1_destroyed_min",
                                  div(
                                    span("Min", style = "color: black;"),
                                    " / ",
                                    span("Min", style = "color: #00008B;")
                                  ),
                                  value = 3, min = 0, max = 5)),
            column(6, numericInput("factor1_destroyed_max",
                                  div(
                                    span("Max", style = "color: black;"),
                                    " / ",
                                    span("Max", style = "color: #00008B;")
                                  ),
                                  value = 5, min = 0, max = 5))
          ),

          # Factor 2 Destroyed
          h5(uiOutput("factor2_destroyed_label")),
          fluidRow(
            column(6, numericInput("factor2_destroyed_min",
                                  div(
                                    span("Min", style = "color: black;"),
                                    " / ",
                                    span("Min", style = "color: #00008B;")
                                  ),
                                  value = 2, min = 0, max = 5)),
            column(6, numericInput("factor2_destroyed_max",
                                  div(
                                    span("Max", style = "color: black;"),
                                    " / ",
                                    span("Max", style = "color: #00008B;")
                                  ),
                                  value = 4, min = 0, max = 5))
          ),

          # Factor 3 Destroyed
          h5(uiOutput("factor3_destroyed_label")),
          fluidRow(
            column(6, numericInput("factor3_destroyed_min",
                                  div(
                                    span("Min", style = "color: black;"),
                                    " / ",
                                    span("Min", style = "color: #00008B;")
                                  ),
                                  value = 1, min = 0, max = 5)),
            column(6, numericInput("factor3_destroyed_max",
                                  div(
                                    span("Max", style = "color: black;"),
                                    " / ",
                                    span("Max", style = "color: #00008B;")
                                  ),
                                  value = 3, min = 0, max = 5))
          ),

          # Factor 4 Destroyed
          h5(uiOutput("factor4_destroyed_label")),
          fluidRow(
            column(6, numericInput("factor4_destroyed_min",
                                  div(
                                    span("Min", style = "color: black;"),
                                    " / ",
                                    span("Min", style = "color: #00008B;")
                                  ),
                                  value = 2, min = 0, max = 5)),
            column(6, numericInput("factor4_destroyed_max",
                                  div(
                                    span("Max", style = "color: black;"),
                                    " / ",
                                    span("Max", style = "color: #00008B;")
                                  ),
                                  value = 5, min = 0, max = 5))
          ),

          # Factor 5 Destroyed
          h5(uiOutput("factor5_destroyed_label")),
          fluidRow(
            column(6, numericInput("factor5_destroyed_min",
                                  div(
                                    span("Min", style = "color: black;"),
                                    " / ",
                                    span("Min", style = "color: #00008B;")
                                  ),
                                  value = 4, min = 0, max = 5)),
            column(6, numericInput("factor5_destroyed_max",
                                  div(
                                    span("Max", style = "color: black;"),
                                    " / ",
                                    span("Max", style = "color: #00008B;")
                                  ),
                                  value = 5, min = 0, max = 5))
          )
        ),

        # Add this after the destruction_area input
        numericInput("num_simulations",
            div(
              span("Number of Simulations", style = "color: black;"),
              " / ",
              span("Nombre de simulations", style = "color: #00008B;")
            ),
            value = 5000, min = 100, max = 20000, step = 100),

        column(6,
          h4(div(
            span("Compensation Habitat Scores", style = "color: black;"),
            " / ",
            span("Scores d'habitat de compensation", style = "color: #00008B;")
          )),

          # Factor 1 Compensated
          h5(uiOutput("factor1_compensated_label")),
          fluidRow(
            column(6, numericInput("factor1_compensated_min",
                                 div(
                                   span("Min", style = "color: black;"),
                                   " / ",
                                   span("Min", style = "color: #00008B;")
                                 ),
                                 value = 1, min = 0, max = 5)),
            column(6, numericInput("factor1_compensated_max",
                                 div(
                                   span("Max", style = "color: black;"),
                                   " / ",
                                   span("Max", style = "color: #00008B;")
                                 ),
                                 value = 2, min = 0, max = 5))
          ),

          # Factor 2 Compensated
          h5(uiOutput("factor2_compensated_label")),
          fluidRow(
            column(6, numericInput("factor2_compensated_min",
                                 div(
                                   span("Min", style = "color: black;"),
                                   " / ",
                                   span("Min", style = "color: #00008B;")
                                 ),
                                 value = 2, min = 0, max = 5)),
            column(6, numericInput("factor2_compensated_max",
                                 div(
                                   span("Max", style = "color: black;"),
                                   " / ",
                                   span("Max", style = "color: #00008B;")
                                 ),
                                 value = 3, min = 0, max = 5))
          ),

          # Factor 3 Compensated
          h5(uiOutput("factor3_compensated_label")),
          fluidRow(
            column(6, numericInput("factor3_compensated_min",
                                 div(
                                   span("Min", style = "color: black;"),
                                   " / ",
                                   span("Min", style = "color: #00008B;")
                                 ),
                                 value = 3, min = 0, max = 5)),
            column(6, numericInput("factor3_compensated_max",
                                 div(
                                   span("Max", style = "color: black;"),
                                   " / ",
                                   span("Max", style = "color: #00008B;")
                                 ),
                                 value = 4, min = 0, max = 5))
          ),

          # Factor 4 Compensated
          h5(uiOutput("factor4_compensated_label")),
          fluidRow(
            column(6, numericInput("factor4_compensated_min",
                                 div(
                                   span("Min", style = "color: black;"),
                                   " / ",
                                   span("Min", style = "color: #00008B;")
                                 ),
                                 value = 1, min = 0, max = 5)),
            column(6, numericInput("factor4_compensated_max",
                                 div(
                                   span("Max", style = "color: black;"),
                                   " / ",
                                   span("Max", style = "color: #00008B;")
                                 ),
                                 value = 3, min = 0, max = 5))
          ),

          # Factor 5 Compensated
          h5(uiOutput("factor5_compensated_label")),
          fluidRow(
            column(6, numericInput("factor5_compensated_min",
                                 div(
                                   span("Min", style = "color: black;"),
                                   " / ",
                                   span("Min", style = "color: #00008B;")
                                 ),
                                 value = 2, min = 0, max = 5)),
            column(6, numericInput("factor5_compensated_max",
                                 div(
                                   span("Max", style = "color: black;"),
                                   " / ",
                                   span("Max", style = "color: #00008B;")
                                 ),
                                 value = 4, min = 0, max = 5))
          )
        )
      )
    ),

    # Results - English Tab
    tabPanel(
      "Results - English",
      plotOutput("compensation_plot_en", height = "900px"),

      br(),

      fluidRow(
        column(6,
          h4("Summary Statistics"),
          verbatimTextOutput("summary_stats_en")
        ),
        column(6,
          h4("Required Compensation Area"),
          verbatimTextOutput("compensation_result_en")
        )
      )
    ),

    # Results - French Tab
    tabPanel(
      "Résultats - Français",
      plotOutput("compensation_plot_fr", height = "900px"),

      br(),

      fluidRow(
        column(6,
          h4("Statistiques résumées", style = "color: #003366;"),
          verbatimTextOutput("summary_stats_fr")
        ),
        column(6,
          h4("Zone de compensation requise", style = "color: #003366;"),
          verbatimTextOutput("compensation_result_fr")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Dynamic UI for factor weights with labels matching input names
  output$factor1_weight_ui <- renderUI({
    sliderInput("factor1_weight",
               div(
                 span(paste(input$factor1_name, "Weight"), style = "color: black;"),
                 " / ",
                 span(paste("Poids de", input$factor1_name), style = "color: #00008B;")
               ),
               min = 0, max = 1, value = 0.2, step = 0.05)
  })

  output$factor2_weight_ui <- renderUI({
    sliderInput("factor2_weight",
               div(
                 span(paste(input$factor2_name, "Weight"), style = "color: black;"),
                 " / ",
                 span(paste("Poids de", input$factor2_name), style = "color: #00008B;")
               ),
               min = 0, max = 1, value = 0.3, step = 0.05)
  })

  output$factor3_weight_ui <- renderUI({
    sliderInput("factor3_weight",
               div(
                 span(paste(input$factor3_name, "Weight"), style = "color: black;"),
                 " / ",
                 span(paste("Poids de", input$factor3_name), style = "color: #00008B;")
               ),
               min = 0, max = 1, value = 0.1, step = 0.05)
  })

  output$factor4_weight_ui <- renderUI({
    sliderInput("factor4_weight",
               div(
                 span(paste(input$factor4_name, "Weight"), style = "color: black;"),
                 " / ",
                 span(paste("Poids de", input$factor4_name), style = "color: #00008B;")
               ),
               min = 0, max = 1, value = 0.2, step = 0.05)
  })

  output$factor5_weight_ui <- renderUI({
    sliderInput("factor5_weight",
               div(
                 span(paste(input$factor5_name, "Weight"), style = "color: black;"),
                 " / ",
                 span(paste("Poids de", input$factor5_name), style = "color: #00008B;")
               ),
               min = 0, max = 1, value = 0.2, step = 0.05)
  })

  # Dynamic labels for factor inputs
  output$factor1_destroyed_label <- renderUI({
    div(
      span(paste(input$factor1_name, "- Destroyed Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor1_name, "- Habitat détruit"), style = "color: #00008B;")
    )
  })

  output$factor2_destroyed_label <- renderUI({
    div(
      span(paste(input$factor2_name, "- Destroyed Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor2_name, "- Habitat détruit"), style = "color: #00008B;")
    )
  })

  output$factor3_destroyed_label <- renderUI({
    div(
      span(paste(input$factor3_name, "- Destroyed Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor3_name, "- Habitat détruit"), style = "color: #00008B;")
    )
  })

  output$factor4_destroyed_label <- renderUI({
    div(
      span(paste(input$factor4_name, "- Destroyed Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor4_name, "- Habitat détruit"), style = "color: #00008B;")
    )
  })

  output$factor5_destroyed_label <- renderUI({
    div(
      span(paste(input$factor5_name, "- Destroyed Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor5_name, "- Habitat détruit"), style = "color: #00008B;")
    )
  })

  output$factor1_compensated_label <- renderUI({
    div(
      span(paste(input$factor1_name, "- Compensation Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor1_name, "- Habitat de compensation"), style = "color: #00008B;")
    )
  })

  output$factor2_compensated_label <- renderUI({
    div(
      span(paste(input$factor2_name, "- Compensation Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor2_name, "- Habitat de compensation"), style = "color: #00008B;")
    )
  })

  output$factor3_compensated_label <- renderUI({
    div(
      span(paste(input$factor3_name, "- Compensation Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor3_name, "- Habitat de compensation"), style = "color: #00008B;")
    )
  })

  output$factor4_compensated_label <- renderUI({
    div(
      span(paste(input$factor4_name, "- Compensation Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor4_name, "- Habitat de compensation"), style = "color: #00008B;")
    )
  })

  output$factor5_compensated_label <- renderUI({
    div(
      span(paste(input$factor5_name, "- Compensation Habitat"), style = "color: black;"),
      " / ",
      span(paste(input$factor5_name, "- Habitat de compensation"), style = "color: #00008B;")
    )
  })

  # Main calculation results
  result <- eventReactive(input$calculate, {
    # Collect factor names
    factor_names <- c(
      input$factor1_name,
      input$factor2_name,
      input$factor3_name,
      input$factor4_name,
      input$factor5_name
    )

    # Collect habitat names
    habitat_names <- c(
      input$destroyed_habitat_name,
      input$compensated_habitat_name
    )

    # Collect factor ranges for destroyed habitat
    factor_ranges_destroyed <- list(
      c(input$factor1_destroyed_min, input$factor1_destroyed_max),
      c(input$factor2_destroyed_min, input$factor2_destroyed_max),
      c(input$factor3_destroyed_min, input$factor3_destroyed_max),
      c(input$factor4_destroyed_min, input$factor4_destroyed_max),
      c(input$factor5_destroyed_min, input$factor5_destroyed_max)
    )

    # Collect factor ranges for compensated habitat
    factor_ranges_compensated <- list(
      c(input$factor1_compensated_min, input$factor1_compensated_max),
      c(input$factor2_compensated_min, input$factor2_compensated_max),
      c(input$factor3_compensated_min, input$factor3_compensated_max),
      c(input$factor4_compensated_min, input$factor4_compensated_max),
      c(input$factor5_compensated_min, input$factor5_compensated_max)
    )

    # Collect weights
    weights <- c(
      input$factor1_weight,
      input$factor2_weight,
      input$factor3_weight,
      input$factor4_weight,
      input$factor5_weight
    )

    # Validate weights sum to approximately 1
    if (abs(sum(weights) - 1) > 0.01) {
      weights <- weights / sum(weights)  # Normalize weights
    }

    # Call the calculation function
    calculate_compensation_area(
      destruction_area = input$destruction_area,
      factor_ranges_destroyed = factor_ranges_destroyed,
      factor_ranges_compensated = factor_ranges_compensated,
      weights = weights,
      num_simulations = input$num_simulations,
      quantiles = c(0.025, 0.975),
      habitat_names = habitat_names,
      factor_names = factor_names
    )
  })

  # English plot output
  output$compensation_plot_en <- renderPlot({
    req(result())
    plot_compensation_analysis_en(result(), quantiles = c(0.025, 0.975))
  })

  # French plot output
  output$compensation_plot_fr <- renderPlot({
    req(result())
    plot_compensation_analysis_fr(result(), quantiles = c(0.025, 0.975))
  })

  # English summary statistics
  output$summary_stats_en <- renderPrint({
    req(result())
    result()$summary_stats
  })

  # French summary statistics
  output$summary_stats_fr <- renderPrint({
    req(result())
    result()$summary_stats
  })

  # English compensation result
  output$compensation_result_en <- renderPrint({
    req(result())
    cat("Mean: ", format(result()$mean_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("Median: ", format(result()$median_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("Standard Deviation: ", format(result()$sd_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("95% Confidence Interval: \n")
    cat("  Lower: ", format(result()$confidence_interval[1], big.mark = ","), " m²\n", sep = "")
    cat("  Upper: ", format(result()$confidence_interval[2], big.mark = ","), " m²\n", sep = "")
  })

  # French compensation result
  output$compensation_result_fr <- renderPrint({
    req(result())
    cat("Moyenne: ", format(result()$mean_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("Médiane: ", format(result()$median_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("Écart-type: ", format(result()$sd_adjusted_area, big.mark = ","), " m²\n", sep = "")
    cat("Intervalle de confiance à 95%: \n")
    cat("  Inférieur: ", format(result()$confidence_interval[1], big.mark = ","), " m²\n", sep = "")
    cat("  Supérieur: ", format(result()$confidence_interval[2], big.mark = ","), " m²\n", sep = "")
  })
}

shinyApp(ui = ui, server = server)
