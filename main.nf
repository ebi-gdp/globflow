#!/usr/bin/env nextflow

import groovy.json.JsonSlurper

if (!params.config_secrets) {
  error "Error: missing mandatory parameter --config_secrets"
}

if (!params.input) {
  error "Error: missing mandatory parameter --input"
}

if (!params.secret_key) {
  error "Error: missing --secret_key"
}

process download_decrypt {
    maxForks params.threads
    tag "${in_map.filename}"
    publishDir "$params.outdir", mode: "move"
    container "${ workflow.containerEngine == 'singularity' ?
        "oras://ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.4-singularity" :
        "ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.4" }"

    input:
    val in_map
    path secret_config, stageAs: "secret.properties"
    path secret_key, stageAs: "secret-config.json"

    output:
    path "${file(in_map.filename).baseName}"

    script:
    """
    java -jar /opt/globus-file-handler-cli-1.0.4.jar \
      --spring.config.location=./secret.properties \
      --globus_file_transfer_source_path "globus:///${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      --globus_file_transfer_destination_path "file:///\$PWD/${file(in_map.filename).baseName}" \
      --file_size ${in_map.size} \
      --crypt4gh \
      --sk "file:///\$PWD/secret-config.json"
    """
}

workflow {
    // using first() to create reusable value channels
    Channel.fromPath(params.secret_key, checkIfExists: true).first().set { secret_key }
    Channel.fromPath(params.config_secrets, checkIfExists: true).first().set { secrets_config_path }

    // this channel is a list of hashmaps, one for each file to be downloaded
    Channel.fromPath(params.input, checkIfExists: true).map { parseInput(it) }.flatten().set { ch_input }

    download_decrypt(ch_input, secrets_config_path, secret_key)
}


def parseInput(json_file) {
    slurp = new JsonSlurper()
    def slurped = slurp.parseText(json_file.text)
    def meta = slurped.subMap("dir_path_on_guest_collection")
    def parsed = slurped.files.collect { meta + it }

    return parsed
}
