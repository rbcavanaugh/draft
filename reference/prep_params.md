# Prepare a parameters_model object for inline reporting

Formats a `parameters_model` object (output of
[`parameters::model_parameters()`](https://easystats.github.io/parameters/reference/model_parameters.html))
into a nested named list suitable for inline R Markdown / Quarto
reporting.

## Usage

``` r
prep_params(params_obj)
```

## Arguments

- params_obj:

  A `parameters_model` object.

## Value

A named list with one element per parameter. Each element is itself a
named list of formatted strings for all available fields.
