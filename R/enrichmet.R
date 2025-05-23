#' ENRICHMET: R package for Quick and Easy Pathway Analysis in Metabolomics
#'
#' This function performs pathway enrichment analysis using Fisher’s exact test, computes betweenness centrality for metabolites,
#' and performs Metabolite Set Enrichment Analysis (MetSEA). It also generates plots for pathway enrichment, MetSEA, and relative betweenness centrality (RBC).
#'
#' @param inputMetabolites A vector of metabolites for which pathway enrichment and centrality analysis are to be performed.
#' @param PathwayVsMetabolites A data frame containing pathways and their associated metabolites.
#' @param example_data A data frame containing example data for GSEA. This should include columns such as "met_id", "pval", and "log2fc".
#' @param top_n An integer specifying the number of top pathways to include in the pathway enrichment results (default is 100).
#' @param p_value_cutoff A numeric value for adjusting the p-value threshold for filtering significant pathways (default is 1).
#'
#' @return A list containing three ggplot objects: pathway enrichment plot, GSEA plot, and RBC plot.
#' @examples
#' ## ** Examples
#'
#' # Generate example data with at least n=50 metabolites
#' set.seed(1234)
#'
#' # Create 50 unique metabolites
#' inputMetabolites <- paste0("M", 1:20)
#'
#' # Generate 10 pathways with random metabolites assigned
#' pathway_names <- paste0("Pathway", 1:50)
#' PathwayVsMetabolites <- data.frame(
#'   Pathway = rep(pathway_names, each = 1),
#'   Metabolites = sapply(1:50, function(x) paste(sample(inputMetabolites, sample(5:15, 1)), collapse = ","))
#' )
#'
#' # Add new pathway entries (Pathway101 and Pathway102)
#' new_rows <- data.frame(
#'   Pathway = c("Pathway101", "Pathway102", "Pathway103", "Pathway104", "pathway105"),
#'   Metabolites = c(
#'     "M12,M13,M14,M15,M16,M1,M18,M3,M29,M6,M16,M4",
#'     "M6,M7,M8,M9,M10,M11,M9,M29,M6,M6,M16,M4",
#'     "M24,M25,M26,M27,M28,M29,M30,M29,M26,M5",
#'     "M13,M14,M15,M16,M17,M24,M27,M14",
#'     "M15,M16,M17,M18,M19,M20,M21,M4,M8,M10"
#'   )
#' )
#'
#' # Combine with existing PathwayVsMetabolites
#' PathwayVsMetabolites <- rbind(PathwayVsMetabolites, new_rows)
#'
#' # Generate example metabolite-level data
#' example_data <- data.frame(
#'   met_id = inputMetabolites,
#'   pval = runif(20, 0.001, 0.05),  # Random p-values between 0.001 and 0.05
#'   log2fc = rnorm(20, mean = 0, sd = 1)  # Log2 fold changes from normal distribution
#' )
#'
#' # Run the enrichment analysis
#' enrichmet(inputMetabolites, PathwayVsMetabolites, example_data, top_n = 20)
#' @export

