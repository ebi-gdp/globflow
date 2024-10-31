#!/usr/bin/env nextflow

import groovy.json.JsonSlurper


if (!params.config_application) {
  error "Error: missing mandatory parameter --config_application"
}

if (!params.input) {
  error "Error: missing mandatory parameter --input"
}

if (params.decrypt) {
  if (!params.config_crypt4gh) {
    error "Error: missing mandatory parameter --config_crypt4gh"
  }
  if (!params.secret_key) {
    error "Error: missing --secret_key"
  }
} else {
  if (params.config_crypt4gh || params.secret_key) {
    log.info "INFO: Ignoring --config_crypt4gh or --secret_key when --decrypt is not set"
  }
}

if (params.debug) {
    log.info "INFO: Debug mode enabled (not cleaning up sensitive intermediate files)"
} else {
    log.info "INFO: Debug mode disabled (being careful to clean up sensitive intermediate files)"
}


process download {
    stageInMode "${ params.debug ? 'copy' : 'symlink' }"
    tag "${in_map.filename}"
    // drops the "output" directory from path when publishing
    publishDir "$params.outdir", mode: "move", saveAs: { "${file(it).getName()}" }
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    beforeScript 'mkdir output'

    input:
    val in_map
    path application_properties, stageAs: "application.properties"

    output:
    path "output/*"

    script:
    """
    java -jar /opt/globus-file-handler-cli-1.0.5.jar \
      --globus_file_transfer_source_path "globus:///${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      --globus_file_transfer_destination_path "file:///\$PWD/output/${file(in_map.filename).baseName}" \
      --file_size ${in_map.size}

    if [ "$params.debug" = false ] ; then
      # this will keep nextflow log files but delete sensitive inputs
      echo "Cleaning all files except output directory"
      rm *.properties
    fi
    """
}

process download_decrypt_key_handler {
    stageInMode "${ params.debug ? 'copy' : 'symlink' }"

    tag "${in_map.filename}"
    // drops the "output" directory from path when publishing
    publishDir "$params.outdir", mode: "move", saveAs: { "${file(it).getName()}" }
    errorStrategy { sleep(Math.pow(2, task.attempt) * 200 as long); return 'retry' }
    beforeScript 'mkdir output'

    input:
    val in_map
    path application_properties, stageAs: "application.properties"
    path crypt4gh_properties, stageAs: "application-crypt4gh-secret-manager.properties"
    path secret_key, stageAs: "secret-config.json"

    output:
    path "output/*"

    script:
    """
    java -jar /opt/globus-file-handler-cli-1.0.5.jar \
      --spring.profiles.active=crypt4gh-secret-manager \
      --globus_file_transfer_source_path "globus:///${in_map.dir_path_on_guest_collection}/${in_map.filename}" \
      --globus_file_transfer_destination_path "file:///\$PWD/output/${file(in_map.filename).baseName}" \
      --file_size ${in_map.size} \
      --crypt4gh \
      --sk "file:///\$PWD/secret-config.json"

    if [ "$params.debug" = false ] ; then
      # this will keep nextflow log files but delete sensitive inputs
      echo "Cleaning all files except output directory"
      rm *.sec *.properties *.json
    fi
    """
}

workflow {
    // using first() to create reusable value channels
    Channel.fromPath(params.config_application, checkIfExists: true).first().set { application_properties }

    // this channel is a list of hashmaps, one for each file to be downloaded
    Channel.fromPath(params.input, checkIfExists: true).map { parseInput(it) }.flatten().set { ch_input }

    if (params.decrypt) {
      Channel.fromPath(params.secret_key, checkIfExists: true).first().set { secret_key }
      Channel.fromPath(params.config_crypt4gh, checkIfExists: true).first().set { crypt4gh_properties }
      download_decrypt_key_handler(ch_input, application_properties, crypt4gh_properties, secret_key)
    } else {
      download(ch_input, application_properties)
    }
}


def parseInput(json_file) {
    slurp = new JsonSlurper()
    def slurped = slurp.parseText(json_file.text)
    def meta = slurped.subMap("dir_path_on_guest_collection")
    def parsed = slurped.files.collect { meta + it }

    return parsed
}
