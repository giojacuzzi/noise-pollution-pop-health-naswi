## Utility functions for acoustic metric calculation

p0 = 2*10^(-5)  # Reference sound pressure in Pascals (Pa) in air 20 μPa

# Acoustic pressure (Pa) to sound pressure level (dB)
pressureToSpl = function(p) {
  20*log10(p/p0)
}

# Sound pressure level (dB) to acoustic pressure (Pa)
splToPressure = function(l) {
  p0*10^(l/20)
}

# NOTE: this is identical to Leq, i.e.
# "equivalent continuous sound pressure level"
# "time-averaged sound pressure level"
# "energy average" (logarithmic)
energyavg = function(L) {
  10*log10(mean(10^(L/10)))
}

energyavg_pressure = function(p) {
  10*log10( (sum(p^2)/length(p)) / (p0^2) )
}

# Leq is the equivalent continuous sound pressure level, also known as the "time-averaged sound pressure level". This is the steady-state sound pressure level which, over a given period of time (t_start to t_end), has the same total acoustic energy as the actual fluctuating noise signal (L). In other words, the RMS sound level with the measurement duration used as the averaging time.

# Calculate total Leq from level series over given time period (ISO 1996, Navy Technical Report)
# Can extrapolate Leq from partially missing data
LeqTotal = function(L, t_start=1, t_end=length(L), extrapolate=TRUE) {
  duration = t_end - t_start + 1
  10*log10(sum(10^(L[t_start:t_end]/10))/duration)
}

# The sound exposure level, SEL (also referred to as LE), of a noise event is the entire event's total sound energy normalized to a constant reference time interval, typically one second. When applied to single event the SEL is called "single-event sound exposure level". SEL can be used to compare the energy of noise events which have different time durations.

# Calculate SEL from Leq of identical time period	
SelFromLeq = function(Leq, duration) {
  Leq + 10*log10(duration) # Leq plus 10 times the log of the duration over 1 second)
}

# Calculate SEL from level series
# Also known as "sound exposure level", LE, (3.1.5 of ISO 1996)
# When applied to single event the sound exposure level is called single-event sound exposure level
SelFromLevels = function(L) {
  10*log10(sum(splToPressure(L)^2) / p0^2)
}

# Exceedance levels (Lx) represent the percent of the time that was measured above a certain level. For example, an L50 of 44 dB means that for 50% of the time, the level exceeded 44 dB.

# Calculate exceedance for the given percentage of time (0-100)
# https://www.larsondavis.com/ContentStore/mktg/LD_Manuals/831%20Manual.pdf
LxFromLevels = function(L, p = 50) {
  if (anyNA(L) | length(L) == 0) {
    warning('Missing data. Unable to calculate Lx')
    return(NA)
  }
  if (p <= 0 | p > 100) {
    warning('x given to Lx is invalid')
    return(NA)
  } else if (p == 100) {
    return(min(L) - 0.1) # 0.1 dB adjustment to establish exceedance
  }
  Lsorted = L[order(L, decreasing=TRUE)]
  i = max(floor(length(L) * p/100.0), 1)
  return(Lsorted[i] - 0.1)
}

# Hourly Leq for the given interval
# Can extrapolate hourly Leqs for partially missing data
LeqHourly = function(Levels, Times, start='00:00:00', end='23:59:59', extrapolate=TRUE) {
  date = format(Times[1], format=format_date)
  period = (Times >= as.POSIXct(paste(date,start), tz='UTC')
             & Times <= as.POSIXct(paste(date,end), tz='UTC'))
  
  # Subset only hours within the specified period (i.e. day, evening, or night)
  Levels = Levels[period]
  Times = Times[period]
  Leqh = tapply(X=Levels, INDEX=cut(Times, breaks='hour'), FUN=LeqTotal)
  
  # These hours have partial measurements (less than 3600 sec, but more than 0)
  hours_partial_data = tapply(X=Levels, INDEX=cut(Times, breaks='hour'), FUN=function(X){
    sum(is.na(X))<3600 & sum(is.na(X))>0
  })

  msg_partial_data = paste('Hour(s)', paste(format(as.POSIXct(names(which(hours_partial_data))), '%H')), 'have incomplete data.')
  for (hour in which(hours_partial_data)) {
    hour_start = as.POSIXct(names(hours_partial_data)[hour], tz='UTC')
    hour_levels = Levels[which(Times==hour_start):which(Times==(hour_start+3600-1))]
    
    # Extrapolate the hour's Leq as that of the measurements that are present
    if (extrapolate) {
      Leqh[hour] = LeqTotal(na.omit(hour_levels))
      msg_partial_data = paste(msg_partial_data, 'Extrapolated Leqs.')
    }
  }
  if (any(hours_partial_data)) {
    warning(msg_partial_data)
  }

  # Check if any hours are missing data entirely
  hours_missing_data = !hours_partial_data & is.na(Leqh)
  if (any(hours_missing_data)) {
    msg_missing_hrs = paste(format(as.POSIXct(names(which(hours_missing_data))), '%H'), collapse = ' ')
    warning(paste('Hour(s)', msg_missing_hrs, 'have no data. Unable to calculate Leq.'))
  }
  return(Leqh)
}

# NOTE: A standardized 24-hour time series window (by second) is expected for Ldn and Lden calculations.

