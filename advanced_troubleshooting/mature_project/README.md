# State ILI Surveillance Project

A small, realistic R project for learning `tryCatch`, `testthat`, `purrr`,
parameterized R Markdown, and `here`-based project structure, in the context
of public health surveillance: a state epidemiologist monitoring
influenza-like illness (ILI) case counts across counties.

## Project structure

```
ili-surveillance-project/
├── ili-surveillance-project.Rproj   <- open this in RStudio; anchors here::here()
├── run_tests.R                       <- run the full test suite
├── R/
│   └── outbreak_functions.R          <- all custom functions live here
│   └── rendering_functions.R
├── scripts/
│   ├── 00_simulate_data.R             <- main pipeline: simulate -> analysis -> report
│   ├── 01_run_analysis.R 
│   └── 02_generate_reports.R         <- renders one PDF per county
├── reports/
│   ├── co_report_template.Rmd        <- parameterized report template
│   ├── state_report_template.Rmd        
│   └── output/                       <- rendered PDFs and the priority chart land here
├── data/
│   ├── raw/                          <- simulated "as received" surveillance data
│   └── processed/                    <- outbreak_results.csv, priority_table.csv
└── tests/
    └── testthat/
        └── test-outbreak_functions.R
```

This mirrors a layout you'll see in real analysis projects: code is
separated from data, raw data is separated from processed/derived data, and
reports are a build output, not something you hand-edit. `R/` holds function
*definitions* (the package-style convention: code that's `source()`'d but
never run directly); `scripts/` holds things you actually execute, numbered
in the order you'd run them.

## Why `here::here()` instead of `setwd()`

Every script in this project uses `here::here()` to build file paths, e.g.
`here::here("data", "raw", "surveillance_data.csv")`. `here` figures out
where the project root is by finding `ili-surveillance-project.Rproj` (or a
`.git` folder, or a few other markers) and builds paths relative to that —
regardless of what your current working directory happens to be.

The practical effect: you can run `scripts/01_run_analysis.R` from the R
console, from a `Rscript` call in a terminal, from inside RStudio with the
project open, or from a CI pipeline, and the paths still resolve correctly.
`setwd("some/specific/folder")` breaks the moment you, a teammate, or a
scheduled job runs the script from a different location — it's one of the
most common sources of "works on my machine" bugs in R.

## How to run it

Open `ili-surveillance-project.Rproj` in RStudio (this sets the working
directory and lets `here` find the root immediately), or just `cd` into the
folder from a terminal — `here` will still find the `.Rproj` file.

```r
install.packages(c("tidyverse", "testthat", "here", "rmarkdown", "knitr"))
# pdf_document requires a LaTeX install -- if you've never rendered to PDF before:
install.packages("tinytex")
tinytex::install_tinytex()
```

```r
source("scripts/01_run_analysis.R")     # simulate data, detect outbreaks, save csv + chart
```
```
Rscript run_tests.R                     # run the test suite
Rscript scripts/02_generate_reports.R   # render one PDF per county into reports/output/
```

## Concepts highlighted in this module

**1. Realistic simulated data** — `simulate_surveillance_data()` creates
weekly case counts per county scaled to population with Poisson noise, an
injected outbreak in two counties, and a simulated reporting error (a
negative case count) — the kind of thing that actually shows up in
surveillance data.

**2. Writing a function** — `detect_outbreak()`, `safe_detect_outbreak()`,
`recommend_resources()`, and `get_county_report_inputs()`, each with one
clear responsibility. It's tempting to write one massive function, but single task functions are easier to troubleshoot.

**3. Failing loudly with `tryCatch`** — `detect_outbreak()` validates its input and `stop()`s loudly on bad data. `safe_detect_outbreak()` wraps it in `tryCatch()` so one county's bad data doesn't halt the whole run.
`safe_render_county_report()` applies the same pattern to PDF rendering,
which can fail for unrelated reasons (missing LaTeX, a typo in the `.Rmd`).

**4. Recreate errors with `testthat`**  `tests/testthat/test-outbreak_functions.R` covers the happy path and every
error path for all four functions.

**5. Efficient alternative to loops: Mapping. `purrr`** — `scripts/01_run_analysis.R` uses `group_split()` +
`purrr::map()` to apply `safe_detect_outbreak()` across every county.
`scripts/02_generate_reports.R` does the same with
`safe_render_county_report()` to render every county's PDF.

**6. Writing reports based on a template** — This project produces two types of reports. 


`reports/co_report_template.Rmd` is *parameterized* — it reads from a `params`
list (`county_name`, `county_summary`, `county_weekly`) supplied at render
time, rather than hardcoding one county's data.

`scripts/02_generate_reports.R` keeps data-gathering and rendering
deliberately separate:

- `get_county_report_inputs()` (in `R/outbreak_functions.R`) pulls and
  validates one county's rows. It's pure data wrangling with no side
  effects, so it's fully covered by `testthat` without needing pandoc or
  LaTeX installed.
- `render_county_report()` calls that helper, then calls
  `rmarkdown::render()` — the actual side effect of writing a PDF.
- `safe_render_county_report()` wraps the render call in `tryCatch()`.
- `purrr::map()` applies the safe version across every county.

It also reads its inputs from `data/processed/priority_table.csv` and
`data/raw/surveillance_data.csv` rather than relying on objects still being
in your R session — so report generation can be re-run on its own (on a
schedule, or by a colleague) any time after the analysis script has been run
at least once.

## Things worth experimenting with once it's running

- Change `outbreak_counties` or `seed` in `scripts/01_run_analysis.R` and
  watch the priority table and the PDFs change.
- Break something on purpose — feed `detect_outbreak()` a vector with `NA`s
  mixed in, or change `threshold` — and see how the output responds.
- Add a new `test_that()` block for a case you're curious about.
- Try adding a `data/processed/outbreak_results.csv` -> `scripts/` script
  that reads it back in without touching `scripts/01_run_analysis.R` at
  all, to get a feel for why separating raw/processed data is useful.

