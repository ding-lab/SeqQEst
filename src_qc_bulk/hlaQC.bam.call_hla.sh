#!/bin/bash

# Hua Sun
# 2021-03-01;2020-10-06
# bash run.sh -T dna -N sampleName -O ./OUT -B sample.bam

# -C config.ini
# -P bwa/razers3/optitype
# -N sampleName
# -T dna/rna
# -B *.bam
# -O outdir
# output outdir/sample/...


CONFIG=""

TYPE="dna"
pipeline="bwa"

while getopts "C:P:N:T:B:O:" opt; do
  case $opt in
    C)
      CONFIG=$OPTARG
      ;;
    P)
      pipeline=$OPTARG
      ;;
    N)
      NAME=$OPTARG
      ;;
    T)
      TYPE=$OPTARG
      ;;
    B)
      BAM=$OPTARG
      ;; 
    O)
      OUTDIR=$OPTARG
      ;;           
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done


mkdir -p $OUTDIR

OUT=$OUTDIR/$NAME
mkdir -p $OUT


# load contig.ini
source ${CONFIG}



HLA_FASTA=''

if [[ $TYPE == "dna" ]] || [[ $TYPE == "DNA" ]] || [[ $TYPE == "WES" ]] || [[ $TYPE == "WGS" ]];then HLA_FASTA=$HLA_REF_DNA; fi
if [[ $TYPE == "rna" ]] || [[ $TYPE == "RNA" ]] || [[ $TYPE == "RNA-Seq" ]];then HLA_FASTA=$HLA_REF_RNA; fi




##===========================##
##       Set function
##===========================##

# set run OptiType function
function run_optiType {
    if [[ $TYPE == "dna" ]] || [[ $TYPE == "DNA" ]] || [[ $TYPE == "WES" ]] || [[ $TYPE == "WGS" ]]; then
        $OptiTypePipeline -i $OUT/$NAME.fished_1.fastq $OUT/$NAME.fished_2.fastq --dna -o $OUT --config ${config_for_optiType}
    fi

    if [[ $TYPE == "rna" ]] || [[ $TYPE == "RNA" ]] || [[ $TYPE == "RNA-Seq" ]]; then
        $OptiTypePipeline -i $OUT/$NAME.fished_1.fastq $OUT/$NAME.fished_2.fastq --rna -o $OUT --config ${config_for_optiType}
    fi
    
    exit 0
}




##===========================##
##       Main
##===========================##

##------------- OptiTypePipeline (only using it re-run optitype)
if [[ $pipeline == "optiType" ]]; then  
    n=`ls $OUT/*/*.tsv | wc -l`
    
    if [[ $n > 0 ]];then
        echo "[INFO] The $OUT/$NAME already exist HLA genotype ..." >&2
        exit 0
    fi
    
    run_optiType
    exit 0
fi





##------------- bam to fastq
$SAMTOOLS sort -m 2G -@ 6 -o $OUT/${NAME}.sortbyName.bam -n $BAM
$SAMTOOLS fastq -1 $OUT/${NAME}.r1.fastq.gz -2 $OUT/${NAME}.r2.fastq.gz -0 /dev/null -s /dev/null -n -F 0x900 $OUT/${NAME}.sortbyName.bam

FQ1=$OUT/${NAME}.r1.fastq.gz
FQ2=$OUT/${NAME}.r2.fastq.gz


rm -f $OUT/${NAME}.sortbyName.bam






##------------- bwa
if [[ $pipeline == "bwa" ]]; then
    # R1
    $BWA mem -t 8 $HLA_FASTA $FQ1 | $SAMTOOLS view -Shb -F 4 -o $OUT/$NAME.fished_1.bam -
    $SAMTOOLS bam2fq $OUT/$NAME.fished_1.bam > $OUT/$NAME.fished_1.fastq

    ## remove temp file 
    rm -f $OUT/$NAME.fished_1.bam


    # R2
    $BWA mem -t 8 $HLA_FASTA $FQ2 | $SAMTOOLS view -Shb -F 4 -o $OUT/$NAME.fished_2.bam -
    $SAMTOOLS bam2fq $OUT/$NAME.fished_2.bam > $OUT/$NAME.fished_2.fastq

    ## remove temp file 
    rm -f $OUT/$NAME.fished_2.bam
    rm -f $FQ1 $FQ2


    # run OptiType
    run_optiType
    exit 0
fi


#rm -f $OUT/$NAME.fished_1.fastq $OUT/$NAME.fished_2.fastq


