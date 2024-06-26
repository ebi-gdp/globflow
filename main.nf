#!/usr/bin/env nextflow

import groovy.json.JsonSlurper

if (!params.config_secrets) {
  error "Error: missing mandatory parameter --config_secrets"
}

if (!params.input) {
  error "Error: missing mandatory parameter --input"
}


process download_decrypt {
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxForks params.threads
    tag "${in_map.filename}"
    publishDir "$params.outdir", mode: "move"
    container "${ workflow.containerEngine == 'singularity' ?
        "oras://ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.0-singularity" :
        "ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.0" }"

    input:
    val in_map 
    path config_path
    path secret_path
    path secret_key

    output:
    path "${file(in_map.filename).baseName}"

    when:
    in_map.filename.endsWith(".crypt4gh") && secret_key.name != "NO_FILE"
  
    script:
    """
    java -jar /opt/globus-file-handler-cli-1.0.0.jar \
      -Dspring.config.location=${config_path},${secret_path} \
      -s "${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      -d "\$PWD/${file(in_map.filename).baseName}" \
      -l ${in_map.size} \
      --crypt4gh \
      --sk ${secret_key}
    """      
}

process download {
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxForks params.threads
    tag "${in_map.filename}"
    publishDir "$params.outdir", mode: "move"
    container "${ workflow.containerEngine == 'singularity' ?
        "oras://ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.0-singularity" :
        "ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.0" }"

    input:
    val in_map 
    path config_path
    path secret_path
    path secret_key

    output:
    path "${in_map.filename}"

    when:
    !in_map.filename.endsWith(".crypt4gh") || secret_key.name == "NO_FILE"
  
    script:
    """
    java -jar /opt/globus-file-handler-cli-1.0.0.jar \
      -Dspring.config.location=${config_path},${secret_path} \
      -s "${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      -d "\$PWD/${in_map.filename}" \
      -l ${in_map.size}
    """
}

workflow {
    // using first() to create reusable value channels
    Channel.fromPath(params.secret_key, checkIfExists: true).first().set { secret_key }
    Channel.fromPath(params.config_path, checkIfExists: true).first().set { config_path }
    Channel.fromPath(params.config_secrets, checkIfExists: true).first().set { secrets_path }

    // this channel is a list of hashmaps, one for each file to be downloaded
    Channel.fromPath(params.input, checkIfExists: true).map { parseInput(it) }.flatten().set { ch_input }

    // decryption on the fly will automatically happen if a filename ends with .crypt4gh and a --key is provided
    download_decrypt(ch_input, config_path, secrets_path, secret_key)
    // if --key is missing or a file doesn't end with .crypt4gh, just download
    download(ch_input, config_path, secrets_path, secret_key)
}


def parseInput(json_file) {
    slurp = new JsonSlurper()
    def slurped = slurp.parseText(json_file.text)
    def meta = slurped.subMap("dir_path_on_guest_collection")
    def parsed = slurped.files.collect { meta + it } 

    return parsed
}
