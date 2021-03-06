#' @importFrom RANN nn2
NULL


#' @export
sampling_frame <- function(blocklens, TR, startTime=TR/2, precision=.1) {
  ret <- list(blocklens=blocklens,
              TR=TR,
              startTime=startTime,
              precision=precision)
  
  class(ret) <- c("sampling_frame", "list")
  ret
}

#' @export
samples.sampling_frame <- function(x, blocknum=NULL, global=FALSE) {
  if (is.null(blocknum)) {
    blocknum <- seq(1, length(x$blocklens))
  }
  
  if (!global) {
    unlist(lapply(blocknum, function(b) {
      seq(x$startTime, by=x$TR, length.out=x$blocklens[b])
    }))
  } else {
    unlist(lapply(blocknum, function(b) {
      start <- if (b > 1) sum(x$blocklens[1:(b-1)])*x$TR + x$startTime else x$startTime
      seq(start, by=x$TR, length.out=x$blocklens[b])
    }))
  }
}



#' @export
global_onsets.sampling_frame <- function(x, onsets, blockids) {
  
  ids <- rep(1:length(unique(blockids)), table(blockids))
  
  if (max(ids) > length(x$blocklens)) {
    stop("there are more block ids than block lengths, cannot compute global onsets")
  }
  
  sapply(1:length(onsets),function(i) {
    blocknum <- ids[i]
    offset <- (sum(x$blocklens[1:blocknum]) - x$blocklens[blocknum])*x$TR
    if (onsets[i] > x$blocklens[blocknum]*x$TR) {
      NA
    } else {
      onsets[i] + offset
    }
    
  })
}  

#' regressor 
#' 
#' construct a regressor function that can be used to generate a regression fucntion 
#' from a set of onset times and a hemodynamic response function
#' 
#' @param onset the event onsets in seconds
#' @param hrf a hemodynamic response function
#' @param duration duration of events (default is 0)
#' @param amplitude scaling vector (default is 1)
#' @param span the temporal window of the impulse response function (default is 24)
#' @export
regressor <- function(onsets, hrf, duration=0, amplitude=1, span=24) {
  if (length(duration) == 1) {
    duration = rep(duration, length(onsets))
  }
  
  if (length(amplitude) == 1) {
    amplitude = rep(as.vector(amplitude), length(onsets))
  }
  
  keep <- which(amplitude !=0)
  
  ret <- list(onsets=onsets[keep],hrf=hrf, eval=hrf$hrf, duration=duration[keep],amplitude=amplitude[keep],span=span)  
  class(ret) <- c("regressor", "list")
  ret
}


dots <- function(...) {
  eval(substitute(alist(...)))
}

#' evaluate
#' @rdname evaluate
#' @param precision the sampling precision for the hrf. This parameter is passed to \code{evaluate.HRF}
#' @export
evaluate.regressor <- function(x, grid, precision=.1) {
  nb <- nbasis(x)
  dspan <- x$span/median(diff(grid)) 
  outmat <- matrix(0, length(grid), length(x$onsets) * nb)
  
  nidx <- if (length(grid) > 1) {
    apply(RANN::nn2(matrix(grid), matrix(x$onsets), k=2)$nn.idx, 1, min)
  } else {
    apply(RANN::nn2(matrix(grid), matrix(x$onsets), k=1)$nn.idx, 1, min)
  }
  
  valid <- x$onsets >= grid[1] & x$onsets < grid[length(grid)]
  
  if (all(!valid)) {
    message("none of the regressor onsets intersect with sampling 'grid', evalauting to zero at all times.")
    return(outmat)
  }
  
  
  valid.ons <- x$onsets[valid]
  valid.durs <- x$duration[valid]
  valid.amp <- x$amplitude[valid]
  
  nidx <- nidx[valid]

  
  for (i in seq_along(valid.ons)) { 
    grid.idx <- seq(nidx[i], min(nidx[i] + dspan, length(grid)))             
    relOns <- grid[grid.idx] - valid.ons[i]    
    resp <- evaluate(x$hrf, relOns, amplitude=valid.amp[i], duration=valid.durs[i], precision=precision)   
  
    if (nb > 1) {
      start <- (i-1) * nb + 1
      end <- i*nb 
      outmat[grid.idx,start:end] <- resp
    } else {
      outmat[grid.idx, i] <- resp
    }
  }
  
  
  if (length(valid.ons) > 1) {
    if (nb == 1) {
      rowSums(outmat)
    } else {
      do.call(cbind, lapply(1:nb, function(i) {
        rowSums(outmat[,seq(i, by=nb, length.out=length(valid.ons))])
      }))
    }
  } else {
    outmat
  }
}

#' @export
nbasis.regressor <- function(x) nbasis(x$hrf)

#' @export
nbasis.HRF <- function(x) x$nbasis

#' @export
nbasis.hrfspec <- function(x) x$hrf$nbasis

#' @export
onsets.regressor <- function(x) x$onsets

#' @export
durations.regressor <- function(x) x$duration
#' @export
amplitudes.regressor <- function(x) x$amplitude


#' @export
plot.regressor <- function(object, y, samples, add=FALSE, ...) {
  y <- evaluate(object, samples)
  if (add){
    lines(samples, y)
  } else {
    plot(samples, y, type='l', xlab="Time", ylab="Amplitude", ...)
  }
  srange <- range(samples)
  
  for (on in onsets(object)) {
    if (on >= srange[1] && on <= srange[2]) {
      abline(v=on, col=2, lty=2)
    }
  }
  
}

#' @export
print.regressor <- function(object) {
  N <- min(c(6, length(onsets(object))))
  cat(paste("hemodynamic response function:", object$hrf$name))
  cat("\n")
  cat(paste("onsets: ", paste(onsets(object)[1:N], collapse=" "), "..."))
  cat("\n")
  
  durs <- durations(object)
  amps <- amplitudes(object)
  
  if (all(durs == durs[1])) {
    cat(paste("durations: ", durs[1], "for all events"))
  } else {
    cat(paste("durations: ", paste(durs[1:N], collapse=" "), "..."))
  }
  
  cat("\n")
  
  if (all(amps == amps[1])) {
    cat(paste("amplitudes: ", amps[1], "for all events"))
  } else {     
    cat(paste("amplitudes: ", paste(amps[1:N], collapse=" "), "..."))
    
  }
  
  cat("\n")
}

#' check vector is of length 1 or repeated for supplied length
conformLen <- function(val, len) {
  name <- deparse(substitute(val))
  if (length(val) == 1) {
    rep(val, len)
  } else if (length(val) == len) {
    val
  } else {
    stop(paste(name, "must be of length 1 or same length as onsets"))
  }
}


  
                