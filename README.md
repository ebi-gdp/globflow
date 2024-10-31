## What's this useful for?

We needed a way to:

1) Reliably download files from a Globus collection over HTTPS
2) Optionally decrypt them on the fly ([crypt4gh](https://github.com/EGA-archive/crypt4gh))
3) Store the plaintext files in an object store (bucket), ready for cloud based data science workflows

The [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) takes care of 1) and 2). 

`globflow` wraps the CLI using [Nextflow](https://www.nextflow.io/) to support parallel downloads and [Fusion file system](https://seqera.io/fusion/) to transparently upload plaintext data to an object store. 

Downloaded files can also be saved to a local filesystem. 

> [!NOTE]  
> This workflow grabs crypt4gh secret keys from the INTERVENE key handler service, but could be adapted to work with local crypt4gh key pairs

## Parameters

### File input

`--input` must be a JSON array with the following structure:

```
{
    "dir_path_on_guest_collection": "bwingfield@ebi.ac.uk/test_hapnest/",
    "files": [
        {
            "filename": "hapnest.pgen.crypt4gh",
            "size": 278825058
        }
    ]
}
```

### Secret key

`--secret_key` must be a JSON file with the following structure:

```
{"secretId": "77451C57-0FCC-460F-91A3-E0DED05B440F", "secretIdVersion": "1"}
```

The secret key is used to contact the platform key handler service and grab the correct crypt4gh secret key.

### Application properties 

> [!TIP]
> Be careful of trailing whitespace in properties files

`--config_application` must be a path to a spring boot application properties file with the following structure:

```
#####################################################################################
# Application config
#####################################################################################
spring.main.web-application-type=none
data.copy.buffer-size=8192
#####################################################################################
# Apache HttpClient connection config
#####################################################################################
webclient.connection.pipe-size=${data.copy.buffer-size}
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
globus.guest-collection.domain=@globus.guest-collection.url@
#Oauth
globus.aai.access-token.uri=https://auth.globus.org/v2/oauth2/token
globus.aai.client-id=@globus.aai.client-id@
globus.aai.client-secret=@globus.aai.client-secret@
globus.aai.scopes=https://auth.globus.org/scopes/c1e6310c-11d5-4e8a-9443-211884f04c6f/https
#####################################################################################
# Logging config
#####################################################################################
logging.level.uk.ac.ebi.intervene=INFO
logging.level.org.springframework=WARN
logging.level.org.apache.http=WARN
logging.level.org.apache.http.wire=WARN
```

See the [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) README for a description of the configuration. 

### crypt4gh application properties

`--config_crypt4gh` must be a path to a spring boot application properties file with the following structure:

```
#####################################################################################
# Crypt4gh config
#####################################################################################
crypt4gh.binary-path=/opt/bin/crypt4gh
crypt4gh.shell-path=/bin/bash -c
#####################################################################################
# Intervene service config
#####################################################################################
intervene.key-handler.base-url=http://localhost:8040/bff/key-handler
intervene.key-handler.keys.uri=/key/{secretId}/version/{secretIdVersion}
intervene.key-handler.basic-auth=${KEY_HANDLER_BASIC_AUTH:basic-auth}
intervene.key-handler.secret-key.password=${SEC_KEY_PASSWD:test-password}
```

See the [file handler CLI](https://github.com/ebi-gdp/globus-file-handler-cli) README for a description of the configuration. 

## Example use cases

> [!TIP]
> `--debug` can be helpful to keep files containing sensitive data if you're having problems with a transfer (disabled by default)

### Download files from a Globus collection over HTTPS 

```
$ nextflow run main.nf -profile docker \
  --input input.json \
  --config_application application.properties \
  --outdir downloads
```

### Downloading files with crypt4gh decryption on the fly

It makes sense to submit these jobs to [a grid executor](https://www.nextflow.io/docs/latest/executor.html), like SLURM or cloud batch, because decryption on the fly will use ~1 CPU for each file:

```
$ nextflow run main.nf -profile docker \
  --input input.json \
  --secret_key key.json \
  --config_application application.properties \
  --config_crypt4gh application-crypt4gh-secret-manager.properties \
  --config_secrets assets/secret.properties \
  --outdir downloads \
  --decrypt
```

### Downloading files to an object store (bucket) 

It's possible to use nextflow's support for object storage to transfer files from Globus directly to a bucket:

```
$ nextflow run main.nf -profile docker \
  -c cloud.config \
  --input input.json \
  --secret_key key.json \
  --config_application application.properties \
  --config_crypt4gh application-crypt4gh-secret-manager.properties \
  --config_secrets assets/secret.properties \
  --outdir gs://pathtobucket/downloads \
  -w gs://pathworkbucket/work
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
    workspaceId = 'work'
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

## Helm support

`helm/` contains a [helm chart](https://helm.sh/docs/topics/charts/) which can install a [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) to a Kubernetes cluster. 

In the helm chart worker processes run in Cloud Batch by default with crypt4gh decryption on the fly enabled.
