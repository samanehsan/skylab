task downloadSRA {
  String sraID
  String SeqNameFormat
  
  command {
    /usr/bin/fastq-dump --split-files ${SeqNameFormat} --gzip ${sraID}
  }
  output {
    File fastq1 = "${sraID}_1.fastq.gz"
    File fastq2 = "${sraID}_2.fastq.gz"
  }
  runtime {
    docker:"humancellatlas/sratools"
    memory: "4 GB"
    disks :"local-disk 10 HDD"
  }
}

workflow BatchDownloadSra {
  File sra_list
  String PreDefinedSeqID

  Array[Array[String]] sraIDs=read_tsv(sra_list)

  scatter(sID in sraIDs) {
    call downloadSRA {
      input:
        sraID= sID[0],
        SeqNameFormat = PreDefinedSeqID
    }
  }
}

