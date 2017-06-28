#!/usr/bin/env Rscript

# SCRNAQC functions
# Zhe Wang
# 20170628



# ggplot publication theme
# adapted from Koundinya Desiraju
# https://rpubs.com/Koundy/71792
theme_Publication <- function(base_size=12, base_family="sans") {
  (ggthemes::theme_foundation(base_size=base_size, base_family=base_family)
   + ggplot2::theme(plot.title = element_text(face = "bold",
                                              size = rel(1), hjust = 0.5),
                    text = element_text(),
                    panel.background = element_rect(colour = NA),
                    plot.background = element_rect(colour = NA),
                    panel.border = element_rect(colour = NA),
                    axis.title = element_text(face = "bold",size = rel(1)),
                    axis.title.y = element_text(angle=90,vjust =2),
                    axis.title.x = element_text(vjust = -0.2),
                    axis.text = element_text(), 
                    axis.line = element_line(colour="black"),
                    axis.ticks = element_line(),
                    panel.grid.major = element_line(colour="#f0f0f0"),
                    panel.grid.minor = element_blank(),
                    legend.key = element_rect(colour = NA),
                    legend.position = "right",
                    legend.direction = "vertical",
                    legend.key.size= unit(0.5, "cm"),
                    legend.margin = margin(0),
                    legend.title = element_text(face="bold"),
                    plot.margin=unit(c(10,5,5,5),"mm"),
                    strip.background=element_rect(colour="#f0f0f0",fill="#f0f0f0"),
                    strip.text = element_text(face="bold")
   ))
  
}


scale_fill_Publication <- function(...){
  ggplot2::discrete_scale("fill","Publication",manual_pal(values = cpalette), ...)
  
}


scale_colour_Publication <- function(...){
  ggplot2::discrete_scale("colour","Publication",manual_pal(values = cpalette), ...)
  
}


# read a sam file
# return a data table of the file
read.sam <- function(samfile){
  # get the maximum number of columns per row
  maxncol <- max(count.fields(samfile, sep="\t", quote="", comment.char=""))
  
  # read in SAM file
  sam <- read.table(samfile, 
                    sep="\t",
                    quote="",
                    fill=T, 
                    header=F,
                    stringsAsFactors=F,
                    na.strings=NULL,
                    comment.char="@",
                    col.names=1:maxncol)
  
  colnames(sam)[1:11] <- c("qname", "flag", "rname", "position", "mapq", "cigar",
                           "rnext", "pnext", "tlen", "seq", "qual")
  
  # convert to data.table object
  samdt <- data.table(sam, check.names=T)
  return (samdt)
}


# correct umi mismatch
umi.mismatch.correction <- function(samdt, current.ref, umi.max.gap, umi.edit) {
  # Add inferred_umi info to reference data table
  rdt <- samdt[rname == current.ref,]
  rdt[, c("umi", "inferred_umi") := 
        tstrsplit(qname, ":", fixed=TRUE, 
                  keep=length(tstrsplit(qname, ":", fixed=TRUE)))]
  
  # Correct UMIs with sequencing errors by looking at UMIs in surrounding region
  
  # get all alignment positions
  unique.pos <- sort(unique(rdt$position))
  
  unique.pos.list <- get.adj.pos.list(unique.pos, umi.max.gap)
  
  # for each IVT fragment
  for (i in unique.pos.list) {
    all.umi.count <- sort(table(c(rdt[position %in% i, umi])))
    
    if (length(all.umi.count) > 1) {
      # temporary solution with only one iteration
      # need a recursive solution for some special cases
      sdm <- stringdistmatrix(names(all.umi.count), names(all.umi.count))
      diag(sdm) <- 100
      rownames(sdm) <- names(all.umi.count)
      colnames(sdm) <- names(all.umi.count)
      
      for (j in colnames(sdm)) {
        if (min(sdm[j,]) <= umi.edit) {
          sdm.edit.ind <- max(which(sdm[j,] <= umi.edit))
          # correct current umi j within position group i
          if (which(rownames(sdm) == j) < sdm.edit.ind) {
            rdt[umi == j & position %in% i, inferred_umi := colnames(sdm)[sdm.edit.ind]]
          }
        }
      }
    }
  }
  return (rdt)
}


