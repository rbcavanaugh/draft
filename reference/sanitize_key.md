# Sanitize names into valid R list keys

Converts raw parameter or variable names into clean, valid R list keys
suitable for use as named-list elements in inline reporting paths. Names
are lowercased; spaces and non-alphanumeric characters are replaced with
underscores; leading/trailing underscores are stripped. Duplicate keys
receive a numeric suffix (`_2`, `_3`, ...) to ensure uniqueness.

## Usage

``` r
sanitize_key(x)
```

## Arguments

- x:

  A character vector of names to sanitize.

## Value

A character vector the same length as `x`, with unique, valid R names.
