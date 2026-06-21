# Parallel Programming in R: Infectious Disease Modeling
### Computer Lab — Student Handout | 90 Minutes

**Learning Objectives:** By the end of this lab you will be able to:
- Explain why and when parallelization speeds up computation
- Use `doParallel` and `foreach` to parallelize R code
- Apply parallel computing to stochastic epidemic simulations and parameter sweeps
- Diagnose and fix common parallelization pitfalls

**Group size:** 1–3 students | **Recommended:** one person drives, others navigate and discuss

---

## Setup (Before You Begin)

Run this block first. Raise your hand if you get any errors.

```r
# Install packages if needed (do this BEFORE lab if possible)
# install.packages(c("doParallel", "foreach", "tidyverse", "tictoc"))

library(doParallel)   # parallel backend (loads parallel and foreach)
library(foreach)      # provides the %dopar% operator
library(tidyverse)
library(tictoc)

# How many cores does your machine have?
parallel::detectCores()
```

> **Tip:** You'll see your core count printed. Keep this number in mind — you'll use it throughout the lab.
>
> **Package note:** `doParallel` wraps R's built-in `parallel` package and registers it as a backend for `foreach`. You only need these two packages to parallelize loops in R.

---

## Part 1 — Why Parallelize? (15 min)

### 1.1 The Baseline: A Stochastic SIR Model

The SIR (Susceptible–Infectious–Recovered) model is a workhorse of infectious disease epidemiology. Below is a stochastic, discrete-time version using binomial draws to simulate transmission and recovery.

Read through the function, then answer the discussion questions before running it.

```r
# Stochastic discrete-time SIR model
# Returns a data frame of S, I, R counts over time

run_sir <- function(
  N       = 10000,   # population size
  I0      = 10,      # initial infectious individuals
  beta    = 0.3,     # transmission rate (per contact per day)
  gamma   = 0.1,     # recovery rate (per day)
  n_days  = 150      # simulation duration
) {
  S <- numeric(n_days); I <- numeric(n_days); R <- numeric(n_days)
  S[1] <- N - I0; I[1] <- I0; R[1] <- 0

  for (t in 2:n_days) {
    # TODO: fill in the stochastic transitions
    # Hint: new infections ~ Binomial(S[t-1], 1 - exp(-beta * I[t-1] / N))
    #       new recoveries  ~ Binomial(I[t-1], 1 - exp(-gamma))

    new_infections <- ____________(S[t-1], 1, prob = 1 - exp(-beta * I[t-1] / N))
    new_recoveries <- ____________(I[t-1], 1, prob = 1 - exp(-gamma))

    S[t] <- S[t-1] - new_infections
    I[t] <- I[t-1] + new_infections - new_recoveries
    R[t] <- R[t-1] + new_recoveries
  }

  data.frame(day = 1:n_days, S = S, I = I, R = R)
}

# Run a single simulation and plot it
set.seed(42)
sim1 <- run_sir()

ggplot(sim1, aes(x = day)) +
  geom_line(aes(y = S, color = "Susceptible")) +
  geom_line(aes(y = I, color = "Infectious")) +
  geom_line(aes(y = R, color = "Recovered")) +
  scale_color_manual(values = c("Susceptible" = "steelblue",
                                "Infectious"  = "firebrick",
                                "Recovered"   = "darkgreen")) +
  labs(title = "Single Stochastic SIR Simulation",
       x = "Day", y = "Count", color = NULL) +
  theme_minimal()
```

> **Discussion (2 min):** The model is stochastic — run it twice without `set.seed()`. Do you get the same epidemic curve? Why or why not? What does this imply about how many simulations we need?

---

### 1.2 Timing a Serial Loop

Because the model is stochastic, public health analysts often run hundreds or thousands of simulations to characterize uncertainty. Let's see how long that takes serially.

