#!/usr/bin/env nextflow

import groovy.json.JsonSlurper

if (!params.config_secrets) {
  error "Error: missing mandatory parameter --config_secrets"
}

if (!params.input) {
  error "Error: missing mandatory parameter --input"
}

process download {
    tag "${in_map.filename}"
    container "ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.0"
    publishDir "$params.outdir", mode: "move"

    input:
    val in_map 
    path config_path
    path secret_path
    path secret_key

    output:
    // grab basename because decrypted data will drop .crypt4gh extension
    path "${file(in_map.filename).baseName}*"

    script:
    if (secret_key.name != "NO_FILE" && in_map.filename.endsWith("crypt4gh"))
      // if crypt4gh and a key -> decrypt on the fly while downloading
      """
      java -jar /opt/globus-file-handler-cli-1.0.0.jar \
        -Dspring.config.location=${config_path},${secret_path} \
        -s "${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
        --globus_file_download_destination_path "\$PWD" \
        -l ${in_map.size} \
        --crypt4gh \
        --sk ${secret_key}
      """      
    else 
      // else, just download the file
      """
      java -jar /opt/globus-file-handler-cli-1.0.0.jar \
        -Dspring.config.location=${config_path},${secret_path} \
        -s "${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
        --globus_file_download_destination_path "\$PWD" \
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

    download(ch_input, config_path, secrets_path, secret_key)
}


def parseInput(json_file) {
    slurp = new JsonSlurper()
    def slurped = slurp.parseText(json_file.text)
    def meta = slurped.subMap("dir_path_on_guest_collection")
    def parsed = slurped.files.collect { meta + it } 

    return parsed
}
