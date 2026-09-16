## merging interrupted plate reader data sets

# working directory handled by here::here()


library(lubridate)


# Read in the Data
data1<-read.csv(file=here::here("data-raw/pH/pHassay_033123_interrupted_at_17hr.csv"), header = TRUE, stringsAsFactors = F)
# Remove the temperature column
#data1 <- data1[,-2]

# Change time from HH:MM:SS to hours and fractions in decimals
data1$Time<-period_to_seconds(hms(data1$Time))/3600


# Read in the Data
data2<-read.csv(file=here::here("data-raw/pH/pHassay_033123_interrupted_at_17hr_pt2.csv"), header = TRUE, stringsAsFactors = F)
# Remove the temperature column
#data2 <- data2[,-2]

# Change time from HH:MM:SS to hours and fractions in decimals
data2$Time<-period_to_seconds(hms(data2$Time))/3600
## add 24hrs to the time column in data set 2, to compensate for the restart of the program and to match with the time in plate 1
data2$Time<-data2$Time+24

## now merge with the first data set
data<-rbind(data1, data2)

write.csv(data, "pHassay_033123_merged.csv", quote = FALSE, row.names = FALSE)