# Day-night sound level, also known as DNL (ISO 1996). Returns a list including Ldn as well as intermediate calculations (Lday, Lnight, Leqh). Default level adjustment is night +10dB. United States FAA uses day values of [7am,10pm), night values of [10pm,7am)
LdnFromLevels = function(Levels, Times) {
  # browser()
  Leqh_night_am = LeqHourly(Levels, Times, '00:00:00', '06:59:59')
  Leqh_day      = LeqHourly(Levels, Times, '07:00:00', '21:59:59')
  Leqh_night_pm = LeqHourly(Levels, Times, '22:00:00', '23:59:59')
  Leqh_night = c(Leqh_night_am, Leqh_night_pm)
  Leqh = c(Leqh_night_am, Leqh_day, Leqh_night_pm)
  
  if (anyNA(Leqh)) {
    warning('Hourly Leq incomplete. Unable to calculate Ldn.')
  }

  Tday   = length(Leqh_day)
  Tnight = length(Leqh_night)
  Lday   = LeqTotal(Leqh_day)
  Lnight = LeqTotal(Leqh_night)
  # NOTE: +10dB adjustment for night hours
  Ldn = 10*log10((Tday*10^(Lday/10) + Tnight*10^((Lnight+10)/10))/24)
  
  return(list(
    'Ldn'    = Ldn,
    'Lday'   = Lday,
    'Lnight' = Lnight,
    'Leqh'   = Leqh
  ))
}

# Day-evening-night sound level, also known as DENL (ISO 1996). Returns a list including Ldn as well as intermediate calulations (Lday, Lnight, Leqh). Default time values are day [7am,7pm), evening [7pm,10pm), and night [10pm,7am). Default level adjustments are evening +5dB, night +10dB
# NOTE: The FAA uses "Community Noise Equivalent Level" (CNEL) in California, a metric similar to Lden, however the periods are day [7am,7pm), evening [7pm,10pm) with +4.77dB adjustment, and night [10pm,7am) with +10dB adjustment.
LdenFromLevels = function(Levels, Times) {
  Leqh_night_am = LeqHourly(Levels, Times, '00:00:00', '06:59:59')
  Leqh_day      = LeqHourly(Levels, Times, '07:00:00', '18:59:59')
  Leqh_evening  = LeqHourly(Levels, Times, '19:00:00', '21:59:59')
  Leqh_night_pm = LeqHourly(Levels, Times, '22:00:00', '23:59:59')
  Leqh_night = c(Leqh_night_am, Leqh_night_pm)
  Leqh = c(Leqh_night_am, Leqh_day, Leqh_evening, Leqh_night_pm)
  
  if (anyNA(Leqh)) {
    warning('Hourly Leq incomplete. Unable to calculate Ldn.')
  }
  
  Tday     = length(Leqh_day)
  Tevening = length(Leqh_evening)
  Tnight   = length(Leqh_night)
  Lday     = LeqTotal(Leqh_day)
  Levening = LeqTotal(Leqh_evening)
  Lnight   = LeqTotal(Leqh_night)
  
  # Day-evening-night sound level, calculated from continuous whole-day levels (ISO 1996, 3.6.4)
  # NOTE: +5dB adjustment for evening, +10dB for night
  Lden = 10*log10((Tday*10^(Lday/10) + Tevening*10^((Levening+5)/10) + Tnight*10^((Lnight+10)/10))/24)
  
  return(list(
    'Lden'     = Lden,
    'Lday'     = Lday,
    'Levening' = Levening,
    'Lnight'   = Lnight,
    'Leqh'     = Leqh
  ))
}

CnelFromLevels = function(Levels, Times) {
  Leqh_night_am = LeqHourly(Levels, Times, '00:00:00', '06:59:59')
  Leqh_day      = LeqHourly(Levels, Times, '07:00:00', '18:59:59')
  Leqh_evening  = LeqHourly(Levels, Times, '19:00:00', '21:59:59')
  Leqh_night_pm = LeqHourly(Levels, Times, '22:00:00', '23:59:59')
  Leqh_night = c(Leqh_night_am, Leqh_night_pm)
  Leqh = c(Leqh_night_am, Leqh_day, Leqh_evening, Leqh_night_pm)
  
  if (anyNA(Leqh)) {
    warning('Hourly Leq incomplete. Unable to calculate Ldn.')
  }
  
  Tday     = length(Leqh_day)
  Tevening = length(Leqh_evening)
  Tnight   = length(Leqh_night)
  Lday     = LeqTotal(Leqh_day)
  Levening = LeqTotal(Leqh_evening)
  Lnight   = LeqTotal(Leqh_night)
  # NOTE: +4.77dB adjustment for evening, +10dB for night
  Cnel = 10*log10((Tday*10^(Lday/10) + Tevening*10^((Levening+4.77)/10) + Tnight*10^((Lnight+10)/10))/24)
  
  return(list(
    'Cnel'     = Cnel,
    'Lday'     = Lday,
    'Levening' = Levening,
    'Lnight'   = Lnight,
    'Leqh'     = Leqh
  ))
}

# Day-evening-night sound level, calculated as composite whole-day rating level for single events
# (ISO 1996, 6.5)
lden_composite = function() {
  LR = 10*log10(sum(10^(SELi/10))/n)
  Kd = 0
  Ke = 5
  Kn = 10
  Lden_Le = 10*log10((d/24)*(10^((LRd+Kd)/10))+
                       (e/24)*(10^((LRe+Ke)/10))+
                       (24-d-e/24)*(10^((LRn+Kn)/10)))
}

# See page 43 https://www.navfac.navy.mil/Portals/68/Documents/Business-Lines/Asset-Management/Sound/Read-Me-Files/Technical_Report_Real-time_Aircraft_Sound_Monitoring_FINAL.pdf?ver=11ABujLRXHVyNY9tGQNZsA%3d%3d
dnl_composite = function() {
  dnl = 10*log10((15/24)*(1/54000)*sum(10^(SELsDay/10))) +
    10*log10( (9/24)*(1/32400)*sum(10^(SELsNight/10)))
}
