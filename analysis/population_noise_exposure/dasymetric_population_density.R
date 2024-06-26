## Generate dasymetric population density maps
# Dasymetric population mapping framework: https://zenodo.org/record/7853206
# Input: NLCD rasters and NASWI infrastructure shapefile
# Output: analysis/preprocessing/_output/{county}_dasypop.tif

source('global.R')

# Load packages
library(raster)
library(sf)
library(glue)
library(gdalUtils)
library(rslurm)
library(fasterize)
library(mapview)
mapviewOptions(mapview.maxpixels = 50000000)
options(tigris_use_cache = T)

generate_dasypop_county = function(id) {
  msg('Processing county ', id) # 'Jefferson', 'San Juan', 'Snohomish', 'Island', 'Skagit'
  msg('Retrieving block group population estimates...')
  
  # Get 2021 ACS 5-year block group population estimates
  pop = get_acs(geography = 'block group', variables = 'B01003_001', year = 2021, state = 'WA', county = id, geometry = T)
  file_suffix = paste0(id, '_county')
  zero.pop = get_decennial(geography = 'block', variables = 'P1_001N', year = 2020, state = 'WA', county = id, geometry = T)
  generate_dasypop(id, pop, file_suffix, zero.pop)
}

generate_dasypop_native_land = function(id) {
  msg('Processing native land ', id) # 'Samish', 'Swinomish'
  msg('Retrieving population estimates...')
  
  # Get 2021 ACS 5-year population estimates
  pop = get_acs(geography = 'american indian area/alaska native area/hawaiian home land', variables = 'B01003_001', year = 2021, geometry = T)
  pop = pop[pop$NAME == id, ]
  file_suffix = paste0(unlist(str_split(pop$NAME[1], ' '))[1], '_native')
  zero.pop = get_decennial(geography = 'block', variables = 'P1_001N', year = 2020, state = 'WA', county = c('Island', 'Skagit', 'San Juan'), geometry = T)
  # zero.pop = get_decennial(geography = 'american indian area/alaska native area/hawaiian home land', variables = 'P1_001N', year = 2020, geometry = T)
  # zero.pop = zero.pop[zero.pop$NAME==id, ]
  generate_dasypop(id, pop, file_suffix, zero.pop)
}

