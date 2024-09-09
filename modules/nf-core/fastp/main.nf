process FASTP {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastp:0.23.4--h5f740d0_0' :
        'biocontainers/fastp:0.23.4--h5f740d0_0' }"

    input:
    tuple val(meta), path(reads)
    path  adapter_fasta
    val   discard_trimmed_pass
    val   save_trimmed_fail
    val   save_merged

    output:
    tuple val(meta), path('*.fastp.fastq') , optional:true, emit: reads
    tuple val(meta), path('*.json')           , emit: json
    tuple val(meta), path('*.html')           , emit: html
    tuple val(meta), path('*.log')            , emit: log
    tuple val(meta), path('*.fail.fastq')  , optional:true, emit: reads_fail
    tuple val(meta), path('*.merged.fastq'), optional:true, emit: reads_merged
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def adapter_list = adapter_fasta ? "--adapter_fasta ${adapter_fasta}" : ""
    def fail_fastq = save_trimmed_fail && meta.single_end ? "--failed_out ${prefix}.fail.fastq" : save_trimmed_fail && !meta.single_end ? "--failed_out ${prefix}.paired.fail.fastq --unpaired1 ${prefix}_1.fail.fastq --unpaired2 ${prefix}_2.fail.fastq" : ''
    def out_fq1 = discard_trimmed_pass ?: ( meta.single_end ? "--out1 ${prefix}.fastp.fastq" : "--out1 ${prefix}_1.fastp.fastq" )
    def out_fq2 = discard_trimmed_pass ?: "--out2 ${prefix}_2.fastp.fastq"
    // Added soft-links to original fastqs for consistent naming in MultiQC
    // Use single ended for interleaved. Add --interleaved_in in config.
    if ( task.ext.args?.contains('--interleaved_in') ) {
        """
        [ ! -f  ${prefix}.fastq ] && ln -sf $reads ${prefix}.fastq

        fastp \\
            --stdout \\
            --in1 ${prefix}.fastq \\
            --thread $task.cpus \\
            --json ${prefix}.fastp.json \\
            --html ${prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            $args \\
            2> >(tee ${prefix}.fastp.log >&2) \\
            > ${prefix}.fastp.fastq

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
        END_VERSIONS
        """
    } else if (meta.single_end) {
        """
        [ ! -f  ${prefix}.fastq ] && ln -sf $reads ${prefix}.fastq

        fastp \\
            --in1 ${prefix}.fastq \\
            $out_fq1 \\
            --thread $task.cpus \\
            --json ${prefix}.fastp.json \\
            --html ${prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            $args \\
            2> >(tee ${prefix}.fastp.log >&2)

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
        END_VERSIONS
        """
    } else {
        def merge_fastq = save_merged ? "-m --merged_out ${prefix}.merged.fastq" : ''
        """
        [ ! -f  ${prefix}_1.fastq ] && ln -sf ${reads[0]} ${prefix}_1.fastq
        [ ! -f  ${prefix}_2.fastq ] && ln -sf ${reads[1]} ${prefix}_2.fastq
        fastp \\
            --in1 ${prefix}_1.fastq \\
            --in2 ${prefix}_2.fastq \\
            $out_fq1 \\
            $out_fq2 \\
            --json ${prefix}.fastp.json \\
            --html ${prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            $merge_fastq \\
            --thread $task.cpus \\
            --detect_adapter_for_pe \\
            $args \\
            2> >(tee ${prefix}.fastp.log >&2)

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
        END_VERSIONS
        """
    }

    stub:
    def prefix              = task.ext.prefix ?: "${meta.id}"
    def is_single_output    = task.ext.args?.contains('--interleaved_in') || meta.single_end
    def touch_reads         = (discard_trimmed_pass) ? "" : (is_single_output) ? "echo '' > ${prefix}.fastp.fastq" : "echo '' > ${prefix}_1.fastp.fastq ; echo '' > ${prefix}_2.fastp.fastq"
    def touch_merged        = (!is_single_output && save_merged) ? "echo '' >  ${prefix}.merged.fastq" : ""
    def touch_fail_fastq    = (!save_trimmed_fail) ? "" : meta.single_end ? "echo '' > ${prefix}.fail.fastq" : "echo '' > ${prefix}.paired.fail.fastq ; echo '' > ${prefix}_1.fail.fastq ; echo '' > ${prefix}_2.fail.fastq"
    """
    $touch_reads
    $touch_fail_fastq
    $touch_merged
    touch "${prefix}.fastp.json"
    touch "${prefix}.fastp.html"
    touch "${prefix}.fastp.log"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
    END_VERSIONS
    """
}
