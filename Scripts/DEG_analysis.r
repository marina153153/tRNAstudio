#! /usr/bin/Rscript

# PIPELINE FOR DIFFERENTIAL EXPRESION ANALYSIS FOR LINUX
list.of.packages <- c("magick","pheatmap","BiocManager","plyr",
                      "tidyverse","readxl","data.table","xtable")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)>0){
  install.packages(new.packages, repos = "http://cran.us.r-project.org")
}

list.of.packages <- c("Rsubread", "GenomicAlignments","GenomicFeatures",
                      "Rsamtools", "edgeR", "DESeq2","vsn","Glimma","ReportingTools")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)>0){
  
 BiocManager::install(new.packages, update=TRUE, ask=FALSE)
}

rm(list.of.packages)
rm(new.packages)
suppressPackageStartupMessages({
library(Rsubread)
library("GenomicAlignments")
library("GenomicFeatures")
library("Rsamtools")
library("edgeR")
library("DESeq2")
library("vsn")
#library("magick")
library("Glimma")
library("pheatmap")
library(ggplot2)
library(rmarkdown)
  library(plyr)
  library("data.table")
  library(xtable)
  library(ReportingTools)
})
#1-Obtain count matrix.



if (!file.exists("../Results/DEG")){
  dir.create("../Results/DEG", recursive=TRUE)
}
all_genes <- read.delim("../Results/R_files/Counts/Counts_by_gene_total_for_DESeq2.txt")

sampleInfo_total <- read.table("../Fastq_downloaded/sample_data.txt",
                               header=T, stringsAsFactors = T)


## DESeq2 for isoaceptors.

all_data = data.frame(all_genes, isodecoder=rownames(all_genes))
all_data = data.frame(all_data, do.call(rbind, strsplit(as.character(
  all_data$isodecoder), "-")))

# We keep the count matrix and the aa.
all_data = all_data[c(c(1:ncol(all_data)), ncol(all_data)-3, ncol(all_data)-2)]
colnames(all_data)[c(ncol(all_data)-1,ncol(all_data))] = c("aa", "codon")

all_data = all_data[all_data$aa !="*",]
all_data$aa = factor(all_data$aa)
isoaceptors = data.frame()
for(aminoacid in levels(all_data$aa)){
  # Select all isodecoders from each isoaceptor, delete codon and isoaceptor info
  isoaceptor1 = all_data[all_data$aa==aminoacid,1:(ncol(all_data)-8)]
  isoaceptor1 = t(apply(isoaceptor1, 2, function(x) sum(x)))
  rownames(isoaceptor1) = aminoacid
  isoaceptors = rbind(isoaceptors, isoaceptor1)
}


all_data = data.frame(all_data, paste0(all_data$aa, " ", all_data$codon))
colnames(all_data)[ncol(all_data)] = "isodecoder"
all_data$isodecoder = factor(all_data$isodecoder)
isodecoders = data.frame()
for(isodecoder in levels(all_data$isodecoder)){
  # Select all isodecoders from each isoaceptor, delete codon and isoaceptor info
  isodecoder1 = all_data[all_data$isodecoder==isodecoder,1:(ncol(all_data)-9)]
  isodecoder1 = t(apply(isodecoder1, 2, function(x) sum(x)))
  rownames(isodecoder1) = isodecoder
  isodecoders = rbind(isodecoders, isodecoder1)
}


#tRFs = read.delim("../Results/R_files/Counts/Counts_tRFs.txt")

