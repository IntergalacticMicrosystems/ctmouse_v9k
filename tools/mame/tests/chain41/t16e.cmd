# Baseline: A41 alone (no CTMOUSEV) receives 1360 text bytes on pty A.
waittext >
waitidle 1
type B:A41\n
waitidle 2
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 120
# the pty is drained into MAME long before the 7201 has clocked it in: 1360 bytes = 11.3 s
wait 14
type B:A41 S\n
waitidle 2
sh cat @RUN@/sendA.log
screen -
peek e0042 1
items :7l
items :16e
items :16e:cha
items :16e:chb
exit
