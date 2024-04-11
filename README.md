## What's this useful for?

We needed a way to:

1) Reliably download files from a Globus collection over HTTPS
2) Optionally decrypt them on the fly ([crypt4gh](https://github.com/EGA-archive/crypt4gh))
3) Store the plaintext files in an object store (bucket), ready for cloud based data science workflows

The [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) takes care of 1) and 2). 

`globflow` wraps the CLI using [Nextflow](https://www.nextflow.io/) to support parallel downloads and [Fusion file system](https://seqera.io/fusion/) to transparently upload plaintext data to an object store.

## Example runs

### Downloading files

```
$ nextflow run main.nf --config_secrets assets/secret.properties --input assets/example_input.json --outdir downloads
```

### Downloading files with decryption on the fly 

```
$ nextflow run main.nf --config_secrets assets/secret.properties --input assets/example_input.json --outdir downloads --secret_key key
```

### Downloading files to an object store (bucket) 

```
$ nextflow run main.nf --config_secrets assets/secret.properties --input assets/example_input.json --secret_key key  --outdir gs://test-bucket/downloads -w gs://test-bucket/work
```

For best performance use a cloud executor and enable fusion in the nextflow configuration:

```
process {
    executor = 'google-batch'
}

wave {
    enabled = true
}

fusion {
    enabled = true
}

tower {
    accessToken = 'token'
    enabled = true
}

google {
    project = 'prj-id'
    location = 'europe-west2'
    batch {
        spot = true
    }
}
```
