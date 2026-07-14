log = "logs/log.chtMultiRegionSimpleFoam"

extract(fld,reg) = sprintf("< awk '/^Time =/{t=$3; delete s} /^Solving for (fluid|solid) region/{r=$5} /Solving for %s,.*Initial/{if(r==\"%s\" && !s[r]){s[r]=1; for(i=1;i<=NF;i++) if($i==\"Initial\"){v=$(i+3); sub(/,$/,\"\",v)}; print t, v}}' %s", fld, reg, log)

extract_cont(reg) = sprintf("< awk '/^Time =/{t=$3; delete c} /^Solving for (fluid|solid) region/{r=$5} /continuity errors/{if(r==\"%s\" && !c[r]){c[r]=1; for(i=1;i<=NF;i++) if($i==\"cumulative\"){v=$(i+2); sub(/,$/,\"\",v); print t, v}}}' %s", reg, log)

set logscale y
set term qt noraise
set xlabel "Iteration"
set ylabel "Initial residual / Continuity error"
set grid
set key outside right

plot extract("Uy","fluid")    u 1:2 w l t "Ux (fluid)", \
     extract("p_rgh","fluid") u 1:2 w l t "p_rgh (fluid)", \
     extract("h","fluid")     u 1:2 w l t "h (fluid)", \
     extract("h","die")       u 1:2 w l t "h (die)", \
     extract("h","ihs")       u 1:2 w l t "h (ihs)", \
     extract("h","core")      u 1:2 w l t "h (core)", \
     extract("h","fins")      u 1:2 w l t "h (fins)", \
     extract_cont("fluid")    u 1:(abs($2)) w l t "cont. error (fluid)"

while (1) {
    pause 5
    replot
}
