
task Star {
  File genomic_fastq
  File gtf
  File star_genome  # todo should be included in genome directly

  # note that if runThreadN must always equal 1 or the order will be modified
  # could pipe zcat to head in readFilesCommand for speed? need only align about ~ 10m reads
  command {
    tar -zxvf ${star_genome}
    STAR  --readFilesIn ${genomic_fastq} \
      --genomeDir ./star \
      --quantMode TranscriptomeSAM \
      --outSAMstrandField intronMotif \
      --genomeLoad NoSharedMemory \
      --sjdbGTFfile ${gtf} \
      --readFilesCommand "zcat" \
      --outSAMtype BAM Unsorted  \
      --outSAMunmapped Within \
      --limitBAMsortRAM 30000000000
  }
  output {
    File output_bam = "Aligned.out.bam"
  }

  runtime {
    docker: "humancellatlas/star_dev:v1"
    memory: "40 GB"  # not used locally
    disks: "local-disk 250 HDD"  # not used locally
  }
}


task ExtractSubsetReadIndicesInline {
  File bam_file
  Int chromosome

  command <<<
    python <<CODE

    import os
    import json
    import pysam

    # set some constants
    n_aligned = 10000
    n_unaligned = 2000

    with pysam.AlignmentFile('${bam_file}', 'rb') as fin:

        aligned, unaligned = 0, 0  # counters
        chrom_string = str(${chromosome})
        indices = []

        for i, record in enumerate(fin):

            # should be a check that works with all annotation types
            if record.is_unmapped and unaligned < n_unaligned:
                indices.append(i)
                unaligned += 1
            elif not record.is_unmapped and chrom_string in record.reference_name and aligned < n_aligned:
                indices.append(i)
                aligned += 1

            # check termination condition (we have the requisite number of reads
            if aligned == n_aligned and unaligned == n_unaligned:
                break

    # write indices
    with open('indices.json', 'w') as fout:
        json.dump(indices, fout)

    # warn user if early termination occurred
    if aligned < n_aligned or unaligned < n_unaligned:
        print('Warning: %s: test file construction terminated early. Only %d unaligned '
              'and %d aligned reads were written to %s' %
              (script_name, n_unaligned, n_aligned, indices.json))

    CODE
    >>>

  output {
    File output_indices_json = "indices.json"
  }

  runtime {
    docker: "ambrosejcarr/python-hca:latest"  # need to make a docker file for this script
    memory: "1 GB"
    disks: "local-disk 100 HDD"
  }

}


task SubsetFastqFromIndicesInline {
  File indices_json
  File input_fastq_r1
  File input_fastq_r2
  File input_fastq_i1

  command <<<
  python <<CODE

  import json
  import gzip
  import scsequtil.fastq as fq


  with open('${indices_json}', 'r') as f:
      indices = set(json.load(f))


  # create fastq readers
  fastqs = ['${input_fastq_r1}', '${input_fastq_r2}', '${input_fastq_i1}']
  readers = zip(fq.Reader(f) for f in fastqs)

  # create output filenames
  output_filenames = [f.partition('.fastq')[0] + '_subset.fastq.gz' for f in fastqs]

  # open output files
  output_fileobjs = [gzip.open(f, 'wt') for f in output_filenames]

  # write records in indices to output files and close files
  try:
      for i, records in enumerate(zip(iter(r) for r in readers)):  # bug
          if i in indices:
              for record, fout in zip(records, output_fileobjs):
                  fout.write(record)

  finally:
      for f in output_fileobjs:
          f.close()

  CODE
  >>>


  runtime {
    docker: "ambrosejcarr/python-hca:latest"
    memory: "2.5 GB"
    disks: "local-disk 1000 HDD"  # todo put this in to see if it breaks cromwell
  }

  output {
    Array[File] output_subset_fastqs = glob("*_subset.fastq.gz")
  }

}


workflow generate_test {

  File input_fastq_r1
  File input_fastq_r2
  File input_fastq_i1
  File gtf
  File star_genome
  Int chromosome

  call Star {
    input:
      genomic_fastq = input_fastq_r2,
      gtf = gtf,
      star_genome = star_genome
  }

  call ExtractSubsetReadIndicesInline {
    input:
      bam_file = Star.output_bam,
      chromosome = chromosome
  }

  call SubsetFastqFromIndicesInline {
    input:
      indices_json = ExtractSubsetReadIndicesInline.output_indices_json,
      input_fastq_r1 = input_fastq_r1,
      input_fastq_r2 = input_fastq_r2,
      input_fastq_i1 = input_fastq_i1
  }

  output {
    Array[File] output_subset_fastqs = SubsetFastqFromIndicesInline.output_subset_fastqs
  }

}