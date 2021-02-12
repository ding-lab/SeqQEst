#!/bin/bash

# Author: Hua Sun
# Email: hua.sun@wustl.edu or hua.sun229@gmail.com

# 2020-11-10   v1.0  renamed all of scripts; add HLA-QC local version to SeqQEst 
# 2020-07-29   beta v0.3


## USAGE: 

# sh SeqQEst.sh -c <config.ini> -p <pipelineName> -n <name> -o <outdir>

## INSTALL:
# python3.7
# python3 -m pip install pandas



outdir=`pwd`
config="/gscuser/hua.sun/scripts/SeqQEst/config/config.gencode.ini"


type='dna' # dna/rna

while getopts "c:l:p:n:m:f:g:t:b:d:o:" opt; do
  case $opt in
    c)
      config=$OPTARG
      ;;
    p)
      pipeline=$OPTARG
      ;;
    n)
      name=$OPTARG
      ;;
    l)
      loci=$OPTARG
      ;;    
    m)
      matrix=$OPTARG
      ;;
    g)
      group=$OPTARG
      ;;
    t)
      type=$OPTARG
      ;;
    f)
      sampleInfo=$OPTARG
      ;;
    b)
      bam=$OPTARG
      ;;
    d)
      dir=$OPTARG
      ;;
    o)
      outdir=$OPTARG
      ;;
    \?)
      echo "script usage: $(basename $0) [-p] [-n] " >&2
      exit 1
      ;;
  esac
done


if [[ $config == '' ]]; then
  echo "[ERROR] Please set config.ini using -c ..." >&2
  exit
fi

if [ ! -e $config ]; then
  echo "[ERROR] No config file in $config ..." >&2
  exit
fi


source $config



###############################
##     bam QC-L1 (seqQC)
###############################

##------------ fastqc
# input includes fastq.gz/fastq/bam/sam
if [[ $pipeline == "fastqc" ]]; then
    sh $scriptDir/seqQC.bam.fastqc.sh -C ${config} -S ${name} -I ${bam} -O ${outdir}
fi

##------------ Target Coverage
if [[ $pipeline == "tarcov" ]]; then
    sh $scriptDir/seqQC.bam.targetCoverage.sh -C ${config} -S ${name} -B ${bam} -O ${outdir}
fi


##------------ Mean Depth
if [[ $pipeline == "depth" ]]; then
    sh $scriptDir/seqQC.bam.meanDepth.sh -C ${config} -S ${name} -B ${bam} -O ${outdir}
fi


##------------ Flagstat and Stat
if [[ $pipeline == "stat" ]]; then
    sh $scriptDir/seqQC.bam.flagstat.sh -C ${config} -S ${name} -B ${bam} -O ${outdir}
fi


##------------ Summary (QC-L1: step-2)
# manually merge all results
if [[ $pipeline == "qc1-summary" ]]; then
    if [ -d $dir ]; then
  
        ls $dir | sed 's/\///' | perl -ne 'print unless /^\./' | while read sample
        do
            echo [INFO] Summary QC-L1 - $sample ......
	        perl $scriptDir/seqQC.summary.report.pl -n ${sample} -f ${dir}/${sample}/flagstat.txt -s ${dir}/${sample}/bamStats.txt -m ${dir}/${sample}/hsMetrics.txt -d ${dir}/${sample}/meanDepth.txt --qc ${dir}/${sample}/*_fastqc/summary.txt > ${dir}/${sample}/qc1.summary.out
        done

        echo [INFO] Merge summary QC ......
        cat $dir/*/qc1.summary.out > $dir/merged.summary.qc.tmp; head -n 1 $dir/merged.summary.qc.tmp > $dir/head.tmp; grep -v 'Total_reads' $dir/merged.summary.qc.tmp > $dir/merged.summary.qc.2.tmp; cat $dir/head.tmp $dir/merged.summary.qc.2.tmp > $dir/qc1.seq.summary.merged.out
        
        rm -f $dir/*.tmp
    fi
fi


##------------ Plot (QC-L1: step-3)
# manually merge all results
if [[ $pipeline == "qc1-plot" ]]; then
    ${PYTHON3} $scriptDir/seqQC.summary.plot.py -d ${matrix} --info ${sampleInfo} -o ${outdir}
fi




###############################
##    bam QC-L2 (germlineQC)
###############################

##------------ Bamreadcount (QC-L2: step-1)
if [[ $pipeline == "qc2-brc" ]]; then
    sh $scriptDir/germlineQC.run.bamreadount.sh -C ${config} -L ${GermlineLoci} -S ${name} -B ${bam} -O ${outdir}
fi


##------------ Merge the vaf from bamreadcount (QC-L2: step-2)
if [[ $pipeline == "qc2-merge" ]]; then 
  # the dir is *.vaf dir from bamreadcount
    sh $scriptDir/germlineQC.merge_vaf_table.sh -C ${config} -L ${GermlineLoci} -D ${dir} -O ${outdir}
fi


##------------ Summary QC-L2 (QC-L2: step-3)
if [[ $pipeline == "qc2-summary" ]]; then
    mkdir -p $outdir
  
  # output - all cor.
    echo "[INFO] qc2-summary - Calculate correlation ..." >&2
    ${PYTHON3} $scriptDir/germlineQC.call_correlation.py -i ${matrix} -o ${outdir} --show_pair_cor

    # Judge PASS/FAIL/swap
    echo "[INFO] qc2-summary - Calculate Pass/Fail/Swap ..." >&2
    ${PYTHON3} $scriptDir/germlineQC.summary.report.py -i ${outdir}/export_corr_matrix.tsv -a ${sampleInfo} -o ${outdir}
fi


##------------ Plot QC-L2 (QC-L2: step-4)
if [[ $pipeline == "qc2-plot" ]]; then
  # plot-heatmap
  # need to add sort by caes function
    ${PYTHON3} $scriptDir/germlineQC.summary.plot.heatmap.py -i ${matrix} -o ${outdir} --cluster
fi




###############################
##    bam QC-L3 (hlaQC)
###############################

##------------ Call HLA genotype (QC-L3: step-1)
if [[ $pipeline == "qc3-hla" ]]; then
  
    sh $scriptDir/hlaQC.bam.call_hla.sh -C ${config} -N ${name} -T ${type} -B ${bam} -O ${outdir}
  
fi


# only re-run optitype
if [[ $pipeline == "qc3-optitype" ]]; then
    sh $scriptDir/hlaQC.bam.call_hla.sh -C ${config} -N ${name} -T ${type} -P optiType -O ${outdir}
fi


##------------ Merge HLA results (QC-L3: step-2)
if [[ $pipeline == "qc3-merge" ]]; then

    ls ${outdir}/*/*/*_result.tsv | while read file; do sample=`echo $file | perl -ne '@arr=split("\/");print $arr[-3]'`; sed '1d' $file | cut -f 2- | perl -pe 's/^/'$sample'\t/'; done | sort -u | perl -pe 's/^/Sample\tA1\tA2\tB1\tB2\tC1\tC2\tReads\tObjective\n/ if $.==1' > ${outdir}/qc3.hla.merged.out

fi


##------------ Summary QC-L3 (QC-L3: step-3)
if [[ $pipeline == "qc3-summary" ]]; then

    echo "[INFO] HLA-QC summary report ..." >&2
    ${PYTHON3} $scriptDir/hlaQC.summary.report.py -i ${sampleInfo} --hla ${matrix} -o ${outdir}

fi