conditions = c("isoaceptors", "isodecoders","all_genes") #, "tRFs")
for(condition in conditions){
  if(condition =="isoaceptors"){ count_data = isoaceptors}
  if(condition =="isodecoders"){ count_data = isodecoders}
  if(condition =="all_genes"){ count_data = all_genes}
  if(condition =="tRFs"){ count_data = tRFs}
  # Use the count matrix and the sample info to create the final matrix.
  
  deseqdata_total <- DESeqDataSetFromMatrix(countData=count_data, 
                                            colData=sampleInfo_total, 
                                            design=~Condition)
  ##Remember:The DESeq2 model internally corrects for library size, so transformed or normalized values such as counts scaled by library size should not be used as input.
  
  #sum(colSums(assays(deseqdata_total)$counts)) #all the reads of the whole experiment 
  #sum(colSums(assays(deseqdata_total)$counts))/ncol(deseqdata_total) #this is the ideal depth (is the same value as the mean of the summary)
  dge <- DGEList(counts=assays(deseqdata_total)$counts, genes=mcols(deseqdata_total),
                 group=deseqdata_total$Condition)
  #ord = order(dge$samples$lib.size/1e6)

  
  #Level factors 
  deseqdata_total$Condition <- factor(deseqdata_total$Condition)
  deseqdata_total$Condition <- droplevels(deseqdata_total$Condition)
  
  #Perform the DE 
  des <- DESeq(deseqdata_total)
  
  #CHANGE/VERIFY THE ORDER OF THE COMPARISON
  resDESeq2 <- results(des, 
                       pAdjustMethod="BH")
  
  out_result = na.omit(data.frame(resDESeq2))
  setorderv(out_result, cols="padj")
  file_out = paste0("../Results/DEG/DESeq2_", condition, "_results.txt")
  write.table(out_result, file = file_out, sep = "\t",
              row.names = TRUE, col.names = NA, quote=FALSE)
  
  #We can order our results table by the smallest p value:
  resDESeq2Ordered <- resDESeq2[order(resDESeq2$pvalue),]
  
  # This gives log2(n +1)
  ntd = normTransform(deseqdata_total)
  file_heatmap_jpeg = paste0("../Results/DEG/Heatmap_", condition, "_DESeq2.jpeg")
  jpeg(file_heatmap_jpeg)
  show_rownames=F
  if(condition == "isoaceptors"){ show_rownames=T}
  pheatmap(assay(ntd), cluster_rows=T, show_rownames=show_rownames, show_colnames = T,
           cluster_cols=T,fontsize_row=8, clustering_method="ward.D")
  resDESeq2_data <- as.data.frame(assay(ntd))
  file_heatmap_txt = paste0("../Results/DEG/Heatmap_", condition, "_DESeq2.txt")
  write.table(resDESeq2_data, file = file_heatmap_txt, sep = "\t",
              row.names = TRUE, col.names = NA)
  dev.off()
  
  group1 = which(sampleInfo_total$ID %in% unfactor(sampleInfo_total$ID[
    sampleInfo_total$Condition ==  levels(sampleInfo_total$Condition)[1] ] ))
  
  group2 = which(sampleInfo_total$ID %in% sampleInfo_total$ID[
    sampleInfo_total$Condition ==  levels(sampleInfo_total$Condition)[2] ] )
  
  mean_group1 = apply(assay(ntd),1, function(x) mean(x[group1]))
  mean_group2 = apply(assay(ntd),1, function(x) mean(x[group2]))
  diff_expr = mean_group1 - mean_group2
  
  mean_data = data.frame(mean_group1, mean_group2)
  colnames(mean_data) = c(levels(sampleInfo_total$Condition))
  
  f_heatmap_groups_jpeg = paste0("../Results/DEG/Heatmap_groups_", 
                                 condition, "_DESeq2.jpeg")
  jpeg(f_heatmap_groups_jpeg)
  
  pheatmap(mean_data, cluster_rows=T, show_rownames=show_rownames, show_colnames = T,
           cluster_cols=F,fontsize_row=8, clustering_method="ward.D")
  resDESeq2_data_mean <- as.data.frame(mean_data)
  f_heatmap_groups_jpeg = paste0("../Results/DEG/Heatmap_groups", 
                                 condition, "_DESeq2.txt")
  write.table(resDESeq2_data_mean, file = "../Results/DEG/Heatmap_groups_DESeq2.txt", sep = "\t",
              row.names = TRUE, col.names = NA)
  dev.off()
  
  
  ## Data visualization. Glimma
  status <- as.numeric(resDESeq2$padj < .05)
  anno <- data.frame(GeneID=rownames(resDESeq2))
  fMD = paste0("DESeq2_MD-plot_", condition)
  glMDPlot(resDESeq2, status=status, counts=counts(des,normalized=TRUE),
           groups=des$Condition, transform=FALSE,
           samples=colnames(des), anno=anno, launch = F, 
           html =fMD ,folder = "../Results/DEG")
}


### Iso-tRNA-CP

