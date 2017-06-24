# Obsolete stuff

umi.mismatch.correction.2 <- function(samdt, current.ref, umi.window, umi.edit) {
  cat("Now processing", current.ref, "...\n")
  
  # Add UMI info to reference data table
  rdt <- samdt[rname == current.ref,]
  rdt[, c("umi", "inferred_umi") := 
        tstrsplit(qname, ":", fixed=TRUE, 
                  keep=length(tstrsplit(qname, ":", fixed=TRUE)))]
  
  # Correct UMIs with sequencing errors by looking at UMIs in surrounding region
  
  # get all alignment positions
  unique.pos <- sort(unique(rdt$position))
  
  for (i in unique.pos) {
    # Get range data table for position and surrounding window
    # get all alignment positions ranging between i-umi.window to i+umi.window
    rdt.sub <- rdt[position == i, ]
    rdt.flank.5p <- rdt[position >= (i-umi.window) & position <= (i-1), ]
    rdt.flank.3p <- rdt[position >= (i+1) & position <= (i+umi.window), ]
    rdt.flank <- rbindlist(list(rdt.flank.5p, rdt.flank.3p), use.names=F, fill=F, idcol=F)
    
    # Get all unique UMIs in the region
    all.umi.count <- sort(table(c(rdt.sub[,umi], rdt.flank[,umi])))
    
    
    # Align UMIs to all other UMIs. Assign UMIs with lower counts to 
    # matching UMI with higher counts
    
    if (length(all.umi.count) > 1) {
      sdm <- stringdistmatrix(names(all.umi.count), names(all.umi.count))
      diag(sdm) <- 100
      rownames(sdm) <- names(all.umi.count)
      colnames(sdm) <- names(all.umi.count)
      
      position.umi.count <- sort(table(rdt.sub$umi))
      
      # for umi k at position i
      for (k in names(position.umi.count)) {
        
        # Get the min edit distance for that UMI
        sdm.min.edit <- min(sdm[k,])
        
        if (sdm.min.edit <= umi.edit) {
          # Get the index of the edit distance less than umi.edit with the highest count.
          # rownames and colnames of sdm (all.umi.count) is sorted by read counts
          # increasingly
          sdm.edit.ind <- max(which(sdm[k,] <= umi.edit))
          
          # correct current umi k at position i
          if (which(rownames(sdm) == k) < sdm.edit.ind) {
            rdt[umi == k & position == i, inferred_umi := colnames(sdm)[sdm.edit.ind]]
          }
        }
      }
    }
  }
  return (rdt)
}