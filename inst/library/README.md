# Built-in function library

Each subfolder is one self-contained library entry:

```
<name>/
  entry.yml     description, tags, parameters, outputs, methods text, version
  function.R    the R code (defines one function called <name>)
  report.Rmd    optional report fragment
```

To add or change a function, edit these files; no package rebuild is needed.
User libraries use the same layout in the folders listed under
`library.user_dirs` in the config, and override built-in entries of the same
name. Entries are checked on load; a malformed entry is reported and skipped.
Bump `version` in `entry.yml` whenever behaviour changes, because projects
record the version they used.
