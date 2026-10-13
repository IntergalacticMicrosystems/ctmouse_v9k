# Baseline: A41 alone (no CTMV9K) receives 1360 text bytes on pty A.
waittext >
waitidle 1
type B:A41\n
waitidle 2
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 120
wait 2
type B:A41 S\n
waitidle 2
sh cat @RUN@/sendA.log
peek e0042 1
items :7l
exit
