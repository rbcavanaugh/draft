# Convert a formatted parameters data frame to a nested list

Convert a formatted parameters data frame to a nested list

## Usage

``` r
params_df_to_list(params)
```

## Arguments

- params:

  A data frame with a `key` column and formatted value columns.

## Value

A named list with one element per row, keyed by `key`.
