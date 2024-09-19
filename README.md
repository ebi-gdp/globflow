## What's this useful for?

We needed a way to:

1) Reliably download files from a Globus collection over HTTPS
2) Decrypt them on the fly ([crypt4gh](https://github.com/EGA-archive/crypt4gh))
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
#####################################################################################
# Application config
#####################################################################################
data.copy.buffer-size=8192
#####################################################################################
# Apache HttpClient connection config
#####################################################################################
webclient.connection.pipe-size=4096
webclient.connection.connection-timeout=5
webclient.connection.socket-timeout=0
webclient.connection.read-write-timeout=30000
#####################################################################################
# File download retry config
#####################################################################################
# EXPONENTIAL/FIXED
file.download.retry.strategy=FIXED
file.download.retry.attempts.max=3
# Exponential
file.download.retry.attempts.delay=1000
file.download.retry.attempts.maxDelay=30000
file.download.retry.attempts.multiplier=2
# Fixed
file.download.retry.attempts.back-off-period=2000
#####################################################################################
# Globus config
#####################################################################################
globus.guest-collection.domain=<url>
#Oauth
globus.aai.access-token.uri=https://auth.globus.org/v2/oauth2/token
globus.aai.client-id=<id>
globus.aai.client-secret=<token>
globus.aai.scopes=<url>
#####################################################################################
# Crypt4gh config
#####################################################################################
crypt4gh.binary-path=/opt/bin/crypt4gh
crypt4gh.shell-path=/bin/bash -c
#####################################################################################
# Logging config
#####################################################################################
logging.level.uk.ac.ebi.intervene=INFO
logging.level.org.springframework=WARN
logging.level.org.apache.http=WARN
logging.level.org.apache.http.wire=WARN
#####################################################################################
# key handler service config
#####################################################################################
intervene.key-handler.basic-auth=Basic <token>
intervene.key-handler.secret-key.password=<password>
intervene.key-handler.base-url=https://<url>/key-handler
intervene.key-handler.keys.uri=/key/{secretId}/version/{secretIdVersion}
```

See the [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) README for a description of the configuration. 

## Example use cases

### Downloading files with crypt4gh decryption on the fly

It makes sense to submit these jobs to [a grid executor](https://www.nextflow.io/docs/latest/executor.html), like SLURM or cloud batch, because decryption on the fly will use ~1 CPU for each file:

```
$ nextflow run main.nf -profile <docker/singularity>  \
  --config_secrets assets/secret.properties \
  --input assets/example_input.json \
  --outdir downloads \
  --secret_key key
```

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
