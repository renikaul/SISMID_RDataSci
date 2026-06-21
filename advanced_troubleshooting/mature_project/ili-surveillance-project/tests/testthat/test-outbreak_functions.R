# test-outbreak_functions.R
#
# This file is discovered and run by testthat::test_dir() from run_tests.R,
# which uses here::here() to locate tests/testthat regardless of working
# directory. outbreak_functions.R is sourced by run_tests.R before this
# file runs, so all the functions below (detect_outbreak, etc.) are already
# in scope.

library(testthat)
library(tidyverse)

# detect_outbreak behavior under different scenarios ----
test_that("detect_outbreak flags a clear spike", {
  baseline <- rep(10, 8)            # 8 stable baseline weeks
  weekly_cases <- c(baseline, 40)   # then a spike to 40
  result <- detect_outbreak(weekly_cases, baseline_weeks = 8, threshold = 2)

  expect_true(result$outbreak_flag)
  expect_equal(result$latest_cases, 40)
  expect_true(result$z_score > 2)
})

test_that("detect_outbreak does not flag normal week-to-week variation", {
  weekly_cases <- c(10, 11, 9, 10, 12, 9, 11, 10, 10)
  result <- detect_outbreak(weekly_cases, baseline_weeks = 8, threshold = 2)

  expect_false(result$outbreak_flag)
})

test_that("detect_outbreak errors on negative case counts", {
  weekly_cases <- c(10, 10, 10, 10, 10, 10, 10, 10, -3)
  expect_error(
    detect_outbreak(weekly_cases, baseline_weeks = 8),
    "negative"
  )
})

test_that("detect_outbreak errors on non-numeric input", {
  weekly_cases <- c("10", "11", "nine", "10")
  expect_error(
    detect_outbreak(weekly_cases, baseline_weeks = 8),
    "numeric"
  )
})

test_that("detect_outbreak errors when there isn't enough history", {
  weekly_cases <- c(10, 12, 11)
  expect_error(
    detect_outbreak(weekly_cases, baseline_weeks = 8),
    "Not enough weeks"
  )
})

test_that("safe_detect_outbreak catches errors instead of crashing", {
  bad_cases <- c(10, 10, 10, 10, 10, 10, 10, 10, -5)

  expect_warning(
    result <- safe_detect_outbreak(bad_cases, county_name = "TestCounty"),
    "TestCounty"
  )

  expect_true(is.na(result$outbreak_flag))
  expect_false(is.na(result$error))
})

test_that("safe_detect_outbreak passes clean results through untouched", {
  good_cases <- c(10, 10, 10, 10, 11, 10, 10, 10, 10)
  result <- safe_detect_outbreak(good_cases, county_name = "TestCounty")

  expect_false(result$outbreak_flag)
  expect_true(is.na(result$error))
})

# recommend_resources behavior under different scenarios ----
test_that("recommend_resources assigns priority tiers correctly", {
  fake_results <- tibble(
    county = c("A", "B", "C", "D"),
    population = c(100000, 100000, 100000, 100000),
    latest_cases = c(5, 5, 5, 5),
    z_score = c(4, 2, 0.5, NA)
  )

  out <- recommend_resources(fake_results, high_z = 3, medium_z = 1.5)

  expect_equal(out$priority[out$county == "A"], "High - deploy resources now")
  expect_equal(out$priority[out$county == "B"], "Medium - increase monitoring")
  expect_equal(out$priority[out$county == "C"], "Low - routine surveillance")
  expect_equal(out$priority[out$county == "D"], "Data issue - needs follow-up")
})

test_that("recommend_resources errors when required columns are missing", {
  bad_input <- tibble(county = "A", z_score = 1)
  expect_error(recommend_resources(bad_input), "missing required columns")
})

# rendering behavior under different scenarios ----
test_that("get_county_report_inputs returns the right rows for a valid county", {
  pt <- tibble(
    county = c("Adams", "Baxter"),
    population = c(85000, 42000),
    latest_cases = c(12, 5),
    z_score = c(0.5, 1.2),
    case_rate_per_100k = c(14.1, 11.9),
    priority = c("Low - routine surveillance", "Low - routine surveillance")
  )
  sd <- tibble(
    county = c("Adams", "Adams", "Baxter"),
    population = c(85000, 85000, 42000),
    week = c(1, 2, 1),
    cases = c(10, 12, 5)
  )

  out <- get_county_report_inputs("Adams", pt, sd)

  expect_equal(nrow(out$county_summary), 1)
  expect_equal(out$county_summary$county, "Adams")
  expect_equal(nrow(out$county_weekly), 2)
})

test_that("get_county_report_inputs errors for a county missing from the summary table", {
  pt <- tibble(
    county = "Adams", population = 85000, latest_cases = 12,
    z_score = 0.5, case_rate_per_100k = 14.1, priority = "Low - routine surveillance"
  )
  sd <- tibble(county = "Adams", population = 85000, week = 1, cases = 10)

  expect_error(get_county_report_inputs("Nowhereville", pt, sd), "No summary row")
})

test_that("get_county_report_inputs errors for a county missing from weekly data", {
  pt <- tibble(
    county = "Adams", population = 85000, latest_cases = 12,
    z_score = 0.5, case_rate_per_100k = 14.1, priority = "Low - routine surveillance"
  )
  sd <- tibble(county = "Baxter", population = 42000, week = 1, cases = 5)

  expect_error(get_county_report_inputs("Adams", pt, sd), "No weekly surveillance data")
})
