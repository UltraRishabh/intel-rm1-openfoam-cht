log = "logs/log.chtMultiRegionSimpleFoam"

# Extracts the final outer-corrector max temperature for a given region per iteration
temp(region) = sprintf("< awk '/^Time =/{t=$3; v=\"\"} /Solving for .* region/{r=$5} /^Min\\/max T:/{if(r==\"%s\") v=$3} /^ExecutionTime /{if(v!=\"\") print t, v}' %s", region, log)

set term qt noraise
set xlabel "Iteration"
set ylabel "Max Temperature [K]"
set grid
set key outside right

plot temp("die")   u 1:2 w l lw 2 lc rgb "#d62728" t "Die", \
     temp("ihs")   u 1:2 w l lw 2 lc rgb "#ff9896" t "IHS", \
     temp("core")  u 1:2 w l lw 2 lc rgb "#ff7f0e" t "Core", \
     temp("fins")  u 1:2 w l lw 2 lc rgb "#2ca02c" t "Fins", \
     temp("fluid") u 1:2 w l lw 2 lc rgb "#1f77b4" t "Fluid"

while (1) {
    pause 5
    replot
}
