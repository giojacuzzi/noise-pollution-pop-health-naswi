source('global.R')
source('simulation/contours.R')

library(raster)
library(sf)
library(glue)
library(gdalUtils)
library(rslurm)
library(fasterize)
library(mapview)
mapviewOptions(mapview.maxpixels = 50000000)
options(tigris_use_cache = T)

input_path = paste0(here::here(), '/analysis/population_noise_exposure/_output')
output_path = paste0(here::here(), '/analysis/population_noise_exposure/_output')
pop_exposure_stack = stack(glue('{input_path}/noise_exposure/pop_exposure_stack.grd'))
pop_areas_stack = stack(glue('{input_path}/noise_exposure/pop_areas_stack.grd'))

msg('Starting population noise exposure assessment...')
filename_output = glue(output_path, '/population_noise_exposure_output.txt')
sink(filename_output, split=T)

# mapview(pop_exposure_stack[['Exposed.Population']], layer.name=c('Exposed Persons')) +
#   mapview(pop_exposure_stack[['Ldn']], layer.name=c('Ldn (dB)')) +
#   mapview(pop_exposure_stack[['Lnight']], layer.name=c('Lnight (dB)')) +
#   mapview(pop_exposure_stack[['Leq24']], layer.name=c('Leq24 (dB)'))

# Total area of noise exposure associated with adverse health effects (note this includes water)
contours_Ldn = get_contours_Ldn()
impact_area = st_area(st_make_valid(st_union(contours_Ldn[contours_Ldn$Level>=threshold_adverse_health_effects_Lden,])))
msg('Total area of noise exposure associated with adverse health effects:', round(units::set_units(impact_area, km^2),2), 'km2', round(units::set_units(impact_area, mi^2),2), 'mi2')

msg('Total exposed population:', round(cellStats(pop_exposure_stack[['Exposed.Population']], 'sum')))

## Number of people at risk of annoyance
nexp_annoyance = round(cellStats(mask(pop_exposure_stack[['Exposed.Population']], clamp(pop_exposure_stack[['Ldn']], lower=threshold_annoyance_Lden, useValues=F)), 'sum'))
msg('Number of people at risk of annoyance:', nexp_annoyance)

## Number of people exposed to sleeping disturbance risk threshold
nexp_sleep_disturbance = round(cellStats(mask(pop_exposure_stack[['Exposed.Population']], clamp(pop_exposure_stack[['Lnight']], lower=threshold_sleep_disturbance_Lnight, useValues=F)), 'sum'))
msg('Number of people at risk of sleep disturbance:', nexp_sleep_disturbance)

## Number of people exposed to hearing impairment risk threshold
nexp_hearing_impairment = round(cellStats(mask(pop_exposure_stack[['Exposed.Population']], clamp(pop_exposure_stack[['Leq24']], lower=threshold_hearing_impairment_Leq24, useValues=F)), 'sum'))
msg('Number of people at risk of hearing impairment:', nexp_hearing_impairment)

## Number of people exposed to noise levels incompatible with residential land use (65 dB Ldn, FAA and HUD)
nexp_land_use = round(cellStats(mask(pop_exposure_stack[['Exposed.Population']], clamp(pop_exposure_stack[['Ldn']], lower=threshold_land_use_Ldn, useValues=F)), 'sum'))
msg('Number of people exposed to noise levels incompatible with land use regulations:', nexp_land_use)

#######################################

# Calculate at-risk population for each zone
health_risk_summary = data.frame()
for (zone in names(pop_areas_stack)) {
  zone_name = unlist(str_split(zone, '_'))[1]
  type = unlist(str_split(zone, '_'))[2]
  msg(zone_name, ' (', type, ')', sep='')
  
  # Total zone population
  zone_pop = pop_areas_stack[[zone]]
  npop_zone = cellStats(zone_pop, 'sum')
  msg('  Total        ', npop_zone)
  
  ## Total exposed population
  dasy_pop_cropped = crop(zone_pop, pop_exposure_stack[['Ldn']])
  dasy_pop_masked = mask(dasy_pop_cropped, pop_exposure_stack[['Ldn']])
  dasy_pop_masked[dasy_pop_masked == 0] = NA # set all 0 population cells to NA
  estimated_pop_exposed = dasy_pop_masked
  npop_exposed = cellStats(estimated_pop_exposed, 'sum')
  msg('  Exposed      ', npop_exposed)
  
  ## Annoyance
  pop_risk_annoyance = mask(estimated_pop_exposed, area_risk_annoyance)
  npop_risk_annoyance = cellStats(pop_risk_annoyance, 'sum')
  msg('  Annoyance          ', npop_risk_annoyance)
  
  ## Sleep disturbance
  pop_risk_sleep_disturbance = mask(estimated_pop_exposed, area_risk_sleep_disturbance)
  npop_risk_sleep_disturbance = cellStats(pop_risk_sleep_disturbance, 'sum')
  msg('  Sleep disturbance          ', npop_risk_sleep_disturbance)
  
  ## Hearing impairment
  pop_risk_hearing_impairment = mask(estimated_pop_exposed, area_risk_hearing_impairment)
  npop_risk_hearing_impairment = cellStats(pop_risk_hearing_impairment, 'sum')
  msg('  Hearing impairment          ', npop_risk_hearing_impairment)
  
  ## Land use
  pop_incompatible_land_use = mask(estimated_pop_exposed, area_incompatible_land_use)
  npop_incompatible_land_use = cellStats(pop_incompatible_land_use, 'sum')
  msg('  Incompatible land use         ', npop_incompatible_land_use)
  
  # Add results to table
  health_risk_summary = rbind(health_risk_summary, data.frame(
    Type         = type,
    Name         = zone_name,
    Population   = npop_zone,
    Exposed      = npop_exposed,
    Annoyance    = npop_risk_annoyance,
    SleepDisturbance = npop_risk_sleep_disturbance,
    HearingImpairment = npop_risk_hearing_impairment,
    IncompatibleLandUse = npop_incompatible_land_use
  ))
}

# Subset only the counties and check values
health_risk_summary_counties = health_risk_summary[health_risk_summary$Type == 'county', ]
stopifnot(sum(health_risk_summary_counties$Exposed) == cellStats(pop_exposure_stack[['Exposed.Population']], 'sum'))

# Format table and calculate totals for the entire study region
health_risk_summary = health_risk_summary %>% mutate_at(c(3:ncol(health_risk_summary)), round)
health_risk_summary = health_risk_summary[health_risk_summary$Exposed != 0, ] # remove counties with no exposure
health_risk_summary = health_risk_summary[order(health_risk_summary$Exposed, decreasing=T), ]

totals = health_risk_summary[health_risk_summary$Type == 'county', ] %>%
  summarise(., across(where(is.numeric), sum), across(where(is.character), ~"Total"))

# Append percentages
health_risk_summary$Exposed = paste0(health_risk_summary$Exposed, ' (', round(health_risk_summary$Exposed / health_risk_summary$Population, 3) * 100, '%)')

health_risk_summary = rbind(health_risk_summary, totals)

# Manually enter zone names
health_risk_summary = health_risk_summary[,2:ncol(health_risk_summary)]
health_risk_summary$Name = c(
  'Island County',
  'Skagit County',
  'Samish TDSA',
  'Swinomish Reservation',
  'Jefferson County',
  'San Juan County',
  'Total'
)

msg(health_risk_summary)

#######################################

# Write table and results to files
sink()
msg('Created', filename_output)
filename = glue(output_path, '/population_noise_exposure_summary.csv')
write.csv(health_risk_summary, filename, row.names = F)
msg('Created', filename)