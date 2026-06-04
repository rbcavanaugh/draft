# Launch the draft inline reporting app

Call this from your R session after running your analysis chunks. The
app will have access to all objects in your global environment.

## Usage

``` r
launch_app(env = globalenv(), port = NULL, launch.browser = TRUE)
```

## Arguments

- env:

  The environment to read objects from. Defaults to globalenv().

- port:

  Port to run the app on. Defaults to a random available port.

- launch.browser:

  Whether to open a browser automatically.
