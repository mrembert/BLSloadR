library(data.table)
library(dplyr)
library(bench)

# 1. Setup Data Generation
set.seed(123)

# Function to generate a random data frame
generate_data <- function(n_rows, n_cols) {
  dt <- data.table(
    series_id = sprintf("ID%06d", 1:n_rows),
    year = sample(2000:2020, n_rows, replace = TRUE),
    period = sample(sprintf("M%02d", 1:12), n_rows, replace = TRUE),
    value = runif(n_rows)
  )

  # Add some random key columns
  for (i in 1:n_cols) {
    col_name <- paste0("key_col_", i)
    dt[[col_name]] <- sample(sprintf("CODE%03d", 1:100), n_rows, replace = TRUE)
  }
  return(dt)
}

# Generate Main Data Table (simulate ~100k rows)
main_dt <- generate_data(100000, 5)

# Generate Mapping Tables (simulate ~20 mapping files)
mapping_files <- paste0("map.file.", 1:20)
downloads <- list()

for (f in mapping_files) {
  # Each mapping file maps one of the key columns to descriptive text
  key_idx <- sample(1:5, 1)
  key_col <- paste0("key_col_", key_idx)

  map_dt <- data.table(
    key = unique(main_dt[[key_col]]),
    desc = paste0("Description for ", unique(main_dt[[key_col]])),
    extra = paste0("Extra info for ", unique(main_dt[[key_col]]))
  )

  # Ensure join column matches
  setnames(map_dt, "key", key_col)

  # Mock get_bls_data structure
  downloads[[f]] <- list(data = map_dt)
  class(downloads[[f]]) <- "bls_data"
}

# Mock get_bls_data function
get_bls_data <- function(obj) {
  if (inherits(obj, "bls_data")) return(obj$data)
  return(obj)
}


# 2. Define Benchmark Functions

# Current approach: Iterative dplyr::left_join
current_impl <- function(full_dt, mapping_files, downloads) {
  processing_steps <- c()
  suppress_warnings <- TRUE

  for (map_file in mapping_files) {
    if (map_file %in% names(downloads)) {
      tryCatch({
        map_dt <- get_bls_data(downloads[[map_file]])

        # Mocking the column removal logic
        map_dt <- map_dt |> dplyr::select(-any_of(c("display_level", "sort_sequence")))

        if (ncol(map_dt) == 2) {
          join_col <- names(map_dt)[1]
          if (join_col %in% names(full_dt)) {
            full_dt <- dplyr::left_join(full_dt, map_dt, by = join_col)
          }
        } else {
          potential_join_cols <- names(map_dt)[1:(ncol(map_dt) - 1)]
          join_cols <- intersect(potential_join_cols, names(full_dt))
          if (length(join_cols) > 0) {
            full_dt <- dplyr::left_join(full_dt, map_dt, by = join_cols)
          }
        }
      }, error = function(e) {})
    }
  }
  return(full_dt)
}

# Proposed approach: data.table::merge with Reduce
proposed_impl <- function(full_dt, mapping_files, downloads) {
  # Convert to data.table explicitly (if not already)
  full_dt <- as.data.table(full_dt)

  # Helper to process a single mapping file
  process_mapping <- function(current_dt, map_file) {
    if (map_file %in% names(downloads)) {
      tryCatch({
        map_dt <- get_bls_data(downloads[[map_file]])

        # Mocking column removal
        map_dt <- map_dt[, !names(map_dt) %in% c("display_level", "sort_sequence"), with = FALSE]

        join_cols <- character(0)

        if (ncol(map_dt) == 2) {
          potential_col <- names(map_dt)[1]
          if (potential_col %in% names(current_dt)) {
            join_cols <- potential_col
          }
        } else {
          potential_join_cols <- names(map_dt)[1:(ncol(map_dt) - 1)]
          join_cols <- intersect(potential_join_cols, names(current_dt))
        }

        if (length(join_cols) > 0) {
          # Use merge(..., all.x = TRUE) for left join behavior
          # sort = FALSE to preserve order (faster)
          current_dt <- merge(current_dt, map_dt, by = join_cols, all.x = TRUE, sort = FALSE)
        }

      }, error = function(e) {})
    }
    return(current_dt)
  }

  # Use Reduce to iterate
  result_dt <- Reduce(process_mapping, mapping_files, init = full_dt)

  return(tibble::as_tibble(result_dt))
}


# 3. Run Benchmark
# Verify correctness first (on a small subset)
small_dt <- main_dt[1:100]
res_current <- current_impl(small_dt, mapping_files, downloads)
res_proposed <- proposed_impl(small_dt, mapping_files, downloads)

# Check dimensions and column names
message("Correctness Check:")
message("Current dims: ", paste(dim(res_current), collapse="x"))
message("Proposed dims: ", paste(dim(res_proposed), collapse="x"))
if (identical(dim(res_current), dim(res_proposed)) &&
    all(names(res_current) %in% names(res_proposed))) {
  message("PASS: Results appear structurally similar.")
} else {
  message("FAIL: Results differ.")
  print(setdiff(names(res_current), names(res_proposed)))
}

# Run timing
message("\nRunning Benchmark...")
results <- bench::mark(
  current = current_impl(main_dt, mapping_files, downloads),
  proposed = proposed_impl(main_dt, mapping_files, downloads),
  check = FALSE, # Results might differ in row order or column order slightly
  iterations = 5
)

print(results)
