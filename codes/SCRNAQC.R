#!/usr/bin/env Rscript

## SCRNAQC main script
## Zhe Wang
## zhe@bu.edu
## 2017/06/28


## scRNA-seq QC pipeline
## Calculate metrics of in vitro transcription RNA molecules and 
## PCR amplification products

## Input: directory of demultiplexed (plate specific) SAM files
## Output: QC stats table and plots


## required packages:
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(gtools))
suppressPackageStartupMessages(library(stringdist))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(ggthemes))
suppressPackageStartupMessages(library(scales))
suppressPackageStartupMessages(library(gridExtra))
suppressPackageStartupMessages(library(MASS))
suppressPackageStartupMessages(library(ggseqlogo))
source("SCRNAQC_functions.R")
#source("SCRNAQC_functions_test.R")

## global parameters

# SAM file directory
sam.dir <- "../data/sam/"

# acceptable umi sequence mismatches 
umi.edit <- 1

# maximum acceptable gap between fragments
umi.max.gap <- 40

# maximum acceptable gap for alignment position correction
pos.max.gap <- 5

# output directory
output.dir <- "../res/"

# plate name
platename <- "CS_1017"

#stats.file <- "../res/Alignments_RPI1_UMI_stats.tab"
stats.file <- "../res/sam_UMI_stats.tab"

# palette for ggplot
cpalette <- c("#386cb0","#fdb462","#7fc97f","#ef3b2c","#662506","#0A3708",
              "#a6cee3","#fb9a99","#984ea3","#ffff33","#000000", "#756682")

# run batch QC for one plate
batch.QC.sam(sam.dir, umi.edit, umi.max.gap, pos.max.gap, output.dir)

#pdf(paste0(output.dir, "QC_stats_visualization.pdf"))
#print(visualize.QC.stats(stats.file, platename))
#dev.off()



