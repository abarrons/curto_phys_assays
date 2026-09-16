### Run file for the 384 well plate pH assay report ####

# working directory handled by here::here()


################################
##                            ##
## NO Replicates in the plate ##
##                            ##
################################

# Set the names of the strains in this plate
#S1<-"35G1A08" # Strain in Row A
#S2<-"23D06" # Strain in Row B
#S3<-"35G2B04" # Strain in Row C
#S4<-"23G1B05" # Strain in Row D
#S5<-"35G2A07" # Strain in Row E
#S6<-"28D03" # Strain in Row F 
#S7<-"26G3B03" # Strain in Row G
#S8<-"23G1B10" # Strain in Row H
#S9<-"23G1B10" # Strain in Row I
#S10<-"23G1B10" # Strain in Row J
#S11<-"23G1B10" # Strain in Row K
#S12<-"28G4B03" # Strain in Row L
#S13<-"28G4B03" # Strain in Row M
#S14<-"28G4B03" # Strain in Row N
#S15<-"28G4B03" # Strain in Row O

#SVEC<-c(S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15)

#############################
##                         ##
## Replicates in the plate ##
##                         ##
#############################



S1 <- "26G3B03"
S2 <- "28G1A01"
S3 <- "28G4B03"
S4 <- "23G1B10"
S5 <- "23G4B11"

SVEC <- c(rep(S1, 3),
          rep(S2, 3),
          rep(S3, 3),
          rep(S4, 3),
          rep(S5, 3))

data <- read.csv(file=here::here("data-raw/pH/pHassay_052323.csv"), header = TRUE, stringsAsFactors = F)

date<-"2023-05-23"

#############################
##                         ##
## Replicates in the plate ##
##                         ##
#############################


rmarkdown::render(
  input = here::here("R/pH/provenance/report_sources/GC_initial_analysis_384.Rmd"),  
  output_file = stringr::str_glue(here::here("output/reports/pH_assay_Report_{date}.html")),
  params = list(date = date,
                strains = SVEC))

################################
##                            ##
## NO Replicates in the plate ##
##                            ##
################################

#rmarkdown::render(
#  input = "../report_sources/GC_initial_analysis_384_noREPS.Rmd",  
#  output_file = stringr::str_glue(here::here("output/reports/pH_assay_Report_{date}.html")),
#  params = list(date = date,
#                strains = SVEC))
