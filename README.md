## What's this useful for?

We needed a way to:

1) Reliably download files from a Globus collection over HTTPS
2) Optionally decrypt them on the fly (crypt4gh)
3) Store the plaintext files in an object store (bucket), ready for cloud based data science workflows

The [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) takes care of 1) and 2). 

`globflow` wraps the CLI to support parallel downloads and transparent upload to object stores. 