```r
n_sims <- 500

tic("Serial loop")
serial_results <- lapply(1:n_sims, function(i) {
  # TODO: call run_sir() with default parameters
  # and add a column "sim_id" = i to the result


})
toc()

# Combine results
serial_df <- bind_rows(serial_results)

# Plot the ensemble
ggplot(serial_df, aes(x = day, y = I, group = sim_id)) +
  geom_line(alpha = 0.05, color = "firebrick") +
  stat_summary(aes(group = 1), fun = median, geom = "line",
               color = "darkred", linewidth = 1.2) +
  labs(title = "500 Stochastic SIR Simulations (Serial)",
       subtitle = "Thin lines = individual runs; thick line = median",
       x = "Day", y = "Infectious") +
  theme_minimal()
```

**Record your serial time:** _______ seconds

---

## Part 2 — Setting Up `doParallel` (15 min)

### 2.1 How `doParallel` Works

`doParallel` connects two things:

- **`parallel`** (base R) — creates and manages a cluster of worker processes
- **`foreach`** — provides a loop syntax (`%do%` serial, `%dopar%` parallel) that sends iterations to whichever backend is registered

The workflow is always: **make cluster → register → loop with `%dopar%` → stop cluster.**

```r
# Step 1: Detect cores — leave one free for the OS
n_cores <- parallel::detectCores() - 1
cat("Using", n_cores, "cores\n")

# Step 2: Make a PSOCK cluster (works on Windows, macOS, Linux)
cl <- makeCluster(n_cores)

# Step 3: Register it as the doParallel backend
registerDoParallel(cl)

# Confirm registration
cat("Registered workers:", getDoParWorkers(), "\n")
cat("Backend name:      ", getDoParName(), "\n")
```

> **What is a PSOCK cluster?** Each worker is a fresh R session launched as a separate process. Workers don't share your global environment — you must send them anything they need.

---

### 2.2 Your First `foreach` Loop

`foreach` looks like a for-loop but *collects* results like `lapply`. The `%dopar%` operator sends each iteration to a worker.

```r
# Serial version with %do% (no parallelism — good for testing)
results_serial <- foreach(i = 1:5, .combine = c) %do% {
  i^2
}
cat("Serial:  ", results_serial, "\n")

# Parallel version — swap %do% for %dopar%
results_par <- foreach(i = 1:5, .combine = c) %dopar% {
  i^2
}
cat("Parallel:", results_par, "\n")
```

**Key `foreach` arguments:**

| Argument | Purpose | Common values |
|----------|---------|---------------|
| `.combine` | How to merge results | `c`, `rbind`, `cbind`, `"list"` |
| `.packages` | Packages to load on workers | `c("dplyr", "tidyr")` |
| `.export` | Variables to send to workers | `c("run_sir", "n_days")` |
| `.errorhandling` | What to do on worker error | `"stop"`, `"remove"`, `"pass"` |

---

### 2.3 Parallel SIR Simulations with `foreach`

```r
# Export run_sir to all workers
# (alternatively, use .export inside the foreach call)
clusterExport(cl, varlist = c("run_sir"))

tic("Parallel foreach")
parallel_results <- foreach(
  i          = 1:n_sims,
  .combine   = bind_rows,      # combine data frames by row
  .packages  = c("dplyr")
) %dopar% {
  # TODO: run one simulation and return it with a sim_id column
  # (each worker runs this block independently)


}
toc()
```

**Record your parallel time:** _______ seconds

**Speedup ratio:** serial time / parallel time = _______

> **Discussion (2 min):** Is the speedup equal to the number of cores? Why might it be more or less?

---

### 2.4 Combining Results — `.combine` Options

The `.combine` argument is what makes `foreach` flexible. Try each and compare:

```r
# .combine = "list"  → returns a plain list (like lapply)
out_list <- foreach(i = 1:4, .combine = "list") %dopar% {
  run_sir(n_days = 30)
}
length(out_list)       # 4 data frames in a list

# .combine = rbind  → stacks data frames (like bind_rows, but slower)
out_rbind <- foreach(
  i        = 1:4,
  .combine = rbind,
  .packages = "dplyr"
) %dopar% {
  sim <- run_sir(n_days = 30)
  sim$sim_id <- i
  sim
}
nrow(out_rbind)        # 4 * 30 = 120 rows

# .combine = c  → concatenates atomic vectors
out_vec <- foreach(i = 1:4, .combine = c) %dopar% {
  max(run_sir()$I)     # returns a single number per iteration
}
out_vec                # numeric vector of length 4
```

