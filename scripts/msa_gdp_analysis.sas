/* ============================================================
   Project  : MSA GDP Growth & Unemployment Rate Gap Analysis
   Author   : Matthew Ong
   Updated  : April 28, 2026
   Description:
       Imports MSA-level GDP and labor market data, computes
       GDP growth metrics (CAGR, volatility), ranks MSAs, and 
	   produces panel plots of racial unemployment rate gaps
       for top 10 and bottom 10 MSAs by GDP growth performance.
   ============================================================ */


/* ------------------------------------------------------------ 
   0. LIBRARY & DATA IMPORT
   ------------------------------------------------------------ */

	/* This analysis requires three datasets available under 
     data_tables –> sas_import in my GitHub. 
     After setting a Libname and loading these datasets, 
     you may proceed with the script. */

/* MSA-County crosswalk reference */
proc import
    datafile = "\\Msa_county_reference.csv"
    out      = work.msa_ref
    dbms     = csv
    replace;
    getnames = yes;
run;

/* Main MSA labor market data */
proc import
    datafile = "\\msa_data.csv"
    out      = work.msa_data
    dbms     = csv
    replace;
    getnames  = yes;
    guessingrows = max;
run;

/* Raw MSA GDP data */
proc import
    datafile = "\\msa_gdp_raw.csv"
    out      = work.msa_gdp_raw
    dbms     = csv
    replace;
    getnames  = yes;
    guessingrows = max;
run;


/* ------------------------------------------------------------ 
   1. GDP DATA PROCESSING
   ------------------------------------------------------------ */

/* Keep only LineCode = 2 (real GDP) */
data work.msagdp2;
    set work.msa_gdp_raw;
    where LineCode = 2;
run;

/* Transpose from wide (year columns) to long format */
proc transpose data=work.msagdp2
               out=work.msagdp3;
    by fips;
    var _2009-_2023;
run;

/* Clean transposed data: parse year and GDP value */
data work.msagdp3;
    set work.msagdp3;
    year = input(substr(_name_, 2), 4.);
    if col1 in ("NA", "(NA)", "NM", "(NM)") then gdp = .;
    else gdp = input(compress(col1, ', $()'), best32.);
    drop _name_ col1;
run;

/* Merge with MSA reference crosswalk */
proc sql;
    create table work.msagdp4 as
    select
        a.msa,
        a.name_msa,
        b.*
    from work.msa_ref as a
    inner join work.msagdp3 as b
        on a.fips = b.fips;
quit;


/* ------------------------------------------------------------ 
   2. GDP GROWTH METRICS
   ------------------------------------------------------------ */

/* Aggregate GDP to MSA level, then compute year-over-year growth */
proc sql;
    create table work.msa_gdp_perc as
    select
        msa,
        max(name_msa) as name_msa,
        year,
        sum(gdp) as msa_gdp
    from work.msagdp4
    group by msa, year;
quit;

proc sort data=work.msa_gdp_perc;
    by msa year;
run;

data work.msa_gdp_perc;
    set work.msa_gdp_perc;
    by msa;
    retain lag_gdp;
    if first.msa then lag_gdp = .;
    else gdp_growth = (msa_gdp - lag_gdp) / lag_gdp;
    lag_gdp = msa_gdp;
run;

/* Compute CAGR (Compound Annual Growth Rate) 2009 to 2023 */
data msa_levels;
    set work.msa_gdp_perc;
    by msa;
    retain gdp_start;
    if first.msa then gdp_start = msa_gdp;
    if last.msa then do;
        gdp_end = msa_gdp;
        output;
    end;
    keep msa name_msa gdp_start gdp_end;
run;

data msa_levels;
    set msa_levels;
    T = 2023 - 2009;
    if gdp_start > 0 then
        CAGR = (gdp_end / gdp_start)**(1/T) - 1;
run;

