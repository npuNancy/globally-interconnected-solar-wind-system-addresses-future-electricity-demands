##1.????????
rm(list = ls())
library(readxl)
my_data <- read_excel("D:/GlobalSolarNet/NC Revision R1/Figures/Benefits_Data_Summary.xlsx", sheet = "EnergyExchange", col_names = FALSE)
#colnames(my_data) <- my_data[,1]
#my_data <- my_data[,-1]
#rownames(my_data) <- my_data[1,]
#my_data <- my_data[-1,]
my_matrix <- as.matrix(my_data)
my_matrix <- my_matrix/1000
rownames(my_matrix) = paste0("S", 1:20)
colnames(my_matrix) = paste0("E", 1:20)
my_matrix
library(circlize)
chordDiagram(my_matrix)



aa<-scale_fill_viridis(option="rainbow")

library(tidyverse)
library(ggsci)
mypal<-pal_aaas(alpha=0.7)(8)