> **Best practice:** For data frames, prefer `.combine = bind_rows` with `.packages = c("dplyr")` over `.combine = rbind` — it is faster and handles column types correctly.

---

### 2.5 RNG Seeds in Parallel

Random number generation needs care across workers — naive seeding causes workers to produce identical or correlated streams.

```r
# BAD: setting set.seed() inside %dopar% — workers may get the same seed
bad_results <- foreach(i = 1:6, .combine = c) %dopar% {
  set.seed(99)           # WRONG: every worker resets to the same seed
  run_sir()$I[50]
}
cat("Bad (expect repeated values):", bad_results, "\n")

# GOOD: use L'Ecuyer-CMRG streams via clusterSetRNGStream
RNGkind("L'Ecuyer-CMRG")
clusterSetRNGStream(cl, iseed = 2024)

good_results <- foreach(i = 1:6, .combine = c) %dopar% {
  run_sir()$I[50]        # each worker has its own independent RNG stream
}
cat("Good (all should differ):", good_results, "\n")

# Verify reproducibility — reset seed and re-run
clusterSetRNGStream(cl, iseed = 2024)
repro_results <- foreach(i = 1:6, .combine = c) %dopar% {
  run_sir()$I[50]
}
cat("Identical to good_results?", identical(good_results, repro_results), "\n")
```

---

### 2.6 Always Stop Your Cluster

```r
# Stop the cluster when done — frees memory and CPU resources
stopCluster(cl)
registerDoSEQ()   # revert to serial foreach (good hygiene)
```

> **Rule of thumb:** Always pair `makeCluster()` with `stopCluster()`. For safety, wrap long parallel jobs in `tryCatch()` so the cluster stops even if an error occurs:
>
> ```r
> cl <- makeCluster(n_cores)
> registerDoParallel(cl)
> tryCatch({
>   # ... your parallel code ...
> }, finally = {
>   stopCluster(cl)
>   registerDoSEQ()
> })
> ```

---

## Part 3 — `foreach` Patterns for Epidemic Modeling (15 min)

### 3.1 Iterating Over Multiple Variables with `%:%`

`foreach` supports nested loops via the `%:%` operator. This is useful when sweeping over two parameters simultaneously.

```r
cl <- makeCluster(n_cores)
registerDoParallel(cl)
clusterExport(cl, "run_sir")
clusterSetRNGStream(cl, iseed = 42)

# Nested loop: 3 beta values × 3 gamma values = 9 combinations
beta_vals  <- c(0.2, 0.3, 0.5)
gamma_vals <- c(0.05, 0.10, 0.20)

nested_results <- foreach(
  b        = beta_vals,
  .combine = bind_rows,
  .packages = "dplyr"
) %:%
  foreach(
    g        = gamma_vals,
    .combine = bind_rows
  ) %dopar% {
    sim <- run_sir(beta = b, gamma = g)
    data.frame(
      beta        = b,
      gamma       = g,
      R0          = round(b / g, 2),
      peak_I      = max(sim$I),
      attack_rate = tail(sim$R, 1) / 10000
    )
  }

nested_results
```

> **Note:** `%:%` flattens the nested iterations and distributes them across workers — all 9 combinations run in parallel, not sequentially.

---

### 3.2 Accumulating Results with a Custom `.combine` Function

Sometimes you want more control over how results are merged. You can pass any two-argument function to `.combine`.