sample_data = sampleInfo_total
#Read proportions table
counts <- read.table("../Results/R_files/Counts/Counts_by_gene_total_for_DESeq2.txt", 
                     header=TRUE, quote="\"",stringsAsFactors = T, row.names=1)


counts = data.frame(counts, TRNA=rownames(counts))

#obtain prop
counts <- data.frame(counts,do.call(rbind,strsplit(as.character(counts$TRNA),"-")))
counts[ ,c('V4', 'X1','X4','X5')] <- list(NULL)
colnames(counts)[length(counts)]<- "Cod"
colnames(counts)[length(counts)-1]<- "Aa"


counts = counts[counts$Cod!="*",]
counts = counts[order(counts$Cod),]
cod_list <- unique(counts$Cod)

all_prop <- data.frame(matrix(ncol = ncol(counts), nrow = 0))
colnames(all_prop)<- colnames(counts)

for (cod in cod_list) {
  trna_cod <- counts[counts$Cod == cod, ]
  sum <- apply(trna_cod[1:(ncol(trna_cod)-3)], 2, function(x) sum(x))
  trna_cod = as.data.frame(t(apply(trna_cod[1:(ncol(trna_cod)-3)], 1, 
                                   function(x) x/sum)))
  all_prop <- rbind.fill(all_prop,trna_cod)
}

rownames(all_prop) = rownames(counts)
all_prop$TRNA = counts$TRNA
all_prop$Cod = counts$Cod
all_prop$Aa = counts$Aa


proportions = all_prop[c(1:(ncol(all_prop)-3))]
conditions1 = sample_data$Condition == levels(sample_data$Condition)[1]
conditions2 = sample_data$Condition == levels(sample_data$Condition)[2]
# Apply Wilcoxon test (a nonparametric statistical test that compares two paired groups)
is0 = apply(proportions, 1, function(x) sum(x)==0)
proportions = na.omit(proportions[!is0,])
# We compute pvalue with alternative hipothesis less and gr than and choose the
# lower value (the comparison that has sense)
test1 <- apply(proportions,1, function(a) 
  wilcox.test(x=a[conditions1],y=a[conditions2], alternative = "less")$p.value)
test2 = apply(proportions,1, function(a) 
  wilcox.test(x=a[conditions1],y=a[conditions2], alternative = "gr")$p.value)


test = cbind(test1, test2)
test = apply(test,1,function(x) min(x))

Adjusted_pvalue = p.adjust(test, method="BH")

test = as.data.frame(test)
colnames(test) = "pvalue"

options(scipen=999)




mean_group1 = na.omit(data.frame(apply(proportions[,conditions1], 1, function(x) mean(x))))
colnames(mean_group1) = paste0("Proportion_", levels(sample_data$Condition)[1])

mean_group2 = na.omit(data.frame(apply(proportions[,conditions2], 1, function(x) mean(x))))
colnames(mean_group2) = paste0("Proportion_", levels(sample_data$Condition)[2] )



data_iso = data.frame(mean_group1, mean_group2, test, Adjusted_pvalue)
data_iso = data.frame(genes = rownames(data_iso), data_iso)
#log2fc = log2(data_iso[,3]/data_iso[,2])
fc = (as.numeric(data_iso[,3])/as.numeric(data_iso[,2]))
#diff_mean = 2*(data_iso[,3]-data_iso[,2])/ (data_iso[,3]+data_iso[,2])

data_iso = data.frame(data_iso[,1:3], Fold_change = fc, data_iso[,4:ncol(data_iso)] )
setorderv(data_iso, cols="Adjusted_pvalue", 1)

fout = "Results_iso-tRNA-CP"
title = "Results iso-tRNA-CP"
htmlRep = HTMLReport(shortName= fout, title= title, 
                     reportDirectory = "../Results/DEG")
publish(data_iso, htmlRep)
finish(htmlRep)

write.table(data_iso, file = "../Results/DEG/Results_isotRNACP.txt", sep = "\t",
            row.names = TRUE, col.names = NA)

#fout1 = "Results_isotRNACP.html"
#htmlRep1 = HTMLReport(shortName=fout1, rownames=T,
 #                     title="Test iso-tRNA-CP", 
  #                    reportDirectory = "../Results/DEG")
#publish(data_iso, htmlRep1)
#finish(htmlRep1)
#options(scipen = 999)