/* Compute volatility (std dev of annual growth rates, 2010 to 2023) */
proc sql;
    create table msa_vol as
    select
        msa,
        std(gdp_growth) as volatility
    from work.msa_gdp_perc
    where year >= 2010
    group by msa;
quit;

/* Combine CAGR and volatility; compute score = CAGR / Volatility */
proc sql;
    create table msa_gdp_metrics as
    select
        a.msa,
        a.name_msa,
        a.CAGR,
        b.volatility
    from msa_levels as a
    left join msa_vol as b
        on a.msa = b.msa;
quit;

data msa_gdp_metrics;
    set msa_gdp_metrics;
    if volatility > 0 then
        score = CAGR / volatility;
run;


/* ------------------------------------------------------------ 
   3. RANK MSAs BY SCORE
   ------------------------------------------------------------ */

proc sort data=msa_gdp_metrics;
    by descending score;
run;

data msa_gdp_ranked;
    set msa_gdp_metrics;
    rank = _N_;
run;

/* Convert MSA to numeric variable */
data work.msa_gdp_ranked;
    set work.msa_gdp_ranked;
    msa_num = input(strip(msa), best32.);
    drop msa;
    rename msa_num = msa;
run;

/* Create rank label for plots */
data msa_gdp_ranked;
    set msa_gdp_ranked;
    msa_rank_label = catx(' ', 'Rank', put(rank, 3.), ': ', name_msa);
run;

/* Convert MSA to numeric in growth table */
data work.msa_gdp_perc;
    set work.msa_gdp_perc;
    msa_num = input(strip(msa), best32.);
    drop msa;
    rename msa_num = msa;
run;


/* ------------------------------------------------------------ 
   4. MASTER DATASET
   ------------------------------------------------------------ */

proc sql;
    create table work.master_cleaned as
    select
        a.*,
        b.rank,
        b.msa_rank_label,
        c.gdp_growth
    from work.msa_data as a
    inner join msa_gdp_ranked as b
        on a.msa = b.msa
    left join work.msa_gdp_perc as c
        on a.msa = c.msa
       and a.year = c.year
    where a.year between 2010 and 2023;
quit;

proc sort data=work.master_cleaned;
    by rank year;
run;


/* ------------------------------------------------------------ 
   5. TOP 10 / BOTTOM 10 GROUP ANALYSIS
   ------------------------------------------------------------ */

/* Get total number of ranked MSAs */
proc sql noprint;
    select max(rank) into :max_rank
    from msa_gdp_ranked;
quit;

/* Tag top 10 and bottom 10 MSAs */
data work.msa_groups;
    set msa_gdp_ranked;
    if rank <= 10 then group = "Top 10   ";
    else if rank > &max_rank - 10 then group = "Bottom 10";
    else delete;
    keep msa rank group name_msa;
run;

proc sql;
    create table work.top10_table as
    select
        a.name_msa,
        a.rank,
        b.CAGR,
		b.volatility,
        b.score
    from work.msa_groups as a
    inner join msa_gdp_metrics as b
        on a.name_msa = b.name_msa
	where group = "Top 10   "
    order by rank;
quit;

proc sql;
    create table work.bottom10_table as
    select
        a.name_msa,
        a.rank,
        b.CAGR,
		b.volatility,
        b.score
    from work.msa_groups as a
    inner join msa_gdp_metrics as b
        on a.name_msa = b.name_msa
	where group = "Bottom 10   "
    order by rank;
quit;

/* Merge group labels into master */
proc sql;
    create table work.master_grouped as
    select
        a.*,
        b.group
    from work.master_cleaned as a
    inner join work.msa_groups as b
        on a.msa = b.msa;
quit;

/* Compute average UR gaps by group and year */
proc sql;
    create table work.avg_ur_gaps as
    select
        group,
        year,
        mean(gap_mbw) as avg_gap_mbw,
        mean(gap_mhw) as avg_gap_mhw,
        mean(gap_fbw) as avg_gap_fbw,
        mean(gap_fhw) as avg_gap_fhw
    from work.master_grouped
    group by group, year;
