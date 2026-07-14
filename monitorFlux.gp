log = "logs/log.chtMultiRegionSimpleFoam"

flux(patch) = sprintf("< awk '/^Time =/{t=$3} /integ\\(%s\\)/{n=split($0,a,\",\"); v=a[3]; gsub(/[ \\t]/,\"\",v); print t, v}' %s", patch, log)

set term qt noraise
set xlabel "Iteration"
set ylabel "|integ flux|  [W]"
set grid
set key outside right

plot flux("die_to_ihs")   u 1:(abs($2)) w l lw 2 lc rgb "#1f77b4" t "die\\_to\\_ihs", \
     flux("ihs_to_die")   u 1:(abs($2)) w l lw 2 lc rgb "#aec7e8" t "ihs\\_to\\_die", \
     flux("ihs_to_core")  u 1:(abs($2)) w l lw 2 lc rgb "#d62728" t "ihs\\_to\\_core", \
     flux("core_to_ihs")  u 1:(abs($2)) w l lw 2 lc rgb "#ff9896" t "core\\_to\\_ihs", \
     flux("core_to_fins") u 1:(abs($2)) w l lw 2 lc rgb "#2ca02c" t "core\\_to\\_fins", \
     flux("fins_to_core") u 1:(abs($2)) w l lw 2 lc rgb "#98df8a" t "fins\\_to\\_core", \
     flux("fins_to_fluid")u 1:(abs($2)) w l lw 2 lc rgb "#9467bd" t "fins\\_to\\_fluid", \
     flux("fluid_to_fins")u 1:(abs($2)) w l lw 2 lc rgb "#c5b0d5" t "fluid\\_to\\_fins", \
     flux("die_bottom")   u 1:(abs($2)) w l lw 1 dt 2 lc rgb "black" t "die\\_bottom (src)"

while (1) {
    pause 5
    replot
}