```r
# Custom combiner: keeps a running list AND prints progress
my_combine <- function(a, b) {
  cat(".")      # progress dot to console
  c(a, list(b))
}

cat("Running 20 simulations: ")
custom_results <- foreach(
  i        = 1:20,
  .combine = my_combine
) %dopar% {
  list(sim_id  = i,
       peak_I  = max(run_sir()$I),
       extinct = max(run_sir()$I) < 50)
}
cat("\nDone\n")

# Extract peak counts
peaks <- sapply(custom_results, `[[`, "peak_I")
summary(peaks)
```

---

### 3.3 Error Handling with `.errorhandling`

In long parameter sweeps, one bad combination shouldn't crash the whole job.

```r
# Introduce a deliberately bad parameter set
beta_test <- c(0.1, 0.3, -99, 0.5)   # -99 will cause rbinom to fail

safe_results <- foreach(
  b              = beta_test,
  .combine       = bind_rows,
  .errorhandling = "pass",     # on error, return the error object instead of stopping
  .packages      = "dplyr"
) %dopar% {
  tryCatch({
    sim <- run_sir(beta = b)
    data.frame(beta = b, peak_I = max(sim$I), error = NA_character_)
  }, error = function(e) {
    data.frame(beta = b, peak_I = NA_real_, error = conditionMessage(e))
  })
}

safe_results
```

> **Discussion:** Why is error handling especially important in parallel code compared to serial code?

---

## Part 4 — Parameter Sweeps for Transmission Dynamics (20 min)

This is where parallelization pays off most in infectious disease work: systematically exploring how outputs change across a grid of parameter values.

### 4.1 Define the Parameter Grid

```r
# Sweep over transmission rate (beta) and recovery rate (gamma)
# R0 = beta / gamma; this grid spans R0 ≈ 0.5 to 6
param_grid <- expand.grid(
  beta  = seq(0.1, 0.6, by = 0.05),
  gamma = seq(0.05, 0.20, by = 0.05)
) %>%
  mutate(
    R0       = round(beta / gamma, 2),
    combo_id = row_number()
  )

cat("Parameter combinations:", nrow(param_grid), "\n")
cat("Simulations per combo: 50\n")
cat("Total simulations:", nrow(param_grid) * 50, "\n")
```

---

### 4.2 Run the Sweep with `foreach`

```r
cl <- makeCluster(n_cores)
registerDoParallel(cl)
clusterExport(cl, "run_sir")
clusterSetRNGStream(cl, iseed = 2024)

tic("Parameter sweep — foreach %dopar%")
sweep_results <- foreach(
  row_i    = 1:nrow(param_grid),
  .combine = bind_rows,
  .packages = "dplyr"
) %dopar% {

  # Extract this row's parameters
  b  <- param_grid$beta[row_i]
  g  <- param_grid$gamma[row_i]
  r0 <- param_grid$R0[row_i]
  id <- param_grid$combo_id[row_i]

  # TODO: run 50 simulations for this parameter combo
  # Return a data frame with columns:
  #   combo_id, beta, gamma, R0, sim, peak_I, attack_rate, epidemic
  #
  # attack_rate = final R / N   (proportion ever infected)
  # epidemic    = TRUE if peak_I > 100

  reps <- lapply(1:50, function(sim) {
    result <- run_sir(beta = b, gamma = g)
    N      <- ____________
    data.frame(
      combo_id    = id,
      beta        = b,
      gamma       = g,
      R0          = r0,
      sim         = sim,
      peak_I      = ____________,
      attack_rate = ____________,
      epidemic    = ____________
    )
  })
  bind_rows(reps)
}
toc()

stopCluster(cl)
registerDoSEQ()

cat("Rows in sweep results:", nrow(sweep_results), "\n")
```

> **Why `lapply` inside `%dopar%`?** The outer `foreach` parallelizes over parameter combinations. Within each worker, the 50 replicate simulations run serially — this is the right level of granularity. Trying to parallelize both levels at once (nested `%dopar%`) would create far more overhead than benefit.

---

### 4.3 Summarize and Visualize

```r
# Summarize across simulation replicates
sweep_summary <- sweep_results %>%
  group_by(combo_id, beta, gamma, R0) %>%
  summarize(
    mean_peak_I      = mean(peak_I),
    median_peak_I    = median(peak_I),
    prob_epidemic    = mean(epidemic),
    mean_attack_rate = mean(attack_rate),
    .groups = "drop"
  )

# Heatmap: probability of epidemic by beta and gamma
ggplot(sweep_summary, aes(x = beta, y = gamma, fill = prob_epidemic)) +
  geom_tile() +
  geom_contour(aes(z = prob_epidemic), breaks = 0.5,
               color = "white", linewidth = 1) +
  scale_fill_viridis_c(option = "inferno", name = "P(epidemic)") +
  labs(
    title    = "Probability of Epidemic by Transmission Parameters",
    subtitle = "White contour = 50% probability threshold",
    x        = expression(beta ~ "(transmission rate)"),
    y        = expression(gamma ~ "(recovery rate)")
  ) +
  theme_minimal()
```

```r
# TODO: Make a second heatmap showing mean_attack_rate
# Use a different viridis palette (e.g., "plasma" or "magma")


```

```r
# R0 threshold plot — epidemic probability vs. R0
ggplot(sweep_summary, aes(x = R0, y = prob_epidemic)) +
  geom_point(aes(color = gamma), size = 2, alpha = 0.7) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +
  geom_vline(xintercept = 1, linetype = "dashed", color = "firebrick") +
  annotate("text", x = 1.05, y = 0.1, label = "R₀ = 1",
           hjust = 0, color = "firebrick") +
  scale_color_viridis_c(name = expression(gamma)) +
  labs(
    title = "Epidemic Probability vs. Basic Reproduction Number",
    x     = expression(R[0] ~ "= β / γ"),
    y     = "P(epidemic)"
  ) +
  theme_minimal()
```

> **Discussion (3 min):** At what R₀ does epidemic probability cross 50%? Is it exactly 1.0? Why might it differ from the theoretical threshold?

---

## Part 5 — Vaccination Scenarios (Optional / Stretch, 10 min)

### 5.1 SIRV Model with Vaccination

```r
# Extend SIR with a Vaccinated (V) compartment
# Vaccination occurs at t=0: fraction `vax_coverage` of S moves to V
# Vaccinated individuals are fully protected (vaccine efficacy = 1)

run_sirv <- function(
  N            = 10000,
  I0           = 10,
  beta         = 0.3,
  gamma        = 0.1,
  vax_coverage = 0.0,
  n_days       = 150
) {
  S <- numeric(n_days); I <- numeric(n_days)
  R <- numeric(n_days); V <- numeric(n_days)

  # TODO: Initialize compartments
  # V[1] = floor(vax_coverage * N)
  # S[1] = N - I0 - V[1]
  # I[1] = I0
  # R[1] = 0



  for (t in 2:n_days) {
    # TODO: fill in transitions (same as SIR; V stays constant — no waning)


  }

  data.frame(day = 1:n_days, S = S, I = I, R = R, V = V,
             vax_coverage = vax_coverage)
}
```

### 5.2 Parallel Vaccination Sweep

```r
vax_levels <- seq(0, 0.90, by = 0.10)
n_reps     <- 100

cl <- makeCluster(n_cores)
registerDoParallel(cl)
clusterExport(cl, c("run_sirv"))
clusterSetRNGStream(cl, iseed = 2024)

vax_sweep <- foreach(
  vax      = vax_levels,
  .combine = bind_rows,
  .packages = "dplyr"
) %dopar% {
  # TODO: run n_reps simulations at this vax_coverage level
  # Return data frame with: vax_coverage, sim, peak_I, attack_rate


}

stopCluster(cl)
registerDoSEQ()

# Summarize
vax_summary <- vax_sweep %>%
  group_by(vax_coverage) %>%
  summarize(mean_peak_I  = mean(peak_I),
            mean_attack  = mean(attack_rate),
            .groups = "drop")

# TODO: Plot mean_attack_rate vs. vax_coverage
# Add a horizontal reference line at attack_rate = 0.01 (near-elimination)
# Annotate the herd immunity threshold (1 - 1/R0, where R0 = 0.3/0.1 = 3)


```

---

## Part 6 — Pitfalls and Best Practices (10 min)

Work through each example: identify the bug, fix it, explain why it was a problem.

### Pitfall 1: Missing `.export` or `clusterExport`

```r
multiplier <- 2.5   # in your global environment

cl2 <- makeCluster(2)
registerDoParallel(cl2)

# This will FAIL with "object 'multiplier' not found"
result_broken <- foreach(x = 1:4, .combine = c) %dopar% {
  x * multiplier
}

# TODO: Fix it two ways —
# Option A: add .export to the foreach call
# Option B: use clusterExport before the loop


stopCluster(cl2)
registerDoSEQ()
```

---

### Pitfall 2: Overhead Dominates on Small Tasks

```r
cl3 <- makeCluster(n_cores)
registerDoParallel(cl3)

# Task A: trivially fast — overhead kills any benefit
tic("Parallel — trivial task")
r1 <- foreach(x = 1:1000, .combine = c) %dopar% { sqrt(x) }
toc()

tic("Serial — trivial task")
r2 <- sapply(1:1000, sqrt)
toc()

# Task B: computationally heavy — benefit outweighs overhead
heavy_sim <- function(i) max(run_sir(n_days = 500)$I)

tic("Parallel — heavy task")
r3 <- foreach(i = 1:200, .combine = c) %dopar% { heavy_sim(i) }
toc()

tic("Serial — heavy task")
r4 <- sapply(1:200, heavy_sim)
toc()

stopCluster(cl3)
registerDoSEQ()
```

> **Question:** What rule of thumb can you derive from this experiment about when to parallelize?

---

### Pitfall 3: Correlated RNG

```r
cl4 <- makeCluster(2)
registerDoParallel(cl4)

# BAD: set.seed() inside %dopar% — all workers share the same initial seed
bad_seeds <- foreach(i = 1:6, .combine = c) %dopar% {
  set.seed(99)         # WRONG — resets to same seed on every call
  run_sir()$I[50]
}

# GOOD: use L'Ecuyer-CMRG streams
clusterSetRNGStream(cl4, iseed = 99)
good_seeds <- foreach(i = 1:6, .combine = c) %dopar% {
  run_sir()$I[50]      # each worker has its own independent RNG stream
}

cat("Bad (expect repeated values):", bad_seeds, "\n")
cat("Good (all should differ):    ", good_seeds, "\n")

stopCluster(cl4)
registerDoSEQ()
```

---

### When to Parallelize? A Decision Guide

| Situation | Parallelize? |
|-----------|-------------|
| Each task takes < 0.1 sec | Usually **no** — overhead dominates |
| Tasks are fully independent | **Yes** — ideal for parallelism |
| Tasks share mutable state | **No** — race conditions |
| Short loop (< 100 fast iterations) | **No** |
| Parameter sweep, 1000+ simulations | **Yes** |
| Reading/writing many separate files | **Maybe** — disk I/O may bottleneck |
| Fitting models across many datasets | **Yes** |

---

## Summary and Key Takeaways

| Concept | Remember |
|---------|----------|
| Core detection | `detectCores() - 1` (leave one for the OS) |
| Cluster lifecycle | `makeCluster()` → `registerDoParallel()` → work → `stopCluster()` → `registerDoSEQ()` |
| Parallel loop | `foreach(...) %dopar% { }` |
| Serial loop | `foreach(...) %do% { }` (for testing) |
| Combining results | `.combine = c` / `bind_rows` / `rbind` / `"list"` |
| Exporting to workers | `.export = c("obj")` in `foreach` OR `clusterExport(cl, ...)` before |
| Loading packages on workers | `.packages = c("pkg")` in `foreach` |
| RNG safety | `clusterSetRNGStream(cl, iseed = N)` before the loop |
| Error handling | `.errorhandling = "pass"` + `tryCatch` inside the loop |
| When to parallelize | Independent, computationally heavy tasks |

---

## Reflection Questions

Answer individually or as a group before you leave:

1. You're asked to run 10,000 stochastic SEIR simulations for an Ebola outbreak model. Each simulation takes ~2 seconds. Estimate the wall-clock time with 1 core vs. 8 cores. What does this mean practically for outbreak response?

2. A colleague's parallel code always produces slightly different results each run. What is the most likely cause and how would you fix it using `doParallel`?

3. You have a `foreach` loop that occasionally throws an error for certain parameter combinations. How would you modify the loop so one bad combo doesn't kill the whole job?

4. In the parameter sweep, epidemic probability didn't jump sharply at R₀ = 1. Why not, and what does this mean for public health threshold-based policies?

---

*Lab developed for intermediate R users in public health and epidemiology.*  
*Packages: `doParallel`, `foreach`, `tidyverse`, `tictoc`.*
