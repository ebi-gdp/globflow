## What's this useful for?

We needed a way to:

1) Reliably download files from a Globus collection over HTTPS
2) (Optionally) decrypt them on the fly ([crypt4gh](https://github.com/EGA-archive/crypt4gh))
3) Store the plaintext files in an object store (bucket), ready for cloud based data science workflows

The [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) takes care of 1) and 2). 

`globflow` wraps the CLI using [Nextflow](https://www.nextflow.io/) to support parallel downloads and [Fusion file system](https://seqera.io/fusion/) to transparently upload plaintext data to an object store. 

Downloaded files can also be saved to a local filesystem. 

## Parameters

`--input` must be a JSON array with the following structure:

```
{
    "dir_path_on_guest_collection": "bwingfield@ebi.ac.uk/test_hapnest/",
    "files": [
        {
            "filename": "hapnest.pvar",
            "size": 278705850
        },
        {
            "filename": "hapnest.pgen.crypt4gh",
            "size": 278825058
        }
    ]
}
```

`--config_secrets` must be a path to a spring boot application properties file with the following structure:

```
globus.guest-collection.domain=SECRET
globus.aai.client-id=SECRET
globus.aai.client-secret=SECRET
globus.aai.scopes=SECRET
```

(replace SECRET with your sensitive data)

`--key` must be the secret key pair of the recipients public key. It should probably be made by the crypt4gh CLI.

## Example use cases

### Downloading files to local storage in parallel

```
$ nextflow run main.nf -profile <docker/singularity> \
  --config_secrets assets/secret.properties \
  --input assets/example_input.json \
  --outdir downloads \
  --threads 10 
```

It's a good idea to:

* set --threads to do multiple downloads
* use a local executor, the overhead of submitting jobs to a grid executor like SLURM isn't worth it 

By default parallel downloads are disabled (`--threads 1`).

### Downloading files with crypt4gh decryption on the fly

It makes sense to submit these jobs to [a grid executor](https://www.nextflow.io/docs/latest/executor.html), like SLURM or cloud batch, because decryption on the fly will use ~1 CPU for each file:

```
$ nextflow run main.nf -profile <docker/singularity>  \
  --config_secrets assets/secret.properties \
  --input assets/example_input.json \
  --outdir downloads \
  --secret_key key \
  --threads 10 

```

When using a grid executor, `--threads` will control the number of jobs submitted to the scheduler.

If you're running globflow on a desktop computer, try setting `--threads` to the number of CPUs you have. 

Globflow will only try to decrypt files with a `.crypt4gh` extension, and will download other files normally. 

### Downloading files to an object store (bucket) 

It's possible to use nextflow's support for object storage to transfer files from Globus directly to a bucket:

```
$ nextflow run main.nf -profile <docker/singularity> \
  --config_secrets assets/secret.properties \
  --input assets/example_input.json \
  --secret_key key  \
  --outdir gs://test-bucket/downloads \
  -w gs://test-bucket/work
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