quit;


/* ------------------------------------------------------------ 
   6. PLOT EXPORT MACRO
   ------------------------------------------------------------ */

/* Usage: %save_png(filename, width, height, plot_code)
   Opens ODS listing to the output path, sets image name/size,
   runs whatever plot code is passed in, then closes ODS.        */

%let outpath = /* file path */ ;

%macro save_png(filename, width=9in, height=5in);
    ods listing gpath="&outpath" style=htmlblue;
    ods graphics / reset width=&width height=&height
                   imagename="&filename" outputfmt=png;
    %mend _open;
%mend save_png;

%macro export_png(filename, width=9in, height=5in);
    ods listing gpath="&outpath" style=htmlblue;
    ods graphics / reset width=&width height=&height
                   imagename="&filename" outputfmt=png;
%mend export_png;

%macro close_png();
    ods listing close;
%mend close_png;


/* ------------------------------------------------------------ 
   7. PANEL PLOTS: TOP 10 vs BOTTOM 10
   ------------------------------------------------------------ */

/* Graph 1: Male UR Gaps */
%export_png(MSA_male_ur_gaps, width=11in, height=5in);
proc sgpanel data=work.avg_ur_gaps;
    panelby group / columns=2 novarname;
    refline 0 / axis=y lineattrs=(color=black thickness=1 pattern=solid);
    series x=year y=avg_gap_mbw / name="mbw" legendlabel="Black-White Male"
        lineattrs=(thickness=2 color=navy);
    series x=year y=avg_gap_mhw / name="mhw" legendlabel="Hispanic-White Male"
        lineattrs=(thickness=2 color=darkred pattern=ShortDash);
    keylegend "mbw" "mhw" / position=bottom;
    rowaxis label="Avg Unemployment Rate Gap (pp)";
    colaxis label="Year" values=(2010 to 2023 by 1);
    title "Male Unemployment Rate Gaps: Top 10 vs Bottom 10 MSAs by GDP Growth";
run;
%close_png();

/* Graph 2: Female UR Gaps */
%export_png(MSA_female_ur_gaps, width=11in, height=5in);
proc sgpanel data=work.avg_ur_gaps;
    panelby group / columns=2 novarname;
    refline 0 / axis=y lineattrs=(color=black thickness=1 pattern=solid);
    series x=year y=avg_gap_fbw / name="fbw" legendlabel="Black-White Female"
        lineattrs=(thickness=2 color=purple);
    series x=year y=avg_gap_fhw / name="fhw" legendlabel="Hispanic-White Female"
        lineattrs=(thickness=2 color=darkorange pattern=ShortDash);
    keylegend "fbw" "fhw" / position=bottom;
    rowaxis label="Avg Unemployment Rate Gap (pp)";
    colaxis label="Year" values=(2010 to 2023 by 1);
    title "Female Unemployment Rate Gaps: Top 10 vs Bottom 10 MSAs by GDP Growth";
run;
%close_png();


/* ------------------------------------------------------------ 
   8. SINGLE MSA DEEP DIVE: Kansas City (MSA 28140)
   ------------------------------------------------------------ */

proc sql;
    create table work.msa_28140 as
    select *
    from work.master_cleaned
    where msa = 28140;
quit;

/* Graph 1: Male UR Gaps */
%export_png(msa28140_male_ur_gaps);
proc sgplot data=work.msa_28140;
    refline 0 / axis=y lineattrs=(color=black thickness=1 pattern=solid);
    series x=year y=gap_mbw / name="mbw" legendlabel="Black-White Male"
        lineattrs=(thickness=2 color=navy);
    series x=year y=gap_mhw / name="mhw" legendlabel="Hispanic-White Male"
        lineattrs=(thickness=2 color=darkred pattern=ShortDash);
    keylegend "mbw" "mhw" / position=bottom;
    yaxis label="Unemployment Rate Gap (pp)";
    xaxis label="Year" values=(2010 to 2023 by 1);
    title "Male Unemployment Rate Gaps: MSA 28140 (Kansas City)";
