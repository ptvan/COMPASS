##' Plot a pair of COMPASSResults
##'
##' This function can be used to visualize the mean probability of response --
##' that is, the probability that there is a difference in response between
##' samples subjected to the 'treatment' condition, and samples subjected
##' to the 'control' condition.
##'
##' @param x An object of class \code{COMPASSResult}.
##' @param y An object of class \code{COMPASSResult}.
##' @param row_annotation A vector of names, pulled from the metadata, to be
##'   used for row annotation.
##' @param threshold A numeric threshold for filtering under-expressed
##'   categories. Any categories with mean score < \code{threshold} are
##'   removed.
##' @param minimum_dof The minimum degree of functionality for the categories
##'   to be plotted.
##' @param maximum_dof The maximum degree of functionality for the categories
##'   to be plotted.
##' @param must_express A character vector of markers that should be included
##'   in each subset plotted. For example, \code{must_express=c("TNFa & IFNg")}
##'   says we include only subsets that are positive for both
##'   \code{TNFa} or \code{IFNg}, while \code{must_express=c("TNFa", "IFNg")}
##'   says we should keep subsets which are positive for either \code{TNFa} or
##'   \code{IFNg}.
##' @param subset An \R expression, evaluated within the metadata, used to
##'   determine which individuals should be kept.
##' @param palette The colour palette to be used.
##' @param show_rownames Boolean; if \code{TRUE} we display row names (ie,
##'   the individual ids).
##' @param show_colnames Boolean; if \code{TRUE} we display column names
##'   (ie, the column name associated with a cytokine; typically not needed)
##' @param ... Optional arguments passed to \code{pheatmap}.
##' @importFrom scales div_gradient_pal
##' @return The plot as a \code{grid} object (\code{grob}). It can be redrawn
##' with e.g. \code{grid::grid.draw()}.
##' @export
plot2 <- function(x, y, subset,
  threshold=0.01,
  minimum_dof=1,
  maximum_dof=Inf,
  must_express=NULL,
  row_annotation=NULL,
  palette=NA,
  show_rownames=FALSE,
  show_colnames=FALSE,
  ...) {

  call <- match.call()

  if (is.symbol(call$subset)) {
    subset <- eval(call$subset, envir=parent.frame())
  } else if (is.language(call$subset)) {
    subset <- call$subset
  }

  nc_x <- ncol(x$fit$gamma)
  M_x <- x$fit$mean_gamma[, -nc_x, drop=FALSE]

  nc_y <- ncol(y$fit$gamma)
  M_y <- y$fit$mean_gamma[, -nc_y, drop=FALSE]

  ## make sure the row order is the same
  M_x <- M_x[ order(rownames(M_x)), , drop=FALSE ]
  M_y <- M_y[ order(rownames(M_y)), , drop=FALSE ]

  ## find the common PTIDs, incase the fits have different ones
  if (!all( (rownames(M_x)==rownames(M_y)))) {
    warning("Not all individuals are shared in common between the two ",
      "fit objects; some will be dropped.")
    common <- intersect( rownames(M_x), rownames(M_y) )
    M_x <- M_x[ rownames(M_x) %in% common, , drop=FALSE]
    M_y <- M_y[ rownames(M_y) %in% common, , drop=FALSE]
    meta_x <- x$data$meta[ c(x$data$individual_id, row_annotation) ]
    meta_y <- y$data$meta[ c(y$data$individual_id, row_annotation) ]
    meta <- meta_x[ meta_x[[x$data$individual_id]] %in% common, ]
  } else {
    meta <- x$data$meta[ c(x$data$individual_id, row_annotation) ]
  }

  ## generate the row annotations if needed
  if (!is.null(row_annotation)) {
    rowann <- data.frame(.id=rownames(M_x))
    rowann <- merge(
      rowann,
      meta[c(x$data$individual_id, row_annotation)],
      by.x=".id",
      by.y=x$data$individual_id
    )
    rowann <- rowann[!duplicated(rowann[[".id"]]), ]
    rownames(rowann) <- rowann[[".id"]]
    rowann <- rowann[-c(which(names(rowann)==".id"))]

    ## make sure M, rowann names match up
    rowann <- rowann[ match(rownames(M_x), rownames(rowann)), , drop=FALSE ]
  }

  ## get the common categories
  cats <- unique( rbind(
    x$fit$categories,
    y$fit$categories
  ) )

  ## remove the null category
  cats <- cats[ rowSums(cats)!=0, ]

  cats <- data.frame(cats)
  cats <- cats[,1:(ncol(cats)-1)]
  cats <- as.data.frame( lapply(cats, function(x) {
    factor(x, levels=c(0, 1))
  }))

  cats_str <- apply(cats, 1, function(x) {
    paste0(x, collapse="")
  })

  ## for all of the categories not in common between M_x, M_y,
  ## set them to zero
  M_x <- as.data.frame(M_x)
  M_y <- as.data.frame(M_y)
  for (cat in cats_str) {
    if (!(cat %in% names(M_x))) {
      M_x[[cat]] <- 0
    }
    if (!(cat %in% names(M_y))) {
      M_y[[cat]] <- 0
    }
  }

  ## reorder M_x, M_y
  M_x <- M_x[, order(colnames(M_x)), drop=FALSE]
  M_y <- M_y[, order(colnames(M_y)), drop=FALSE]
  cats<-cats[order(cats_str),]
  cats_str<-cats_str[order(cats_str)]
  if (!all(colnames(M_x) == colnames(M_y))) {
    stop("Internal error: could not match categories between the matrices ",
      "from 'x' and 'y'")
  }

  ## finally, merge the two
  M <- M_x - M_y

  ## after the merging, try to filter based on express markers
  ## Keep only markers that were specified in the 'must_express'
  ## argument
  if (!is.null(must_express)) {

    cats_int <- cats
    cats_int[] <- lapply(cats, function(x) as.integer(as.character(x)))

    ind <- Reduce(union, lapply(must_express, function(x) {
      eval( parse(text=x), envir=cats_int )
    }))

    cats <- cats[ind, ]
    M <- M[, ind]

  }

  ## compute dof from the colnames of M
  dof <- sapply( strsplit( colnames(M), "", fixed=TRUE ), function(x) {
    sum( as.integer(x) )
  })

  ## remove under-expressed categories
  m <- apply(M, 2, mean)
  keep <- m > threshold | m < -threshold
  M <- M[, keep, drop=FALSE]
  cats <- cats[keep, , drop=FALSE]
  keep <- keep[ names(keep) %in% colnames(M) ]

  ## handle subsetting
  if (!missing(subset)) {
    keep_indiv <- unique(x$data$meta[[x$data$individual_id]][eval(subset, envir=x$data$meta)])
    M <- M[ rownames(M) %in% keep_indiv, , drop=FALSE]
    if (!is.null(row_annotation)) {
      rowann <- rowann[ rownames(rowann) %in% keep_indiv, , drop=FALSE]
    }
    M_x <- M_x[ rownames(M_x) %in% keep_indiv, , drop=FALSE]
    M_y <- M_y[ rownames(M_y) %in% keep_indiv, , drop=FALSE]
  }

  ## reorder the data
  if (!is.null(row_annotation)) {
    o <- do.call(order, as.list(rowann[row_annotation]))
  } else {
    o <- 1:nrow(M)
    rowann <- NA
  }

  .scale<-function(x){
    x/max(x)
  }

  cr<-colorRamp(RColorBrewer::brewer.pal(name="RdYlBu",n=5),interpolate="linear")
  #rgbvals<-apply(matrix(c(1,2,3,4,5,6),ncol=2,byrow=TRUE),1,function(x)as.numeric(as.hexmode(substr(as.hexmode(gsub("#","",RColorBrewer::brewer.pal(name="RdYlBu",n=3))),x[1],x[2]))))
  #rgbvals<-prop.table(rgbvals,2)

  #outer(rgbvals[,1],as.vector(as.matrix(M_x)))
  pal<-log1p(as.vector(as.matrix(M_x)))-log1p(as.vector(as.matrix(M_y)))
  pal<-(pal+max(pal))/diff(range(pal))

  ## force negatives to zero
  pal[pal < 0] <- 0

  palette<-t(rgb2hsv(t(cr(pal))))
  #palette<-cr(pal)
#  palette["s",]<-.scale(asinh(1*as.vector(as.matrix(M_x))+as.vector(as.matrix(M_y))))
  alpha<-sqrt(as.vector(as.matrix(M_x))^2+as.vector(as.matrix(M_y))^2)/sqrt(2)

  #palette["v",]<-1
  palette<-hsv(h=palette[,1],s=palette[,2],v=palette[,3],alpha=alpha)
  #palette<-rgb(palette,alpha=alpha*255,maxColor=255)

  m<-matrix(palette,nrow=nrow(M_x),ncol=ncol(M_x))
  colnames(m)<-colnames(M_x)
  rownames(m)<-rownames(M_x)
  m<-m[, names(keep), drop=FALSE]

  rownames(cats) <- colnames(m)

  ## do some final dof subsetting
  dof <- sapply(strsplit(colnames(m), "", fixed=TRUE), function(x)
    sum(x == "1")
  )

  keep <- dof >= minimum_dof & dof <= maximum_dof
  m <- m[, keep, drop=FALSE]
  cats <- cats[keep, ]

  pheatmap(m[o, , drop=FALSE],
    color=palette,
    show_rownames=show_rownames,
    show_colnames=show_colnames,
    row_annotation=rowann,
    cluster_rows=FALSE,
    cluster_cols=FALSE,
    cytokine_annotation=cats,
    polar=TRUE,
    ...
  )

}
