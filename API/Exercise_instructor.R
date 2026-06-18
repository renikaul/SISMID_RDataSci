## ----setup, include=FALSE----------------------------------------------------------------------------------------------------
knitr::opts_chunk$set(echo = TRUE, eval = FALSE)

library(pacman)

p_load(
  tidyverse,
  tidycensus,
  httr,
  httr2,
  readr,
  stringr
)


## ----load vax----------------------------------------------------------------------------------------------------------------
# use url() to set path to data. This avoids any issues with special characters.
vax_url <- url("https://raw.githubusercontent.com/CSSEGISandData/MMR_data/refs/heads/main/mmr_data_us_counties.csv")
# load data readr::read_csv
vax <- read_csv(vax_url)


## ----explore vax-------------------------------------------------------------------------------------------------------------
# examine
glimpse(vax)

# return states in data set
unique(vax$State)

# return number of counties by state
vax |>
  count(State) |>
  print(n = 38)


## ----httr2 request-----------------------------------------------------------------------------------------------------------
#define as string, not <url> object because request expects string
base_url <- "https://api.census.gov/data/"

URI <-
  request(base_url) |>
  req_url_path_append(
    "2023",
    "acs",
    "acs5",
    "subject"
  ) |>
  # I() is used to escape special characters (colon and *)
  req_url_query(
    `get` = "S2701_C01_011E",
    `for` = I("county:*"),
    `in` = I("state:24")
  )

#check URI will be interpreted correctly  
url_parse(URI$url)

#perform the request
response <-
  URI |>
  req_perform()

#check status of response
response

#look at data that was returned
response |>
  resp_body_json() |>
  glimpse()


## ----API challenge-----------------------------------------------------------------------------------------------------------
base_url <- "https://api.census.gov/data/"

URI <-
  request(base_url) |>
  req_url_path_append()|>
  # I() is used to escape special characters (colon and *)
  req_url_query()

#check URI will be interpreted correctly  
url_parse(URI$url)

#Send request
response <-
  URI |>
  req_perform()

#check status of response
response

#Look at response
response |>
  resp_body_json() |>
  glimpse()


## ----load variable-----------------------------------------------------------------------------------------------------------
v23 <- load_variables(2023, "acs5/subject", cache = TRUE)

v23

v23 |>
  filter(str_detect(name, "S2704_C02_01"))


## ----get_acs practice--------------------------------------------------------------------------------------------------------
  get_acs(
    geography = "county",
    state = "MD",
    variables = "S2701_C02_011",
    survey = "acs5",
    year = 2023
  )


## ----load acs data-----------------------------------------------------------------------------------------------------------
#this is an example of soft coding
acs_variables <- c(
  "S2701_C04_011", # under 19 uninsured
  "S2704_C02_017", # under 6 public insurance
  "S2704_C02_018", # 6-18 public insurance
  "S2701_C02_011" # under 19 population
)

#If you are making more than 500 requests in a day, then you need a key. This requirement is specific to this API, some might require it for each request. 
#census_api_key()

demo <-
  get_acs(
    geography = "county",
    variables = acs_variables,
    survey = "acs5",
    year = 2023
  )



## ----reshape acs data--------------------------------------------------------------------------------------------------------

# set meaningful names to use going forward
acs_names <- c("uninsured","public_under6","public_618", "tot_population")
recode <- setNames(acs_variables, acs_names)

demo_wide <- 
# pivot table
demo |>
  select(GEOID, variable, estimate) |>
  pivot_wider(names_from = variable, values_from = estimate) |>
  rename(any_of(recode)) |>
  mutate(tot_VFC = uninsured+public_under6+public_618,
          p_VFC = tot_VFC/tot_population)
# or use rowwise with a function
  # rowwise() |>
  # mutate(tot_VFC = sum(uninsured,public_under6,public_618),
  #        p_VFC = tot_VFC/tot_population)


## ----finding key-------------------------------------------------------------------------------------------------------------
glimpse(demo_wide)
glimpse(vax)


## ----vax key prep------------------------------------------------------------------------------------------------------------
vax <- 
vax |>
  mutate(GEOID = str_pad(
    as.character(FIPS),
    width = 5,
    side = "left",
    pad = "0"
  ))


## ----join--------------------------------------------------------------------------------------------------------------------
d <- 
vax |>
  left_join(demo_wide) |>
  #keep col of interest
  select(State, County, GEOID, SY2022_23, tot_VFC, tot_population, p_VFC)


## ----scatter plot------------------------------------------------------------------------------------------------------------
d |>
  ggplot(aes(y = p_VFC, x = SY2022_23)) +
  geom_point()


## ----map---------------------------------------------------------------------------------------------------------------------
county_geo <- 
  get_acs(
    geography = "county",
    variables = acs_variables[1],
    geometry = TRUE,
    survey = "acs5",
    year = 2023
  ) |>
  tigris::shift_geometry()|>
  select(GEOID, geometry) 

county_geo |>  
left_join(d) |>
  ggplot(aes(fill = SY2022_23)) +
  geom_sf() +
  scale_fill_distiller(palette = "BuGn",
                      direction = 1,
                      na.value = "grey85") +
  theme_void()



## ----RSocrate----------------------------------------------------------------------------------------------------------------
install.packages("devtools")
devtools::install_github("Chicago/RSocrata")

library("RSocrata")

df <- read.socrata(
  "https://data.cdc.gov/resource/x9gk-5huc.json",
  app_token = "YOURAPPTOKENHERE",
  email     = "user@example.com",
  password  = "fakepassword"
)

df <- read.socrata(
  "https://data.cdc.gov/resource/x9gk-5huc.json?year=2022&states=NEVADA",
  app_token = "1s80fPXvBahgK1s0PRHvKwnmY",
  email     = "rajreni.kaul@gmail.com",
  password  = "Y2F2Pni!sW@yCyJ"
)


## ----httr 1v2----------------------------------------------------------------------------------------------------------------
cdc_url <- "https://data.cdc.gov/resource/x9gk-5huc.csv"

# Using httr2
NNDSS_v1 <-
  request(cdc_url) |>
  req_perform()

#Extract response
NNDSS_v1 |>
  resp_body_string() |>
  glimpse()

# Using httr
NNDSS_v2 <- 
  httr::GET(url = cdc_url)
#Extract response
httr::content(NNDSS_v2)


## ----------------------------------------------------------------------------------------------------------------------------
cdc_url <- "https://data.cdc.gov/resource/x9gk-5huc.csv"

query_params <- 
"states=Connecticut&year=2025&label=Anthrax"

q_url <- paste0(cdc_url, "?", query_params)
httr2::url_parse(q_url)

q_NNDSS <- 
httr::GET(url = q_url)

httr::content(q_NNDSS)


## ----figure out query--------------------------------------------------------------------------------------------------------

httr2::url_parse("https://data.cdc.gov/resource/x9gk-5huc.csv?$query=SELECT%20states%2C%20year%2C%20week%2C%20label%2C%20m1%2C%20m1_flag%2C%20m2%2C%20m2_flag%2C%20m3%2C%20m3_flag%2C%20m4%2C%20m4_flag%2C%20location1%2C%20location2%2C%20sort_order%2C%20geocode%20WHERE%20(upper(%60year%60)%20LIKE%20'%252025%25')%20AND%20(upper(%60label%60)%20LIKE%20'%25MEASLES%25')%20AND%20(upper(%60location1%60)%20LIKE%20'%25TEXAS%25')%20ORDER%20BY%20sort_order%20ASC")