run;
%close_png();

/* Graph 2: Female UR Gaps */
%export_png(msa28140_female_ur_gaps);
proc sgplot data=work.msa_28140;
    refline 0 / axis=y lineattrs=(color=black thickness=1 pattern=solid);
    series x=year y=gap_fbw / name="fbw" legendlabel="Black-White Female"
        lineattrs=(thickness=2 color=purple);
    series x=year y=gap_fhw / name="fhw" legendlabel="Hispanic-White Female"
        lineattrs=(thickness=2 color=darkorange pattern=ShortDash);
    keylegend "fbw" "fhw" / position=bottom;
    yaxis label="Unemployment Rate Gap (pp)";
    xaxis label="Year" values=(2010 to 2023 by 1);
    title "Female Unemployment Rate Gaps: MSA 28140 (Kansas City)";
run;
%close_png();


/* ------------------------------------------------------------ 
   8. EXPORT RESULTS
   ------------------------------------------------------------ */

%macro export_csv(data=, file=);
    proc export data=&data
        outfile="\\" /* file path */
        dbms=csv replace;
        putnames=yes;
    run;
%mend export_csv;

%export_csv(data=work.msa_gdp_ranked, file=msa_gdp_ranked.csv);
%export_csv(data=work.master_cleaned,  file=master_cleaned.csv);
%export_csv(data=work.msa_groups,  file=msa_groups.csv);



/* ------------------------------------------------------------ 
   TOP MSA METRICS TABLEs � PNG Export via ODS PDF
   ------------------------------------------------------------ */

ods pdf file="&outpath.\top10_msa_metrics_table.pdf" style=htmlblue;
proc report data=work.top10_table nowd;
    columns name_msa rank CAGR volatility score;
    define name_msa  / display "MSA Name"   width=35;
    define rank      / display "Rank"        width=6;
    define CAGR      / display "CAGR"        format=percent8.2;
    define volatility/ display "Volatility"  format=8.4;
    define score     / display "Score"       format=8.4;
    title "Top 10 MSAs by GDP Growth Score";
run;
ods pdf close;

ods pdf file="&outpath.\bottom10_msa_metrics_table.pdf" style=htmlblue;
proc report data=work.bottom10_table nowd;
    columns name_msa rank CAGR volatility score;
    define name_msa  / display "MSA Name"   width=35;
    define rank      / display "Rank"        width=6;
    define CAGR      / display "CAGR"        format=percent8.2;
    define volatility/ display "Volatility"  format=8.4;
    define score     / display "Score"       format=8.4;
    title "Bottom 10 MSAs by GDP Growth Score";
run;
ods pdf close;

/* ------------------------------------------------------------ 
   KANSAS CITY (MSA 28140) METRICS TABLE � PDF Export
   ------------------------------------------------------------ */
proc sql;
    create table work.kc_table as
    select name_msa, msa, rank, CAGR, volatility, score
    from work.msa_gdp_ranked
    where msa = 28140;
quit;

ods pdf file="&outpath.\kc_msa_metrics_table.pdf" style=htmlblue;
proc report data=work.kc_table nowd;
    columns name_msa msa rank CAGR volatility score;
    define name_msa   / display "MSA Name"   width=35;
    define msa        / display "MSA Code"   width=8;
    define rank       / display "Rank"       width=6;
    define CAGR       / display "CAGR"       format=percent8.2;
    define volatility / display "Volatility" format=8.4;
    define score      / display "Score"      format=8.4;
    title "Kansas City MSA (28140) � GDP Growth Metrics";
run;
ods pdf close;
