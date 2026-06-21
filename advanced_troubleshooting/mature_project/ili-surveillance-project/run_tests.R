# run_tests.R
#
# Run the full test suite from anywhere -- here::here() finds the project
# root via ili-surveillance-project.Rproj, so this works whether you're in
# an R console, RStudio, or calling `Rscript run_tests.R` from the terminal.
#
# Usage: Rscript run_tests.R

library(testthat)
library(here)

source(here::here("R", "outbreak_functions.R"))
source(here::here("R", "render_functions.R"))

test_dir(here::here("tests", "testthat"))
