#!/usr/bin/env nextflow

import groovy.json.JsonSlurper


if (!params.config_application) {
  error "Error: missing mandatory parameter --config_application"
}

if (!params.config_crypt4gh) {
  error "Error: missing mandatory parameter --config_crypt4gh"
}

if (!params.input) {
  error "Error: missing mandatory parameter --input"
}

if (!params.secret_key) {
  error "Error: missing --secret_key"
}

process download_decrypt_key_handler {
    stageInMode 'copy'
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    maxRetries 2

    tag "${in_map.filename}"
    // drops the "output" directory from path when publishing
    publishDir "$params.outdir", mode: "move", saveAs: { "${file(it).getName()}" }
    container "ghcr.io/ebi-gdp/globus-file-handler-cli:1.0.5"

    input:
    val in_map
    path application_properties, stageAs: "application.properties"
    path crypt4gh_properties, stageAs: "application-crypt4gh-secret-manager.properties"
    path secret_key, stageAs: "secret-config.json"

    output:
    path "output/*"

    script:
    """
    mkdir output
    
    java -jar /opt/globus-file-handler-cli-1.0.5.jar \
      --spring.profiles.active=crypt4gh-secret-manager \
      --globus_file_transfer_source_path "globus:///${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      --globus_file_transfer_destination_path "file:///\$PWD/output/${file(in_map.filename).baseName}" \
      --file_size ${in_map.size} \
      --crypt4gh \
      --sk "file:///\$PWD/secret-config.json"
    """
}

workflow {
    // using first() to create reusable value channels
    Channel.fromPath(params.secret_key, checkIfExists: true).first().set { secret_key }
    Channel.fromPath(params.config_application, checkIfExists: true).first().set { application_properties }
    Channel.fromPath(params.config_crypt4gh, checkIfExists: true).first().set { crypt4gh_properties }

    // this channel is a list of hashmaps, one for each file to be downloaded
    Channel.fromPath(params.input, checkIfExists: true).map { parseInput(it) }.flatten().set { ch_input }

    download_decrypt_key_handler(ch_input, application_properties, crypt4gh_properties, secret_key)
}


def parseInput(json_file) {
    slurp = new JsonSlurper()
    def slurped = slurp.parseText(json_file.text)
    def meta = slurped.subMap("dir_path_on_guest_collection")
    def parsed = slurped.files.collect { meta + it }

    return parsed
}
