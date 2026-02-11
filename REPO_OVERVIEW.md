# BLSloadR Repository Overview

## Introduction
`BLSloadR` is an R package designed to streamline the retrieval, processing, and analysis of labor market data from the U.S. Bureau of Labor Statistics (BLS). Unlike wrappers for the BLS Public Data API, this package focuses on accessing the flat files directly from `download.bls.gov`. This approach allows for bulk downloading of full historical series without query limits or registration keys.

## Architecture

The package is built on a few core architectural pillars to ensure reliability and performance:

1.  **Direct File Access**: The package bypasses the API to download tab-separated value (TSV) or Excel files directly. This is particularly useful for large datasets like LAUS or CES.
2.  **Smart Caching**: Implemented in `R/download_helpers.R` (`smart_bls_download`), the package uses HTTP `HEAD` requests to check the `Last-Modified` header of remote files. It only downloads files if the remote version is newer than the local cached copy, significantly reducing bandwidth and processing time for repeated runs.
3.  **Robust Parsing**: The `fread_bls` function (in `R/fread_BLS.R`) wraps `data.table::fread` to handle common irregularities in BLS files, such as "phantom columns" (trailing tabs) and header/data mismatches.
4.  **Diagnostic Tracking**: Data retrieval functions return objects that can include detailed diagnostics (download times, warnings, file dimensions, processing steps) via the `bls_data_collection` S3 class.

## Key Components

### Core Data Functions
The package provides specialized functions for major BLS programs, each handling the specific nuances of that dataset:

*   **CES (Current Employment Statistics)**
    *   `get_ces()`: Retrieves state and metro area employment, hours, and earnings. Supports filtering by state or industry and can toggle between "current year" and "all history" files.
    *   `get_national_ces()`: Retrieves national-level employment data. Joins multiple metadata files (industry, supersector, etc.) to provide descriptive labels.

*   **LAUS (Local Area Unemployment Statistics)**
    *   `get_laus()`: Retrieves unemployment rates and labor force data. It supports a wide range of geographies including State, County, Metro, and City. It automatically handles the large file sizes associated with county-level data.

*   **JOLTS (Job Openings and Labor Turnover Survey)**
    *   `get_jolts()`: Retrieves job openings, hires, and separations. It includes options to filter out regional or national aggregates and transforms rate/level codes into human-readable text.

*   **QCEW (Quarterly Census of Employment and Wages)**
    *   `get_qcew()`: Retrieves detailed establishment counts, employment, and wages. Unlike the other functions, this iterates over quarterly CSV "slices" for specific years and quarters, as QCEW is not distributed as a single time-series file.

*   **OEWS (Occupational Employment and Wage Statistics)**
    *   `get_oews()`: Retrieves employment and wages by occupation. It features a `fast_read` optimization that parses metadata directly from series IDs to speed up processing.
    *   `get_oews_areas()`: Retrieves area definitions, optionally with geometry.

*   **SALT (State Alternative Labor Market Measures)**
    *   `get_salt()`: Retrieves alternative measures of labor underutilization (U-1 to U-6). This function scrapes an Excel file rather than a text file, calculates derived metrics (e.g., quartiles), and can attach `tigris` geometry for mapping.

### General Utilities
*   `load_bls_dataset()`: A generic function to download any BLS time series dataset by its two-letter code (e.g., "ci" for Employment Cost Index). It scrapes the BLS directory to find available files and handles the joining of data and metadata.
*   `bls_overview()`: Fetches and displays the documentation text file for a given series directly in R.

### Data Structures
*   **`bls_data_collection`**: The primary return object for functions when `return_diagnostics = TRUE`. It contains:
    *   `$data`: The processed `data.table`.
    *   `$download_diagnostics`: Information about the file download (size, dimensions, url).
    *   `$processing_steps`: A log of transformations applied to the data.
    *   `$warnings`: Any issues encountered during processing.

## Dependencies
The package relies on a modern R stack:
*   **Data Processing**: `data.table` (for high-performance file reading), `dplyr` (for data manipulation), `stringr` (text processing), `lubridate` (date handling).
*   **Web/Network**: `httr` (robust HTTP requests), `rvest` (HTML scraping for directory listing).
*   **Geospatial**: `tigris` and `sf` (for retrieving and handling map geometries in SALT and OEWS functions).
*   **Other**: `readxl` (for reading Excel-based datasets like SALT), `zoo` (for rolling averages/time series).

## Extension Guide
To add support for a new BLS dataset:
1.  **Identify the Source**: Find the 2-letter code for the dataset on `https://download.bls.gov/pub/time.series/`.
2.  **Map the Files**: Identify the specific URLs for the data file, series file, and any other mapping files (industry, area, etc.).
3.  **Create a Wrapper**: Write a `get_*` function that:
    *   Defines the URLs.
    *   Calls `download_bls_files()`.
    *   Joins the data table with the metadata tables using `left_join`.
    *   Applies any necessary cleaning (e.g., dividing rates by 100, parsing dates).
    *   Returns the data or a `create_bls_object`.
