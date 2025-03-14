#Starting up
library(tidyverse)
library(DEP)
library(openxlsx)
library(ggrepel)
library(tcltk)
library(PTXQC)
tkmessageBox(message="Choose your working directory. Make sure that the `Analysis_parameters`, `pg_matrix.tsv` and 'pr_matrix.tsv' are located in your working directory ")
setwd(tk_choose.dir())

tkmessageBox(message="Please ensure that the abundance column names (and thus the .raw files) contain the name of the mass spectrometer used (e.g. Astral, Exploris) and the following information, in order and separated by an underscore:

- Condition A (e.g. Cell line)
- Condition B (e.g. WT and KO or treated and untreated)
- Replicate
             
Example: 20250205_Astral_AUR_DZ114_Wildtype_untreated_1.raw")

#import and clean data
parameters <- read.xlsx("Analysis_parameters.xlsx")
proteinGroups <- read.delim(list.files(pattern = "pg_matrix.tsv"))
peptides <- read.delim(list.files(pattern = "pr_matrix.tsv"))

filtered_proteinGroups <- data.frame(
  Protein.Group = names(table(unique(peptides[, c('Protein.Group', 'Stripped.Sequence')])$Protein.Group)),
  Peptide.Count = as.integer(table(unique(peptides[, c('Protein.Group', 'Stripped.Sequence')])$Protein.Group))
) %>% 
  filter(Peptide.Count > 2)

proteinGroups <- proteinGroups[proteinGroups$Protein.Group %in% filtered_proteinGroups$Protein.Group, ]

proteinGroups <-
  make_unique(proteinGroups, "Genes", "Protein.Group", delim = ";")
proteinGroups <- proteinGroups %>% filter(!grepl("Cont_", ID) &
                                            !grepl("KRT", name))

###tidy column names
value_columns <- which(str_detect(names(proteinGroups), parameters$mass_spec))               #specify Mass spec (this should be in the value column names)
prefix <- LCSn(colnames(proteinGroups[, value_columns]))
colnames(proteinGroups) <- gsub(".raw", "", gsub(".*" %>% paste0(prefix), "", colnames(proteinGroups)))
##QC
try(if (max(str_count(colnames(proteinGroups[, value_columns]), "_")) == 1 &
        parameters$conditions != 2 |
        max(str_count(colnames(proteinGroups[, value_columns]), "_")) == 2 &
        parameters$conditions != 3)
  stop("incorrect number of conditions"))


results_A <- list()

if (parameters$conditions == 2) {
  data <- proteinGroups
  experimental_design <- data.frame(label = colnames(data[, value_columns]))
  experimental_design <- experimental_design %>% separate_wider_delim(
    label,
    delim = "_",
    names = c("condition", "replicate"),
    cols_remove = FALSE
  )
  experimental_design <- experimental_design[, c("label", "condition", "replicate")]
  
  #Make object and do analysis
  data_se <- make_se(data, value_columns, experimental_design)
  data_filt <- filter_proteins(data_se, type = parameters$filtering_type, thr = 0)
  data_norm <- normalize_vsn(data_filt)
  if (parameters$filtering_type == "complete") {
    data_imp <- data_norm
  }
  if (parameters$filtering_type == "condition") {
    data_imp <- impute(data_norm, fun = "MinProb", q = 0.01)
  }
  data_diff_manual <- test_diff(data_imp, type = parameters$comparison, control = parameters$control)
  contrast <- sub("_diff", "", str_subset(
    names(data_diff_manual@elementMetadata@listData),
    "_diff"
  ))
  dep <- add_rejections(data_diff_manual, alpha = 0.05, lfc = log2(2))
  for (p in 1:length(contrast)) {
    results_A[[paste0(contrast[p])]] <- get_results(dep)
  }
  ####make pdf containing QCs
  pdf(paste0(contrast, ".pdf"))
  
  print(plot_frequency(data_se))
  print(plot_numbers(data_filt))
  if (parameters$filtering_type == "condition") {
    print(plot_detect(data_filt))
  }
  print(plot_normalization(data_filt, data_norm, data_imp))
  print(plot_imputation(data_norm, data_imp))
  for (p in 1:length(contrast)) {
    print(plot_volcano(
      dep,
      contrast = contrast[p],
      label_size = 2,
      add_names = TRUE
    ))
  }
  dev.off()
  write.xlsx(results_A, paste0("DEP_results.xlsx"))
}

if (parameters$conditions == 3) {
  proteinGroups <-
  proteinGroups %>% pivot_longer(
    cols = all_of(value_columns),
    names_to = c("condition_B", "condition_A", "replicate"),                 #change this depending on the amount of different variables used in your experiment
    names_sep = "_",
    values_to = "values"
  )
  proteinGroups <-
    proteinGroups %>% pivot_wider(names_from = c("condition_A", "replicate"),         #change this if necessary
                                  values_from = "values")
  datalist_B <- split(proteinGroups, f = ~ proteinGroups$condition_B)               #specify variable to be split on
  for (i in 1:length(datalist_B)) {
    name_B <- names(datalist_B[i])
    data <- datalist_B[[i]]
    value_columns <- which(sapply(data, is.numeric))
    
    experimental_design <- data.frame(label = colnames(data[, value_columns]))
    experimental_design <- experimental_design %>% separate_wider_delim(
      label,
      delim = "_",
      names = c("condition", "replicate"),
      cols_remove = FALSE
    )
    experimental_design <- experimental_design[, c("label", "condition", "replicate")]
    data_se <- make_se(data, value_columns, experimental_design)
    data_filt <- filter_proteins(data_se, type = parameters$filtering_type, thr = 0)
    data_norm <- normalize_vsn(data_filt)
    if (parameters$filtering_type == "complete") {
      data_imp <- data_norm
    }
    if (parameters$filtering_type == "condition") {
      data_imp <- impute(data_norm, fun = "MinProb", q = 0.01)
    }
    data_diff_manual <- test_diff(data_imp, type = parameters$comparison, control = parameters$control)
    contrast <- sub("_diff", "", str_subset(
      names(data_diff_manual@elementMetadata@listData),
      "_diff"
    ))
    dep <- add_rejections(data_diff_manual, alpha = 0.05, lfc = log2(2))
    for (p in 1:length(contrast)) {
      results_A[[paste0(name_B, "_", contrast[p])]] <- get_results(dep)
    }
    ####make pdf containing QCs
    pdf(paste0(name_B, "_", contrast, ".pdf"))
    
    print(plot_frequency(data_se))
    print(plot_numbers(data_filt))
    if (parameters$filtering_type == "condition") {
      print(plot_detect(data_filt))
    }
    print(plot_normalization(data_filt, data_norm, data_imp))
    print(plot_imputation(data_norm, data_imp))
    for (p in 1:length(contrast)) {
      print(plot_volcano(
        dep,
        contrast = contrast[p],
        label_size = 2,
        add_names = TRUE
      ))
    }
    dev.off()
  }
  write.xlsx(results_A, paste0("DEP_results.xlsx"))
}


save.image(paste0(getwd(), "/DiaNN - DEP analysis.RData"))

