# MSA GDP Growth & Unemployment Rate Gap Analysis
 
**Author** Matthew Ong
**Date** April 28, 2026
 
## Overview
 
This project analyzes Metropolitan Statistical Area (MSA) GDP growth and racial unemployment rate gaps across U.S. metro areas between 2010 and 2023. MSAs are ranked by a composite score (CAGR / Volatility), and labor market disparities are compared between the top and bottom 10 performers.
 
## Methodology
 
### GDP Performance Score
Each MSA is scored using:
 
$$\text{Score} = \frac{\text{CAGR}}{\text{Volatility}}$$
 
Where:
- **CAGR** = Compound Annual Growth Rate from 2009 to 2023
- **Volatility** = Standard deviation of annual GDP growth rates (2010–2023)
Higher scores indicate stronger, more stable growth.
This method helps to eliminate business-cycle bias that creates volatility, especially for smaller MSAs.
 
### Unemployment Rate Gaps
Gaps are defined as the difference in unemployment rates between racial/ethnic groups and white workers:
- `gap_mbw` — Black minus White, Male  
- `gap_mhw` — Hispanic minus White, Male  
- `gap_fbw` — Black minus White, Female  
- `gap_fhw` — Hispanic minus White, Female  
## Data Sources
 
| File | Description |
|------|-------------|
| `Msa_county_reference.xlsx` | MSA–county FIPS crosswalk |
| `msa_data.csv` | MSA-level unemployment data. Source: U.S. Census
Bureau |
| `msagdp_raw.csv` | BEA MSA GDP data (LineCode = 2, real GDP). Source BEA's CAGDP1: County and Metropolitan Area Gross Domestic Product (GDP) Summary |
 
