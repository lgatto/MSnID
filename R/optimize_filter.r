# methods and functions for handling filter optimization.

.get_num_pep_for_fdr <- function(filterThresholds,
                                    msmsdata,
                                    filter,
                                    fdr.max,
                                    ...)
{
    filter <- update(filter, filterThresholds)
    # level should get here through ... (ellipsis)
    x <- evaluate_filter(msmsdata, filter, ...)
    if(is.nan(x[['fdr']]) || x[['fdr']] > fdr.max){
        # 0 is bad because optimization does not move
        return(rnorm(1,sd=0.001))
    }else{
        return(x[['n']])
    }
}


.construct_optimization_grid <- function(filterObj, msnidObj, n.iter)
{
    n.iter.per.param <- round(n.iter^(1/length(filterObj))) - 1
    probs <- seq(0, 1, 1/n.iter.per.param)
    eg <- expand.grid(lapply(names(filterObj),
                                function(arg)
                                    quantile(msnidObj[[arg]],
                                                probs, na.rm=TRUE)))
    colnames(eg) <- names(filterObj)
    return(eg)
}


.optimize_filter.grid <- function(filterObj, msnidObj, fdr.max, level, n.iter)
{
    par.grid <- .construct_optimization_grid(filterObj, msnidObj, n.iter)
    evaluations <- apply(X=par.grid,
                            MARGIN=1,
                            FUN=.get_num_pep_for_fdr,
                                msnidObj,
                                filterObj,
                                fdr.max,
                                level)
    optim.pars <- par.grid[which.max(evaluations),]
    newFilter <- update(filterObj, as.numeric(optim.pars))
    return(newFilter)
}


.optimize_filter.grid.mclapply <- function(filterObj, msnidObj,
                                            fdr.max, level, n.iter)
{
    par.grid <- .construct_optimization_grid(filterObj, msnidObj, n.iter)
    evaluations <- mclapply(seq_len(nrow(par.grid)),
                            function(i){
                                .get_num_pep_for_fdr(par.grid[i,],
                                                        msnidObj,
                                                        filterObj,
                                                        fdr.max,
                                                        level)},
                            mc.cores=detectCores())
    evaluations <- unlist(evaluations)
    optim.pars <- par.grid[which.max(evaluations),]
    newFilter <- update(filterObj, as.numeric(optim.pars))
    return(newFilter)
}


setMethod("optimize_filter",
            signature(filterObj="MSnIDFilter", msnidObj="MSnID"),
            definition=function(filterObj, msnidObj, fdr.max,
                                   method, level, n.iter)
            {
                .optimize_filter.memoized(filterObj, msnidObj,
                                            fdr.max, method, level, n.iter)
            }
)



.optimize_filter <- function(filterObj, msnidObj,
                               fdr.max, method, level, n.iter)
{
    method <- match.arg(method, choices=c("Grid", "Nelder-Mead", "SANN"))
    level <- match.arg(level, choices=c("PSM", "peptide", "accession"))
    #
    # subset msnidObj to only relevant columns
    if(level == "PSM"){
       msnidObj@psms <-
           msnidObj@psms[,c("isDecoy", names(filterObj)), with=FALSE]
    }else{
       msnidObj@psms <-
           msnidObj@psms[,c("isDecoy", level, names(filterObj)), with=FALSE]
       # substitute Peptide and or Accession with integers
       msnidObj@psms[[level]] <- as.integer(as.factor(msnidObj@psms[[level]]))
    }
    #
    if(method == "Grid"){
        if(.Platform$OS.type == "unix"){
            optimFilter <-
                .optimize_filter.grid.mclapply(filterObj, msnidObj,
                                                fdr.max, level, n.iter)
        }else{
            # yet to implement effective parallelization on Windows
            optimFilter <-
                .optimize_filter.grid(filterObj, msnidObj,
                                        fdr.max, level, n.iter)
        }
    }
    if(method %in% c("Nelder-Mead", "SANN")){
        optim.out <- optim(par=as.numeric(filterObj),
                            fn = .get_num_pep_for_fdr,
                            msmsdata = msnidObj,
                            filter = filterObj,
                            fdr.max = fdr.max,
                            level = level,
                            method = method,
                            control=list(fnscale=-1, maxit=n.iter))
        optimFilter <- update(filterObj, as.numeric(optim.out$par))
    }
    return(optimFilter)
}

# todo: make memoization optional
.optimize_filter.memoized <- addMemoization(.optimize_filter)

