# scripts/02_generate_reports.R
#
# Renders
#     - one PDF report per county from reports/co_report_template.Rmd.
#     - one PDF report for the whole state from reports/state_report_template.Rmd.
#
# Reads from data/processed/ and data/raw/ rather than relying on objects
# already in your R session -- that way report generation can be run on its
# own (e.g. on a schedule, or by someone who didn't run the analysis script
# themselves) as long as scripts/01_run_analysis.R has been run at least
# once to produce those files.
#
# Requires a working pandoc + LaTeX installation (pdf_document needs LaTeX
# specifically) -- if you've never rendered an Rmd to PDF before, run:
#
#   install.packages("tinytex")
#   tinytex::install_tinytex()
#
# Usage: Rscript scripts/02_generate_reports.R

pacman::p_load(tidyverse,
               here,
               rmarkdown)

source(here::here("R", "render_functions.R"))

priority_path     <- here::here("data", "processed", "priority_table.csv")
surveillance_path <- here::here("data", "raw", "surveillance_data.csv")

if (!file.exists(priority_path) || !file.exists(surveillance_path)) {
  stop(
    "Required input files not found. Run scripts/01_run_analysis.R first ",
    "to generate data/processed/priority_table.csv and data/raw/surveillance_data.csv."
  )
}

# load data
priority_table     <- read_csv(priority_path, show_col_types = FALSE)
surveillance_data  <- read_csv(surveillance_path, show_col_types = FALSE)

dir.create(here::here("reports", "output"), showWarnings = FALSE, recursive = TRUE)
# Render State Report ----

rmarkdown::render(
  input = here::here("reports", "state_report_template.Rmd"),
  output_file = paste0("state_report_",Sys.Date(), ".pdf"),
  output_dir = here::here("reports", "output"),
  params = list(
    surveillance_data = surveillance_data,
    priority_table  = priority_table
    ),
  envir = new.env(parent = globalenv()),
  quiet = TRUE
)


# Render County Reports ----
# tryCatch wrapper: rendering can fail for reasons that have nothing to do
# with your data (no LaTeX installed, pandoc not found, a typo in the
# .Rmd), and one county's failure shouldn't stop the rest of the batch.
safe_render_county_report <- function(county_name, priority_table, surveillance_data) {
  tryCatch(
    {
      render_county_report(county_name, priority_table, surveillance_data)
      tibble(county = county_name, status = "success", error = NA_character_)
    },
    error = function(e) {
      warning(sprintf("Failed to render report for %s: %s", county_name, conditionMessage(e)), call. = FALSE)
      tibble(county = county_name, status = "failed", error = conditionMessage(e))
    }
  )
}

# Map the rendering function over every county in the priority table.
render_results <- priority_table$county %>%
  map(safe_render_county_report,
          priority_table = priority_table,
          surveillance_data = surveillance_data) %>%
  list_rbind()

cat("\n--- Report generation results ---\n")
print(render_results)
cat("\nPDFs (if successful) are in reports/output/\n")
