# outbreak_functions.R
#
# Core analytical functions for a state ILI (influenza-like illness) surveillance project.
#
#   detect_outbreak()            - flags whether a county's latest week is anomalous
#   safe_detect_outbreak()       - tryCatch wrapper so one bad county can't crash the run
#   recommend_resources()        - turns results into a resource-allocation priority table


library(tidyverse)


#' Detect whether the most recent week's case count is anomalous for a county
#'
#' Compares the latest week to a baseline built from earlier weeks using a
#' simple z-score. This function validates its own input and throws errors
#' on purpose for bad data -- it is meant to be called through
#' safe_detect_outbreak(), which catches those errors.
#'
#' @param weekly_cases numeric vector of weekly case counts, in chronological order
#' @param baseline_weeks number of earlier weeks used to build the baseline
#' @param threshold z-score at or above which we flag an outbreak
#' @return a list: latest_cases, baseline_mean, baseline_sd, z_score, outbreak_flag
detect_outbreak <- function(weekly_cases, baseline_weeks = 8, threshold = 2) {

  # --- Validation: fail loudly and specifically, don't fail silently ---
  if (!is.numeric(weekly_cases)) {
    stop("weekly_cases must be numeric, got class: ", class(weekly_cases)[1])
  }
  if (any(weekly_cases < 0, na.rm = TRUE)) {
    stop("weekly_cases contains negative values, which is impossible for case counts")
  }
  if (length(weekly_cases) < baseline_weeks + 1) {
    stop(
      "Not enough weeks of data: need at least ", baseline_weeks + 1,
      " weeks, got ", length(weekly_cases)
    )
  }
  if (all(is.na(weekly_cases))) {
    stop("weekly_cases is entirely missing (all NA)")
  }

  n <- length(weekly_cases)
  baseline <- weekly_cases[(n - baseline_weeks):(n - 1)]
  latest   <- weekly_cases[n]

  baseline_mean <- mean(baseline, na.rm = TRUE)
  baseline_sd   <- sd(baseline, na.rm = TRUE)

  if (baseline_sd == 0 || is.na(baseline_sd)) {
    # No variability historically (e.g. always near zero cases).
    # Any positive count is automatically notable.
    z_score <- if (latest > baseline_mean) Inf else 0
  } else {
    z_score <- (latest - baseline_mean) / baseline_sd
  }

  list(
    latest_cases  = latest,
    baseline_mean = round(baseline_mean, 2),
    baseline_sd   = round(baseline_sd, 2),
    z_score       = round(z_score, 2),
    outbreak_flag = z_score >= threshold
  )
}

#' tryCatch wrapper around detect_outbreak()
#'
#' This is the function you actually call inside a purrr loop over many
#' counties. detect_outbreak() throws errors on bad data on purpose, so bugs
#' aren't hidden during development -- safe_detect_outbreak() catches those
#' errors at run time and converts them into an NA/flagged row, so one
#' county's bad data doesn't stop the analysis for the other 100+ counties.
#'
#' @param weekly_cases numeric vector of weekly case counts
#' @param county_name character, used only to make the warning message useful
#' @inheritParams detect_outbreak
#' @return same fields as detect_outbreak(), plus `error` (NA if no error)
safe_detect_outbreak <- function(weekly_cases, county_name = "unknown",
                                  baseline_weeks = 8, threshold = 2) {
  tryCatch(
    {
      result <- detect_outbreak(weekly_cases, baseline_weeks = baseline_weeks, threshold = threshold)
      result$error <- NA_character_
      result
    },
    error = function(e) {
      warning(sprintf("Could not analyze %s: %s", county_name, conditionMessage(e)), call. = FALSE)
      list(
        latest_cases  = NA_real_,
        baseline_mean = NA_real_,
        baseline_sd   = NA_real_,
        z_score       = NA_real_,
        outbreak_flag = NA,
        error         = conditionMessage(e)
      )
    }
  )
}

#' Translate outbreak detection results into a resource allocation priority
#'
#' @param results_df tibble with columns: county, population, latest_cases, z_score
#' @param high_z z-score cutoff for "High" priority
#' @param medium_z z-score cutoff for "Medium" priority
#' @return results_df with case_rate_per_100k and priority columns added
recommend_resources <- function(results_df, high_z = 3, medium_z = 1.5) {

  required_cols <- c("county", "population", "latest_cases", "z_score")
  if (!all(required_cols %in% names(results_df))) {
    stop("results_df is missing required columns: county, population, latest_cases, z_score")
  }

  results_df %>%
    mutate(
      case_rate_per_100k = round((latest_cases / population) * 100000, 1),
      priority = case_when(
        is.na(z_score)     ~ "Data issue - needs follow-up",
        z_score >= high_z   ~ "High - deploy resources now",
        z_score >= medium_z ~ "Medium - increase monitoring",
        TRUE                 ~ "Low - routine surveillance"
      )
    ) %>%
    arrange(desc(z_score))
}