enrichmet <- function(inputMetabolites, PathwayVsMetabolites, example_data, top_n = 100, p_value_cutoff = 1) {

  # ----------------- Convert Adjacency Matrix to List -------------------------
  matrix_to_list <- function(pws) {
    pws.l <- list()
    for (pw in colnames(pws)) {
      pws.l[[pw]] <- rownames(pws)[as.logical(pws[, pw])]
    }
    return(pws.l)
  }

  # ----------------- Prepare GMT File from PathwayVsMetabolites -----------------
  prepare_gmt <- function(gmt_file, metabolites_in_data, savefile = FALSE) {
    gmt <- gmtPathways(gmt_file)
    hidden <- unique(unlist(gmt))

    mat <- matrix(NA, dimnames = list(hidden, names(gmt)),
                  nrow = length(hidden), ncol = length(gmt))
    for (i in 1:dim(mat)[2]){
      mat[,i] <- as.numeric(hidden %in% gmt[[i]])
    }

    hidden1 <- intersect(metabolites_in_data, hidden)
    mat <- mat[hidden1, colnames(mat)[which(colSums(mat[hidden1,]) > 5)]]

    final_list <- matrix_to_list(mat)

    if(savefile){
      saveRDS(final_list, file = paste0(gsub('.gmt', '', gmt_file), '_subset_', format(Sys.time(), '%d%m'), '.RData'))
    }

    return(final_list)
  }

  # ----------------- Convert PathwayVsMetabolites to GMT Format -----------------
  PathwayVsMetabolites$description <- "https://www.genome.jp/kegg/pathway.html#metabolism"

  convert_to_gmt <- function(pathway, description, metabolites) {
    pathway_underscore <- gsub(" ", "_", pathway)
    metabolites_vector <- unlist(strsplit(metabolites, ","))
    gmt_line <- paste(pathway_underscore, description, paste(metabolites_vector, collapse = "\t"), sep = "\t")
    return(gmt_line)
  }

  gmt_data <- mapply(convert_to_gmt, PathwayVsMetabolites$Pathway, PathwayVsMetabolites$description, PathwayVsMetabolites$Metabolites, SIMPLIFY = TRUE)

  gmt_file <- "output.gmt"
  writeLines(gmt_data, gmt_file)

  # ----------------- Prepare Data -----------------
  data <- PathwayVsMetabolites %>%
    mutate(Metabolites = strsplit(Metabolites, ",")) %>%
    unnest(Metabolites)

  allMetabolitesSet <- unique(data$Metabolites)

  # ----------------- Compute Betweenness Centrality -----------------
  edge_list_pathways <- data.frame(from = rep(data$Pathway, lengths(data$Metabolites)), to = unlist(data$Metabolites))
  g_pathways <- graph_from_data_frame(d = edge_list_pathways, directed = FALSE)

  edge_list_metabolites <- data.frame(from = unlist(data$Metabolites), to = rep(data$Pathway, lengths(data$Metabolites)))
  g_metabolites <- graph_from_data_frame(d = edge_list_metabolites, directed = FALSE)

  betweenness_metabolites <- betweenness(g_metabolites, directed = FALSE, normalized = TRUE)
  metabolite_centrality <- data.frame(Metabolite = names(betweenness_metabolites), RBC_Metabolite = betweenness_metabolites)

  input_metabolite_centrality <- metabolite_centrality %>%
    filter(Metabolite %in% inputMetabolites) %>%
    arrange(desc(RBC_Metabolite)) %>%
    filter(RBC_Metabolite > 0)

  # ----------------- Perform Fisher’s Exact Test -----------------
  results <- list()

  for (i in 1:nrow(PathwayVsMetabolites)) {
    row <- PathwayVsMetabolites[i, ]
    pathway <- row$Pathway
    pathwayMetabolites <- unlist(strsplit(row$Metabolites, ","))

    a <- length(intersect(pathwayMetabolites, inputMetabolites))
    b <- length(setdiff(inputMetabolites, pathwayMetabolites))
    c <- length(setdiff(pathwayMetabolites, inputMetabolites))
    d <- length(setdiff(allMetabolitesSet, union(inputMetabolites, pathwayMetabolites)))

    contingency_table <- matrix(c(a, b, c, d), nrow = 2, byrow = TRUE)

    fisher_test_result <- fisher.test(contingency_table, alternative = "two.sided")

    results[[i]] <- list(Pathway = pathway, P_value = fisher_test_result$p.value, Log_P_value = -log10(fisher_test_result$p.value))
  }

  results_df <- do.call(rbind, lapply(results, as.data.frame))
  results_df$Adjusted_P_value <- p.adjust(results_df$P_value, method = "BH")

  significant_results_df <- results_df %>%
    filter(Adjusted_P_value < p_value_cutoff) %>%
    arrange(desc(Log_P_value))

  if (!is.null(top_n)) {
    significant_results_df <- head(significant_results_df, top_n)
  }

  # ----------------- Pathway Enrichment Plot -----------------
  pathway_plot <- ggplot(significant_results_df, aes(x = reorder(Pathway, Log_P_value), y = Log_P_value, fill = Adjusted_P_value)) +
    geom_col() +
    coord_flip() +
    scale_fill_gradient(low = "red", high = "blue") +
    labs(x = "Pathway", y = "-log10(P-value)", fill = "Adj P-value") +
    theme_minimal()

  # ----------------- GSEA Preparation -----------------
  # Prepare example data for GSEA
  example_filtered_data <- example_data %>%
    arrange(pval) %>%           # Sort by p-value
    distinct(met_id, .keep_all = TRUE)

  example_cleaned <- example_filtered_data %>%
    filter(met_id != "No Metabolites found")

  meta = example_cleaned$met_id
  bg_metabolites = prepare_gmt(gmt_file, meta, savefile = FALSE)

  # Prepare ranked list of metabolites for GSEA
  example_cleaned$pval = as.numeric(example_cleaned$pval)
  rankings = sign(example_cleaned$log2fc) * (-log10(example_cleaned$pval))
  names(rankings) <- example_cleaned$met_id  # metabolites as names
  rankings <- sort(rankings, decreasing = TRUE)

  # Run GSEA
  MSEAres <- fgsea(pathways = bg_metabolites,
                   stats = rankings,
                   scoreType = 'std',
                   minSize = 10,
                   maxSize = 500,
                   nproc = 1)

  # ----------------- GSEA Plot -----------------
  MSEAres$input_count <- sapply(strsplit(as.character(MSEAres$leadingEdge), ","), length)
  MSEAres <- MSEAres %>% arrange(pval)

  MSEAres$pathway <- factor(MSEAres$pathway, levels = MSEAres$pathway)

  gsea_plot <- ggplot(MSEAres, aes(x = -log10(pval), y = pathway, size = input_count, color = NES)) +
    geom_point() +
    labs(x = "-log10(p-value)", y = "Pathway", size = "Metabolite count", color = "NES") +
    scale_size_continuous(labels = scales::number_format(accuracy = 1)) +
    scale_color_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0) +
    theme_minimal() +
    theme(panel.border = element_rect(color = "black", fill = NA, size = 0.5),
          axis.ticks.y = element_line(color = "black"))

  # ----------------- Export Results to Excel -----------------
  write.xlsx(significant_results_df, "pathway_enrichment_results.xlsx")
  write.xlsx(MSEAres, "gsea_results.xlsx")

  # ----------------- Plot RBC for Input Metabolites -----------------
  filter2 <- subset(input_metabolite_centrality, RBC_Metabolite > 0)
  rbc_plot <- ggplot(filter2, aes(x = reorder(Metabolite, RBC_Metabolite), y = RBC_Metabolite, fill = RBC_Metabolite)) +
    geom_bar(stat = "identity") +
    coord_flip() +
    scale_fill_gradient(low = "orange", high = "red3") +
    labs(title = "",
         x = "Metabolite", y = "Relative Betweenness Centrality", fill = "RBC") +
    theme_minimal()

  return(list(pathway_plot = pathway_plot, gsea_plot = gsea_plot, rbc_plot = rbc_plot))
}
