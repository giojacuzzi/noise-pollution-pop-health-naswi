# Exposure-response functions for health impact relationships

## Annoyance ------------------------------------------------------------------------------
# See ISO 1996-1 2016 Annex E/F and Lct

# ISO 1996
# (3.2.2): Long-term time interval - Specified time interval over which the sound of series of reference time intervals is averaged or assessed; The long-term time interval is determined for the purpose of describing environmental noise as it is generally designated by responsible authorities; For long-term assessments and land-use planning long-term time intervals that represent some significant fraction of year should be used (e.g 3 months, 6 months, and 1 year)
# 
# (8.1): Estimation of long-term annoyance response of communities - Noise assessments representing a long-term time interval, typically year, are used to estimate the annoyance  response of communities to the overall, steady sound situation. Annex E or Annex F (Gio: we are using Annex F, a dose-response regression) should be sued to estimate the long-term annoyance of communities to airport, road-traffic, or railroad noise. Each of these two annexes provides estimates of the percentage of a typical population that is likely to be highly annoyed by that environmental noise due to a specific annual average adjusted day-night sound level.
# 
# (D.4): Qualifications to the dose-response functions - These formulae are applicable only to long-term environmental sounds such as the yearly average; These formulae should not be used with shorter time periods such as weekends single season or busy days, rather, the annual average or some other long-term period should be used; These formulae are not applicable to short-term environmental sound such as from an increase in road traffic due to short-duration construction project; These formulae are only applicable to existing situations
# 
# Note that the WHO guidelines for Ldn/Lden/Lday/Lnight are based on this same 1996 standard –– in their words, "an average sound pressure level over all days, evenings and nights in a year ".

# The percent predicted to be highly annoyed in relation to exposure to aircraft traffic noise. Based on the WHO regression equation %HA = −50.9693 + 1.0168 × Lden + 0.0072 × Lden^2 derived from the systematic review (Guski et al., 2017).
# TODO: should be only defined for Lden [40, 75]
exp_resp_WHO = function(Lden) {
  return(-50.9693 + 1.0168 * Lden + 0.0072 * Lden^2)
}
bounds_who = c(40,75)
exp_resp_WHO_bounded = function(Lden) {
  if (Lden < bounds_who[1]) {
    return(exp_resp_WHO(bounds_who[1]))
  } else if (Lden > bounds_who[2]) {
    return(exp_resp_WHO(bounds_who[2]))
  }
  return(exp_resp_WHO(Lden))
}

# Miedema and Oudshoorn 2001
exp_resp_MO = function(Lden) {
  return(-9.199 * 10^-5 * (Lden - 42)^3 + 3.932 * 10^-2 * (Lden - 42)^2 + 0.2939 * (Lden - 42))
}

# 1996-1 2016 / Fidell et al 2011
exp_resp_ISO_Fidell = function(Lden) {
  # Includes ISO recommended Lct of 71.3 dB to implement a 7 dB adjustment
  Lct = 71.3
  return(
    100 * exp(1)^(-(1/(10^(0.1*(Lden-Lct+4.7))))^0.3)
  )
}
exp_resp_ISO_Miedema = function(Lden) {
  # Includes ISO recommended 7 dB adjustment, based on Miedema curve
  return(-9.199 * 10^-5 * (Lden - 40)^3 + 3.932 * 10^-2 * (Lden - 40)^2 + 0.294 * (Lden - 40))
}
ci_iso_miedema = data.frame(
  Lden=  c(43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76),
  Lower= c(0.3,0.4,0.4,0.5,0.6,0.7,0.9,1.0,1.2,1.4,1.7,1.9,2.2,2.6,3.0,3.4,3.9,4.4,5.0,5.7,6.4,7.2,8.1,9.0,10.0,11.1,12.3,13.6,15.0,16.4,18.0,19.6,21.3,23.1),
  Upper= c(33.5,35.7,38.0,40.3,42.7,45.1,47.5,49.9,52.3,54.7,57.1,59.5,61.8,64.1,66.3,68.5,70.6,72.7,74.7,76.6,78.4,80.1,81.8,83.4,84.8,86.2,87.5,88.7,89.9,90.9,91.9,92.7,93.6,94.3)
)
bounds_iso_miedema = c(40,76)
exp_resp_ISO_Miedema_bounded = function(Lden) {
  if (Lden < bounds_iso_miedema[1]) {
    return(exp_resp_ISO_Miedema(bounds_iso_miedema[1]))
  } else if (Lden > bounds_iso_miedema[2]) {
    return(exp_resp_ISO_Miedema(bounds_iso_miedema[2]))
  }
  return(exp_resp_ISO_Miedema(Lden))
}

