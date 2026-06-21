# render_functions.R
#
# Rendering functions for a state ILI (influenza-like illness) surveillance reports
#
#   get_county_report_inputs()   - gathers all the values needed to render county pdf report
#   render_county_report()       - render a single county's PDF report

#' Gather and validate the inputs needed for one county's PDF report
#'
#' Deliberately kept separate from the actual rmarkdown::render() step so
#' this logic can be unit tested without needing a working LaTeX/pandoc
#' installation. Rendering is a side effect (writes a file); this function
#' is pure data wrangling, which is what we want to put under test.
#'
#' @param county_name character
#' @param priority_table tibble produced by recommend_resources()
#' @param surveillance_data long-format tibble of weekly cases, all counties
#' @return list(county_summary = one-row tibble, county_weekly = tibble)
get_county_report_inputs <- function(county_name, priority_table, surveillance_data) {
  county_summary <- priority_table %>% filter(county == county_name)
  county_weekly  <- surveillance_data %>% filter(county == county_name)
  
  if (nrow(county_summary) == 0) {
    stop("No summary row found for county: ", county_name)
  }
  if (nrow(county_weekly) == 0) {
    stop("No weekly surveillance data found for county: ", county_name)
  }
  
  list(county_summary = county_summary, county_weekly = county_weekly)
}

#' Render a single county's PDF report
#'
#' Pulls the county's data via get_county_report_inputs() (the testable
#' part), then renders the parameterized Rmd template into a PDF.
#' @param county_name character, county name
#' @param priority_table table returned by recommend_resources
#' @param surveillance_data long-format tibble of weekly cases, all counties
render_county_report <- function(county_name, priority_table, surveillance_data) {
  inputs <- get_county_report_inputs(county_name, priority_table, surveillance_data)
  
  rmarkdown::render(
    input = here::here("reports", "co_report_template.Rmd"),
    output_file = paste0("report_", county_name, ".pdf"),
    output_dir = here::here("reports", "output"),
    params = list(
      county_name    = county_name,
      county_summary = inputs$county_summary,
      county_weekly  = inputs$county_weekly
    ),
    envir = new.env(parent = globalenv()),
    quiet = TRUE
  )
  
  invisible(TRUE)
}

