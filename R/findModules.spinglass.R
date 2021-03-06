# Function to get modules from network adjacency matrix
findModules.spinglass <- function(adj, nperm = 10, min.module.size = 30){
  # Input
  #      adj = n x n upper triangular adjacency in the matrix class format
  #      nperm = number of permutation on the gene ordering 
  #      min.module.size = integer between 1 and n genes 
  
  # Output
  #      geneModules = n x 3 dimensional data frame with column names as Gene.ID, moduleNumber, and moduleLabel
  
  # Error functions
  if(class(adj) != "matrix")
    stop('Adjacency matrix should be of class matrix')
  
  if(dim(adj)[1] != dim(adj)[2])
    stop('Adjacency matrix should be symmetric')
  
  if(!all(adj[lower.tri(adj)] == 0))
    stop('Adjacency matrix should be upper triangular')
  
  # Make adjacency matrix symmetric
  adj = adj + t(adj)
  adj[diag(adj)] = 0
  
  # Compute modules by permuting the labels nperm times
  all.modules = plyr::llply(1:nperm, .fun= function(i, adj, path, min.module.size){
    # Permute gene ordering
    ind = sample(1:dim(adj)[1], dim(adj)[1], replace = FALSE)
    adj1 = adj[ind,ind]
    
    # Find modules 
    mod = findModules.spinglass.once(adj1, min.module.size)
    
    # Compute local and global modularity
    adj1[lower.tri(adj1)] = 0
    Q = compute.Modularity(adj1, mod)
    Qds = compute.ModularityDensity(adj1, mod)
    
    return(list(mod = mod, Q = Q, Qds = Qds))
  }, adj, path, min.module.size)
  
  # Find the best module based on Q and Qds
  tmp = plyr::ldply(all.modules, function(x){
    data.frame(Q = x$Q, Qds = x$Qds)
  }) %>%
    dplyr::mutate(r = base::rank(Q)+base::rank(Qds))
  ind = which.max(tmp$r)
  
  mod = all.modules[[ind]]$mod
  
  return(mod)
}

findModules.spinglass.once <- function(adj, min.module.size){
  # Convert lsparseNetwork to igraph graph object
  g = igraph::graph.adjacency(adj, mode = 'undirected', weighted = T, diag = F)
  
  # Find connected components
  scc = igraph::components(g)
  
  # Find modules for each component using spinglass algorithm (http://arxiv.org/abs/cond-mat/0603718)
  mod = lapply(unique(scc$membership), function(x, g, scc){
    sg = igraph::induced_subgraph(g, which(scc$membership == x))
    if (sum(scc$membership == x) == 1){
      geneModules = data.frame(Gene.ID = igraph::V(g)$name[scc$membership == x],
                               moduleNumber = 0)
    } else{
      mod = igraph::cluster_spinglass(sg)
      geneModules = data.frame(Gene.ID = igraph::V(sg)$name,
                               moduleNumber = unclass(igraph::membership(mod)))
    }
  }, g, scc)
  
  mod.sz = c(0, cumsum(sapply(mod, function(x) max(x$moduleNumber))))
  mod.sz = mod.sz[1:(length(mod.sz) -1)]
  geneModules = mapply(function(x,y){
    x$moduleNumber = x$moduleNumber + y
    return(x)
  }, mod, mod.sz, SIMPLIFY = F) %>%
    rbindlist(use.names = T, fill = T)
  
  # Rename modules with size less than min module size to 0
  filteredModules = geneModules %>% 
    dplyr::group_by(moduleNumber) %>%
    dplyr::summarise(counts = length(unique(Gene.ID))) %>%
    dplyr::filter(counts >= min.module.size)
  geneModules$moduleNumber[!(geneModules$moduleNumber %in% filteredModules$moduleNumber)] = 0
  
  # Change cluster number to color labels
  geneModules$moduleLabel = WGCNA::labels2colors(geneModules$moduleNumber)
  
  return(geneModules)
}