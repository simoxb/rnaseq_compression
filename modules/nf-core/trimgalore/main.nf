process TRIMGALORE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/trim-galore:0.6.7--hdfd78af_0' :
        'biocontainers/trim-galore:0.6.7--hdfd78af_0' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*trimmed*val_{1,2}.f*q")	, emit: reads
    tuple val(meta), path("*report.txt")                        , emit: log     , optional: true
    tuple val(meta), path("*unpaired*.fq")                   	, emit: unpaired, optional: true
    tuple val(meta), path("*.html")                             , emit: html    , optional: true
    tuple val(meta), path("*.zip")                              , emit: zip     , optional: true
    path "versions.yml"                                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    // Calculate number of --cores for TrimGalore based on value of task.cpus
    // See: https://github.com/FelixKrueger/TrimGalore/blob/master/Changelog.md#version-060-release-on-1-mar-2019
    // See: https://github.com/nf-core/atacseq/pull/65
    def cores = 1
    if (task.cpus) {
        cores = (task.cpus as int) - 4
        if (meta.single_end) cores = (task.cpus as int) - 3
        if (cores < 1) cores = 1
        if (cores > 8) cores = 8
    }

    // Added soft-links to original fastqs for consistent naming in MultiQC
    def prefix = task.ext.prefix ?: "${meta.id}"
    if (meta.single_end) {
        def args_list = args.split("\\s(?=--)").toList()
        args_list.removeAll { it.toLowerCase().contains('_r2 ') }
        """
        [ ! -f  ${prefix}.fastq ] && ln -s $reads ${prefix}.fastq
        trim_galore \\
            ${args_list.join(' ')} \\
            --cores $cores \\
            ${prefix}.fastq

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            trimgalore: \$(echo \$(trim_galore --version 2>&1) | sed 's/^.*version //; s/Last.*\$//')
            cutadapt: \$(cutadapt --version)
        END_VERSIONS
        """
    } else {
        """
        [ ! -f  ${prefix}_1.fastq ] && ln -s ${reads[0]} ${prefix}_1.fastq
        [ ! -f  ${prefix}_2.fastq ] && ln -s ${reads[1]} ${prefix}_2.fastq
        trim_galore \\
            $args \\
            --cores $cores \\
            --paired \\
            --dont_gzip \\
            --basename ${meta.id}_tg_out \\
            ${prefix}_1.fastq \\
            ${prefix}_2.fastq 

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            trimgalore: \$(echo \$(trim_galore --version 2>&1) | sed 's/^.*version //; s/Last.*\$//')
            cutadapt: \$(cutadapt --version)
        END_VERSIONS
        """
    }

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    if (meta.single_end) {
        output_command = "echo '' > ${prefix}_trimmed.fq ;"
        output_command += "touch ${prefix}.fastq_trimming_report.txt"
    } else {
        output_command = "echo '' > ${prefix}_1_trimmed.fq ;"
        output_command += "touch ${prefix}_1.fastq_trimming_report.txt ;"
        output_command += "echo '' > ${prefix}_2_trimmed.fq ;"
        output_command += "touch ${prefix}_2.fastq_trimming_report.txt"
    }
    """
    ${output_command}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        trimgalore: \$(echo \$(trim_galore --version 2>&1) | sed 's/^.*version //; s/Last.*\$//')
        cutadapt: \$(cutadapt --version)
    END_VERSIONS
    """
}