group1 = which(sample_data$ID %in%sample_data$ID[
  sample_data$Condition ==  levels(sample_data$Condition)[1] ] )
group2 = which(sample_data$ID %in%sample_data$ID[
  sample_data$Condition ==  levels(sample_data$Condition)[2] ] )

unique_aa = unique(all_prop$Aa)

# Plots proportions pools isodecoders.

if (!file.exists("../Results/Plots/isotRNACP")){
  dir.create("../Results/Plots/isotRNACP", recursive=TRUE)
}
for(aa in unique_aa){
  data = all_prop[all_prop$Aa == aa,]
  first_group = apply(data[group1],1, function(x) mean(x))
  second_group = apply(data[group2],1, function(x) mean(x))
  means = as.numeric(c(first_group, second_group))
  group = c(rep(levels(sample_data$Condition)[1], length(first_group)),
            rep(levels(sample_data$Condition)[2], length(second_group)))
  
  data_final = data.frame(cbind(means, group, tRNA =rep(data$TRNA,2), 
                                Aa=rep(data$Aa,2), Cod=rep(data$Cod,2)))
  data_final$means = as.numeric(data_final$means)
  p= ggplot(data = data_final, aes(x=tRNA, y=means, fill=group))+ 
    scale_fill_manual(values=c("dodgerblue","olivedrab3"))+
    geom_bar(stat="identity", position=position_dodge2()) + 
    labs(x="tRNA family",y = "Proportion", fill="Group")+ 
    theme(text = element_text(size=10), 
          axis.text.x = element_text(angle=90, color="black", vjust=0.5), 
          axis.text.y = element_text(color="black"), 
          panel.background =element_rect(fill = "snow2", colour = "snow2",
                                         size = 0.5, linetype = "solid"),
          strip.text.x = element_text(face="bold")) + 
    facet_grid(~Cod, scales="free", space="free")
  file_name = paste0("../Results/Plots/isotRNACP/Plots_iso_", aa, ".jpeg")
  ggsave(plot=p, filename=file_name,
         width = 20, height = 10, units = "cm")
  
}

# Heatmap total
jpeg("../Results/DEG/Heatmap_total_isotRNACP.jpeg")
p = pheatmap(proportions, cluster_rows=T, show_rownames=T, show_colnames = T,
             cluster_cols=F,fontsize_row=0.5, clustering_method="ward.D")
res_data_mean <- as.data.frame(proportions)
write.table(proportions, file = "../Results/DEG/Heatmap_total_isotRNACP.txt", sep = "\t",
            row.names = TRUE, col.names = NA)
dev.off()


#Heatmap group
mean_group1 = apply(proportions,1, function(x) mean(x[group1]))
mean_group2 = apply(proportions,1, function(x) mean(x[group2]))
diff_expr = mean_group1 - mean_group2

mean_data = data.frame(mean_group1, mean_group2)
colnames(mean_data) = c(levels(sampleInfo_total$Condition))

jpeg("../Results/DEG/Heatmap_groups_isotRNACP.jpeg")
p = pheatmap(mean_data, cluster_rows=T, show_rownames=T, show_colnames = T,
             cluster_cols=F,fontsize_row=0.5, clustering_method="ward.D")
res_data_mean <- as.data.frame(mean_data)
write.table(res_data_mean, file = "../Results/DEG/Heatmap_groups_isotRNACP.txt", sep = "\t",
            row.names = TRUE, col.names = NA)
dev.off()

#Differentially expressed genes.
genesDESeq2 = rownames(resDESeq2)
resDESeq205 = data.frame(pvalue_adj= resDESeq2$padj)
resDESeq205 = data.frame(resDESeq205, gene =genesDESeq2 )
resDESeq205 = na.omit(resDESeq205[resDESeq205$pvalue_adj<0.05,])


test_adjust = as.data.frame(p.adjust(test$pvalue, method="BH"))
colnames(test_adjust) = "pvalue_adj"
rownames(test_adjust) = rownames(test)
genes_iso = rownames(test_adjust)
test_adjust = data.frame(pvalue_adj= test_adjust, gene=genes_iso)
test_iso <- na.omit(test_adjust[test_adjust$pvalue_adj < 0.05,])

rmarkdown::render("Report_comparison.Rmd", 
                  output_dir = "../Results/Reports")