get.adjacent.unique.pos <- function(unique.pos, gap) {
  adjs <- diff(unique.pos) <= gap
  ind <- which(adjs == T)
  plusone <- ind + 1
  return (unique.pos[sort(union(ind, plusone))])
}


get.adj.pos.list <- function(unique.pos, gap){
  adjs <- diff(unique.pos) <= gap
  n <- sum(adjs == F) + 1
  res <- vector("list", n) 
  
  i <- 1 # Alignment position group
  j <- 1 # index of position
  while (i <= n) {
    if (j > length(adjs)) {
      res[[i]] <- c(res[[i]], unique.pos[j])
      i <- i + 1
    } else if (adjs[j] == T) {
      res[[i]] <- c(res[[i]], unique.pos[j])
    } else if (adjs[j] == F) {
      res[[i]] <- c(res[[i]], unique.pos[j])
      i <- i + 1
    } 
    j <- j + 1
  }
  return (res)
}


get.position.with.most.reads <- function(rdt.sub) {
  res <- sort(table(rdt.sub[,position]), decreasing = T)
  return (sort(as.numeric(names(res[which(res == res[1])])))[1])
}


alignment.position.correction <- function(rdt, pos.max.gap) {
  rdt[,inferred_pos := position]
  unique.pos <- sort(unique(rdt$position))
  
  # consider only adjacent positions with gap <= pos.max.gap
  adj.unique.pos <- get.adjacent.unique.pos(unique.pos, pos.max.gap)
  pos.group <- get.adj.pos.list(adj.unique.pos, pos.max.gap)
  # correct alignment position error
  for (i in pos.group) {
    rdt.sub <- rdt[position %in% i, ]
    unique.umi.count <- table(rdt.sub$inferred_umi)
    
    for (j in 1:length(unique.umi.count)) { 
      rdt.sub.sub <- rdt.sub[inferred_umi == names(unique.umi.count)[j], ]
      rdt[position %in% i & inferred_umi == names(unique.umi.count)[j], 
          inferred_pos := get.position.with.most.reads(rdt.sub.sub)]
    }
  }
  return (rdt)
}


get.pcr.duplicates <- function(rdt) {
  reads <- rdt[,.(inferred_umi, inferred_pos, rname)]
  unique.fragments <- unique(reads[order(reads$inferred_pos)])
  for (i in 1:nrow(unique.fragments)) {
    frag <- unique.fragments[i,]
    n <- nrow(rdt[inferred_umi==frag[[1]] & inferred_pos==frag[[2]],])
    unique.fragments[i, num := n]
  }
  return (unique.fragments)
}


num.amplified.frag <- function(num.pcr.products.table) {
  return (sum(num.pcr.products.table$num >= 2))
}


plot.num.frag.per.umi <- function(umi.table, title) {
  dt <- data.table(umi.table)
  
  breaks <- pretty(range(dt$N), n = nclass.scott(dt$N), min.n = 1)
  bwidth <- diff(breaks)[1]
  
  g <- ggplot(dt, aes(N)) + 
    geom_histogram(aes(y=..count../sum(..count..)),
                   binwidth=bwidth, 
                   closed="left", boundary=0, fill="white", col="black") +
    theme_Publication() +
    ggtitle(title) +
    xlab("Number of fragments per UMI") + ylab("UMI fraction")
  return (g)
}


