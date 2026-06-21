# scripts/simulate data.R
# stand alone file to simulate data for this example
# Data simulated by simulate_suurveillance_data() to produce weekly ILI case
# counts for 6 counties

# Uses here::here() throughout so it runs correctly no matter what your
# working directory is when you call it -- no setwd() needed. here::here()
# finds the project root by locating ili-surveillance-project.Rproj.


#load mutiple libraries in single call using pacman library p_load function
pacman::p_load(
  tidyverse,
  here)


#' Simulate weekly ILI case counts for a set of counties
#'
#' @param counties character vector of county names
#' @param populations numeric vector of populations, same order as counties
#' @param n_weeks number of weeks of history to simulate
#' @param outbreak_counties counties that should show a simulated late spike
#' @param seed random seed, for reproducibility
#' @return tibble with columns: county, population, week, cases
simulate_surveillance_data <- function(counties,
                                       populations,
                                       n_weeks = 12,
                                       outbreak_counties = character(0),
                                       seed = 42) {
  set.seed(seed)
  
  county_lookup <- tibble(county = counties, population = populations)
  
  surveillance <- county_lookup %>%
    rowwise() %>%
    mutate(
      week_data = list(
        tibble(
          week = 1:n_weeks,
          # Baseline cases scale loosely with population, plus weekly noise based on a Poisson distribution.
          baseline = pmax(1, rpois(n_weeks, lambda = population / 20000))
        )
      )
    ) %>%
    unnest(week_data) %>%
    ungroup() %>%
    mutate(cases = baseline) %>%
    select(county, population, week, cases)
  
  # Inject an outbreak: a real spike in the final 3 weeks for selected counties.
  if (length(outbreak_counties) > 0) {
    surveillance <- surveillance %>%
      mutate(
        cases = if_else(
          county %in% outbreak_counties & week > (n_weeks - 3),
          cases + rpois(n(), lambda = 15),
          cases
        )
      )
  }
  
  surveillance
}

# ---- 1. Simulate surveillance data -----------------------------------------

counties    <- c("Adams", "Baxter", "Clearwater", "Dunmore", "Elkridge", "Fairview")
populations <- c(85000,    42000,    230000,       15000,     60000,      110000)

surveillance_data <- simulate_surveillance_data(
  counties = counties,
  populations = populations,
  n_weeks = 12,
  outbreak_counties = c("Clearwater", "Dunmore"),
  seed = 2024
)

# Simulate a real-world reporting glitch: Elkridge submitted a negative
# correction for week 12. This is exactly the kind of bad record tryCatch
# needs to handle gracefully instead of crashing the whole pipeline.
surveillance_data <- surveillance_data %>%
  mutate(cases = if_else(county == "Elkridge" & week == 12, -3, cases))

dir.create(here::here("data", "raw"), showWarnings = FALSE, recursive = TRUE)
write_csv(surveillance_data, here::here("data", "raw", "surveillance_data.csv"))

# Note: If you are planning on sourceing scripts, it can be useful to include a message at the end of the script
#cat("Saved raw surveillance data to data/raw/surveillance_data.csv\n")
