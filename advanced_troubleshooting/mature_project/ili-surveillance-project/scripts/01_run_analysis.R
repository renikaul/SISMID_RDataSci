# scripts/01_run_analysis.R
#
# Main workflow:
#   1. Load data simulated by 00_simulate_data.R and saved to data/raw/
#   2. Map detect_outbreak() over every county with purrr
#   3. Summarize current week's status into one row per county, save to data/processed/
#   4. Turn that into a recommendation for county actions, save to data/processed/
#   5. Visualize it for a state-wide decision-maker, save to reports/output/
#
# Uses here::here() throughout so it runs correctly no matter what your
# working directory is when you call it -- no setwd() needed. here::here()
# finds the project root by locating ili-surveillance-project.Rproj.

#load mutiple libraries in single call using pacman library p_load function
pacman::p_load(
  tidyverse,
  here)

source(here::here("R", "outbreak_functions.R"))

# ---- 1. Load data submitted by each county -----------------

#purr function 

# save long-format tibble of weekly cases, all counties in data/raw/surveillance_data.csv

# ---- 2. Map detect_outbreak() over every county with purrr -----------------

# group_split() breaks the long-format tibble into a list of one tibble per county.
# map_dfr() applies a function to each piece and stitches the results back
# into a single tibble -- the functional-programming alternative to a
# manually written for-loop with an empty results data frame to grow.

# convert long-format tibble into list of tibbles
county_data <- surveillance_data %>%
  group_by(county) %>%
  arrange(week, .by_group = TRUE) %>%
  group_split()

#mapping allows us to apply safe_detect_outbreak to each tibble in the county_data list
outbreak_results <- county_data %>%
  # each tibble is passed to this function as df
  map(function(df) {
    # pull out the county name from the df tibble
    county_name <- unique(df$county)
    # apply the function of interest
    result <- safe_detect_outbreak(df$cases, county_name = county_name)
    # create a small, 1-row data frame summarizing this specific county's results.
    # because map() is looping, we will end up with a list of these small data frames.
    tibble(
      county        = county_name,
      population    = unique(df$population),
      latest_cases  = result$latest_cases,
      baseline_mean = result$baseline_mean,
      z_score       = result$z_score,
      outbreak_flag = result$outbreak_flag,
      error         = result$error
    )
  }) %>% # <-- at this point we have a list of individual tables
  list_rbind() # that are stacked row-by-row to create a results table

cat("\n--- Outbreak detection results ---\n")
print(outbreak_results)

# ---- 3. Resource allocation recommendation ---------------------------------

#Calculate case rate and assign priority based on z-score calculated by safe_detect_outbreak()
priority_table <- recommend_resources(outbreak_results)

cat("\n--- Resource allocation priority ---\n")
print(priority_table)

dir.create(here::here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
write_csv(outbreak_results, here::here("data", "processed", "outbreak_results.csv"))
write_csv(priority_table, here::here("data", "processed", "priority_table.csv"))
cat("\nSaved processed results to data/processed/\n")

dir.create(here::here("reports", "output"), showWarnings = FALSE, recursive = TRUE)
cat("\nReady to create pdf reports. Run 02_generate_reports.R\n")