plot.base.fraction <- function(res.table, umi.length) {
  # Base percentage of UMIs
  base.matrix <- c()
  for(i in 1:umi.length) {
    # consider all fragments
    
    base.matrix <- rbindlist(list(base.matrix,
                                  data.table(t(data.frame(table(substr(unique(res.table[,umi]),
                                                                       i, i)), row.names=1)))),
                             use.names=T, fill=F, idcol=F)
  }
  
  base.matrix.frac <- base.matrix / length(unique(res.table[,umi]))
  base.matrix.frac$ind <- 1:nrow(base.matrix.frac)
  base.matrix.frac.melt <- melt(base.matrix.frac, id.vars="ind")
  
  g1 <- ggplot(base.matrix.frac.melt, aes(ind, value, fill=variable)) +
    geom_bar(stat = "identity") + theme_Publication() + scale_fill_Publication() +
    theme(legend.title=element_blank()) + ggtitle("Original UMIs") +
    xlab("UMI position") + ylab("Percent")
  
  
  base.inferred.matrix <- c()
  for(i in 1:umi.length) {
    base.inferred.matrix <- 
      rbindlist(list(base.inferred.matrix, 
                     data.table(t(data.frame(table(substr(unique(res.table[,inferred_umi]),
                                                          i, i)), row.names=1)))),
                use.names=T, fill=F, idcol=F)
  }
  
  base.inferred.matrix.frac <- base.inferred.matrix / length(unique(res.table[,inferred_umi]))
  
  base.inferred.matrix.frac$ind <- 1:nrow(base.inferred.matrix.frac)
  
  base.inferred.matrix.frac.melt <- melt(base.inferred.matrix.frac, id.vars="ind")
  
  g2 <- ggplot(base.inferred.matrix.frac.melt, aes(ind, value, fill=variable)) +
    geom_bar(stat = "identity") + theme_Publication() + scale_fill_Publication() +
    theme(legend.title=element_blank()) + ggtitle("Inferred UMIs") +
    xlab("UMI position") + ylab("Percent")
  return (list(g1,g2))
}


plot.num.products.per.fragment <- function(pcr.products.dt) {
  # histogram of # products per fragment
  breaks <- pretty(range(pcr.products.dt$num),
                   n = nclass.scott(pcr.products.dt$num), min.n = 1)
  bwidth <- diff(breaks)[1]
  
  g <- ggplot(pcr.products.dt, aes(num)) +
    geom_histogram(aes(y=..count../sum(..count..)),
                   binwidth=bwidth, closed="left", boundary=0,
                   fill="white", col="black") + theme_Publication() +
    ggtitle("Number of PCR products per IVT fragment") +
    xlab("Number of PCR products") + ylab("Fraction")
  return (g)
}


plot.num.products.per.fragment <- function(pcr.products.dt) {
  # histogram of # products per fragment
  pcr.products.dt[,num := log2(num)]
  breaks <- pretty(range(pcr.products.dt$num),
                   n = nclass.scott(pcr.products.dt$num), min.n = 1)
  bwidth <- diff(breaks)[1]
  
  g <- ggplot(pcr.products.dt, aes(num)) +
    geom_histogram(aes(y=..count../sum(..count..)),
                   binwidth=bwidth, closed="left", boundary=0,
                   fill="white", col="black") +
    ggtitle("Number of PCR products per IVT fragment") +
    xlab(expression(bold(Log[2](Number~of~PCR~products)))) +
    ylab("Fraction") + theme_Publication()
  
  return (g)
}


plot.stats.sam <- function(res.table, num.pcr.products.table, umi.length, fname) {
  # calculate fragment number
  ori.fragments <- unique(res.table[,.(umi, position)])
  inf.fragments <- unique(res.table[,.(inferred_umi, inferred_pos)])
  
  # Calculate relative abundance of UMIs
  umi.table <- table(ori.fragments$umi)
  umi.inferred.table <- table(inf.fragments$inferred_umi)
  
  nc = 2
  
  g1 <- plot.num.frag.per.umi(umi.table, "Original UMIs")
  
  g2 <- plot.num.frag.per.umi(umi.inferred.table, "Inferred UMIs")
  
  g3.g4 <- plot.base.fraction(res.table, umi.length)
  
  g5 <- plot.num.products.per.fragment(num.pcr.products.table)
  
  return (gridExtra::arrangeGrob(grobs = list(g1,g2,g3.g4[[1]], g3.g4[[2]], g5), ncol = nc, 
                                 top = grid::textGrob(paste0(fname,".sam"))))
}