# Yokoshima et al 2021
exp_resp_Yokoshima = function(Lden) {
  return(-68.080 + 1.838 * Lden + 0.006 * Lden^2) # (R^2 = 0.994)
}
ci_Yokoshima = data=data.frame(
  Lden=  c(40,   45,  50,  55, 60, 65),
  Lower= c(8.1,  22.2, 33.7, 45.9, 58.8, 69.0),
  Upper= c(21.0, 30.1, 42.4, 54.6, 66.7, 82.0)
)
bounds_Yokoshima = c(40,65)
exp_resp_Yokoshima_bounded = function(Lden) {
  if (Lden < bounds_Yokoshima[1]) {
    return(exp_resp_Yokoshima(bounds_Yokoshima[1]))
  } else if (Lden > bounds_Yokoshima[2]) {
    return(exp_resp_Yokoshima(bounds_Yokoshima[2]))
  }
  return(exp_resp_Yokoshima(Lden))
}

## Annoyance ------------------------------------------------------------------------------
# TODO: Military-specific / low-frequency / onset / aircraft dB penalty adjustment?

# Smith et al 2022 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9272916/
# Restricted only to survey questions where noise was explicitly mentioned
exp_resp_HSD_awakenings = function(Lnight) {
  return(0.03132*(Lnight)^2 - 1.80203*(Lnight) + 31.28079)
}
exp_resp_HSD_fallingasleep = function(Lnight) {
  return(0.02204*(Lnight)^2 - 0.86230*(Lnight) + 12.42449)
}
exp_resp_HSD_sleepdisturbance = function(Lnight) {
  return(0.02664*(Lnight)^2 - 1.17389*(Lnight) + 16.46165)
}
exp_resp_HSD_combinedestimate = function(Lnight) {
  return(0.025015*(Lnight)^2 - 1.12624*(Lnight) + 17.074213)
}

ci_upper_HSD_combinedestimate = function(Lnight) {
  return(0.0221483*Lnight^2 - 0.5720120*Lnight + 3.5979810)
}
ci_lower_HSD_combinedestimate = function(Lnight) {
  return(0.027883*Lnight^2 - 1.680477*Lnight + 30.550446) 
}
ci_HSD_combinedestimate = data.frame(
  Lnight = seq(from=40, to=65, by=1),
  Lower  = ci_lower_HSD_combinedestimate(seq(from=40, to=65, by=1)),
  Upper  = ci_upper_HSD_combinedestimate(seq(from=40, to=65, by=1))
)
bounds_HSD = c(40,65)

exp_resp_HSD_combinedestimate_bounded = function(Lnight) {
  if (Lnight < bounds_HSD[1]) {
    return(exp_resp_HSD_combinedestimate(bounds_HSD[1]))
  } else if (Lnight > bounds_HSD[2]) {
    return(exp_resp_HSD_combinedestimate(bounds_HSD[2]))
  }
  return(exp_resp_HSD_combinedestimate(Lnight))
}

# NOTE: Limitations - "The rapid onset time in particular means that a given aircraft is probably more likely to induce an awakening than one that is much more gradual, like a civil aircraft. But of course physiological disturbance such as this and self-reported long-term %HSD are not the same thing, and do not necessarily correlate all that well."

# NOTE: Time scale for ERFs is long-term, typically one year, so single-date maximum Lnights are not appropriate. "Equivalent noise levels are often used in surveys and epidemiologic studies as long-term average exposure metrics, and are therefore also often found in legislative and policy contexts. For example, the Night Noise Guidelines for Europe of the World Health Organization (WHO) define effects of nocturnal noise based on annual average outdoor Lnight ranges. The value of equivalent noise levels in describing the effects of noise on sleep is more limited, as different noise scenarios may calculate to the same equivalent noise level, but differ substantially in their sleep disturbing properties. There is general agreement that the number and acoustical properties of single noise events better reflect the actual degree of nocturnal sleep disturbance in a single night. It is thus questionable whether Lnight can be used as the only indicator for predicting the effects of noise on sleep and the consequences of noise-induced sleep disturbance, or whether supplemental noise indicators are needed