generate_dasypop = function(id, pop, file_suffix, zero.pop) {

  # Initial setup: file tree structure
  path = normalizePath(database_path)
  input_path = glue('{path}/GIS/NLCD')
  output_path = paste0(here::here(), '/analysis/population_noise_exposure/_output/dasymetric_population_density')
  output_path_area = glue('{output_path}/{file_suffix}')
  
  # Overwrite any past output
  file.remove(list.files(output_path_area, include.dirs=T, full.names=T, recursive=T))
  dir.create(output_path_area)
  
  message('Loading impervious surface rasters...')
  
  # Create virtual raster VRTs pointing to IMGs without any modification
  imp_raster_imgfile = glue('{input_path}/nlcd_2019_impervious_l48_20210604.img')
  imp_raster_file = glue('{output_path_area}/impervious_{file_suffix}.vrt')
  gdalbuildvrt(
    gdalfile = imp_raster_imgfile,
    output.vrt = imp_raster_file
  )
  
  imp_desc_raster_imgfile = glue('{input_path}/nlcd_2019_impervious_descriptor_l48_20210604.img')
  imp_desc_raster_file = glue('{output_path_area}/impervious_descriptor_{file_suffix}.vrt')
  gdalbuildvrt(
    gdalfile = imp_desc_raster_imgfile,
    output.vrt = imp_desc_raster_file
  )
  
  # Albers equal-area projection
  aea = '+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96 +x_0=0 +y_0=0 +ellps=WGS84 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'
  
  # Remove empty geometries and project to Albers equal-area
  pop = pop[!is.na(st_dimension(pop)), ]
  pop.projected = st_transform(pop, crs = aea)
  # mapview(pop.projected)
  
  message('Fitting county area to impervious raster...')
  
  # Use gdalwarp to extract the county area from the NLCD impervious percentage raster (already in Albers projection)
  polygon_file = glue('{output_path_area}/area_{file_suffix}.gpkg')
  raster_file = glue('{output_path_area}/impervious_{file_suffix}.tif')
  st_write(st_union(pop.projected), dsn = polygon_file, driver = 'GPKG', append = F)
  gdalwarp(
    srcfile = imp_raster_file, dstfile = raster_file,
    cutline = polygon_file, crop_to_cutline = T,
    tr = c(30, 30), dstnodata = 'None'
  )
  
  lu = raster(raster_file)
  # mapview(lu)
  
  message('Culling blocks with no population...')
  
  # Get 2020 decennial block-level population counts
  # Filter for only the blocks with 0 population, and project to Albers equal-area
  # mapview(zero.pop, zcol='value')
  zero.pop = zero.pop[zero.pop$value==0,]
  zero.pop = st_transform(zero.pop, crs = aea)
  # mapview(zero.pop)
  
  message('Masking impervious raster...')
  
  # Mask impervious raster to county boundaries
  lu = mask(lu, as(pop.projected, 'Spatial'))
  # Set pixels with impervious percentage <= 1% to 0
  lu[lu <= 1] = 0
  # Scale impervious percentages between 0 and 1
  lu.ratio = lu/100
  # Set all pixels in zero-population blocks to 0
  lu.ratio.zp = mask(lu.ratio, as(zero.pop, 'Spatial'), inverse = T, updatevalue = 0)
  # mapview(lu.ratio.zp)
  
  # Load impervious surface descriptor dataset, mask all pixels outside the county to NA
  imp.surf.desc = raster(imp_desc_raster_imgfile, band = 1, values = F)
  imp.surf.crop = crop(imp.surf.desc, as(pop.projected, 'Spatial'))
  
  message('Masking out roads and infrastructure...')
  
  # Mask out primary (20), secondary (21), and urban tertiary (22) roads
  # attr(imp.surf.crop, 'data')
  data = slot(attr(imp.surf.crop, 'data'), 'attributes')[[1]]
  data = data[data$Class_Names %in% c('Primary road', 'Secondary road', 'Tertiary road'), ]
  slot(attr(imp.surf.crop, 'data'), 'attributes')[[1]] = data
  
  slot(attr(imp.surf.crop, 'data'), 'attributes')[[1]]$Class_Names = replace(slot(attr(imp.surf.crop, 'data'), 'attributes')[[1]]$Class_Names, !(slot(attr(imp.surf.crop, 'data'), 'attributes')[[1]]$Class_Names %in% c('Primary road', 'Secondary road', 'Tertiary road')), NA)
  imp.surf.mask = mask(imp.surf.crop, as(pop.projected, 'Spatial'))
  # mapview(imp.surf.mask)
  
  # Reclassify road descriptors as '1' and reproject
  imp.roads = deratify(imp.surf.mask, 'Class_Names')
  imp.roads = reclassify(imp.roads, matrix(c(1,3,1), ncol = 3, byrow = T), right = NA)
  imp.roads.p = projectRaster(imp.roads, lu.ratio.zp, method = 'ngb') 
  # mapview(imp.roads.p)
  
  # Set all road pixels to 0 (all non-NA values in imp.roads.p)
  RISA <- overlay(lu.ratio.zp, imp.roads.p, fun = function(x, y) {
    x[!is.na(y[])] = 0
    return(x)
  })
  
  # Set all Navy infrastructure pixels to 0
  if (id == 'Island') {
    infrastructure = st_read('data/gis/NASWI/NASWI_infrastructure.shp', quiet = T)
    infrastructure = st_transform(infrastructure, crs = aea)
    template = raster(extent(RISA), res = res(RISA), crs = aea)
    infrastructure = rasterize(x = infrastructure, y = template)
    RISA <- overlay(RISA, infrastructure, fun = function(x, y) {
      x[!is.na(y[])] = 0
      return(x)
    })
  }
  
  message('Generating population density across remaining impervious cells...')
  
  # Get the block group-level sum of the remaining impervious surface pixels
  RISA.sum = raster::extract(RISA, as(pop.projected, 'Spatial'), fun = sum, na.rm = T, df = T)
  # Rasterize the block group population estimates and impervious surface pixel sums
  pop.df = cbind(pop.projected, RISA.sum$layer)
  bg.sum.pop  = fasterize(pop.projected, RISA, field = 'estimate')
  bg.sum.RISA = fasterize(pop.df, RISA, field = 'RISA.sum.layer')
  
  # Generate density (people/30 m pixel) and write to file.
  dasy.pop = (bg.sum.pop/bg.sum.RISA) * RISA
  stopifnot(cellStats(dasy.pop, 'sum') == sum(pop$estimate)) # total population
  # mapview(reclassify(dasy.pop, cbind(-Inf, 1e-06, NA), right=F))
  filename = glue('{output_path}/dasypop_{file_suffix}.tif')
  writeRaster(dasy.pop, filename, overwrite = T, NAflag = -9999)
  message('Created ', filename)
}