QC.sam <- function(sam, umi.edit, umi.max.gap, pos.max.gap, output.dir) {
  # read in SAM file
  samdt <- read.sam(sam)
  fname <- strsplit(last(strsplit(sam, split = "/")[[1]]), split = "\\.")[[1]][1]
  umi.length <- as.numeric(nchar(samdt[1,tstrsplit(qname, ":", fixed=TRUE,
                                                   keep=length(tstrsplit(qname, ":", fixed=TRUE)))]))
  # output file names
  umi.stats <- paste0(output.dir, fname, "_UMI_stats.tab")
  
  umi.qc <- paste0(output.dir, fname, "_UMI_QC_plots.pdf")
  
  
  # get reference sequence names
  chr <- mixedsort(setdiff(unique(samdt[,rname]), "*"))
  res.table <- list()
  num.pcr.products.table <- list()
  
  
  # for each reference sequence name (chr)
  for (current.ref in chr) {
    # correct umi mismatch
    rdt <- umi.mismatch.correction(samdt, current.ref, umi.max.gap, umi.edit)
    # correct alignment position error
    rdt <- alignment.position.correction(rdt, pos.max.gap)
    
    
    # Now that UMIs have been fixed, go through each position and pick one read to
    # represent each UMI. Positions with more reads with that UMI and that are more 5'
    # are given higher priority. One read randomly selected to be the non-duplicate
    
    # Metrics to report:
    # Number of PCR priducts per IVT fragment
    num.pcr.products.table <- rbindlist(list(num.pcr.products.table, get.pcr.duplicates(rdt)),
                                        use.names=F, fill=F, idcol=F)
    
    # Distribution of average UMI edit distance of all reads
    
    
    res.table <- rbindlist(list(res.table, 
                                rdt[,c("rname", "position","inferred_pos",
                                       "umi", "inferred_umi")]),
                           use.names=F, fill=F, idcol=F)
  }
  
  # Number of reads with mismatches in UMI
  num.umi.mismatch <- nrow(res.table[umi != inferred_umi,])
  
  # Number of reads with shifts in alignment position
  num.pos.shift <- nrow(res.table[position != inferred_pos,])
  
  
  stats.label <- c("filename",
                   "num.aligned.reads",
                   "num.unique.fragments",
                   "percent.unique.fragments",
                   "num.unique.UMI",
                   "num.unique.UMI.corrected",
                   "num.reads.UMI.mismatch",
                   "percent.reads.UMI.mismatch",
                   "num.reads.pos.shift",
                   "percent.reads.pos.shift",
                   "avg.products.per.fragment",
                   "median.products.per.fragment",
                   "num.amplified.fragments",
                   "percent.amplified.fragments")
  
  stats <- c(fname,
             nrow(res.table), 
             nrow(num.pcr.products.table),
             nrow(num.pcr.products.table)/nrow(res.table),
             length(unique(res.table$umi)), 
             length(unique(res.table$inferred_umi)),
             num.umi.mismatch,
             num.umi.mismatch/nrow(res.table),
             num.pos.shift,
             num.pos.shift/nrow(res.table),
             mean(num.pcr.products.table$num),
             median(num.pcr.products.table$num),
             num.amplified.frag(num.pcr.products.table),
             num.amplified.frag(num.pcr.products.table)/nrow(num.pcr.products.table))
  
  dt.stats <- data.table(matrix(stats, ncol=length(stats.label), nrow=1))
  colnames(dt.stats) <- stats.label
  
  grob <- plot.stats.sam(res.table, num.pcr.products.table, umi.length, fname)
  return (list(dt.stats, grob))
}


# batch QC for one plate
batch.QC.sam <- function(sam.dir, umi.edit = 1, umi.max.gap = 20,
                         pos.max.gap = 3, output.dir = paste0(sam.dir,"SCRNAQC_res/")) {
  # Batch QC for one plate
  files <- list.files(sam.dir, full.names = T)
  stats.sam <- vector(length(files), mode="list")
  plots.sam <- vector(length(files), mode="list")
  
  for (i in 1:length(files)) {
    cat("Now processing", files[i], "...\n")
    sam.res <- QC.sam(files[i], umi.edit, umi.max.gap, pos.max.gap, output.dir)
    stats.sam[[i]] <- sam.res[[1]]
    plots.sam[[i]] <- sam.res[[2]]
  }
  
  stats.res <- rbindlist(stats.sam, use.names=F, fill=F, idcol=F)
  
  fwrite(stats.res, paste0(output.dir, last(strsplit(sam.dir, split="/")[[1]]),
                           "_UMI_stats.tab"), sep="\t",
         quote=F, row.names=F, col.names=T)
  
  pdf(paste0(output.dir, last(strsplit(sam.dir, split="/")[[1]]), ".pdf"))
  for (i in 1:length(files)) {
    grid.arrange(plots.sam[[i]])
  }
  graphics.off()
}