### Run file for the 384 well plate pH assay report ####

# working directory handled by here::here()


# Set the names of the strains in this plate
S1<-"25G2A02" # Strain in columns 1-3
S2<-"35G3B04" # Strain in columns 10-12
S3<-"28D03" # Strain in columns 4-6


SVEC<-c(S1,S2,S3)

data <- read.csv(file=here::here("data-raw/pH/2023-02-06.csv"), header = TRUE, stringsAsFactors = F)

date<-"2023-02-06"


rmarkdown::render(
  input = here::here("R/pH/provenance/report_sources/GC_initial_analysis.Rmd"),  
  output_file = stringr::str_glue(here::here("output/reports/pH_assay_Report_{date}.html")),
  params = list(date = date,
                strains = SVEC))
