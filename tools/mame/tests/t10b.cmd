# Test 10: t10b: --hello MZ, CTMV9K /SA, feeder proto mz, scripts[:held]: s10_w3.txt s10_wm2.txt s10_pm.txt s10_rm.txt:M s10_pl.txt s10_rl.txt:L
waittext >
waitidle 1
sh @FEED@ --hello MZ --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
screen -
type CLS\n
waitidle 1
type B:V9KMT w\n
waittext P=
wait 1
type l
print feed s10_w3.txt
sh (@FEED@ -v --proto mz --script @REPO@/tools/mame/tests/s10_w3.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
print feed s10_wm2.txt
sh (@FEED@ -v --proto mz --script @REPO@/tools/mame/tests/s10_wm2.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 1
type l
print feed s10_pm.txt
sh (@FEED@ -v --proto mz --script @REPO@/tools/mame/tests/s10_pm.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 1
type l
print feed s10_rm.txt:M
sh (@FEED@ -v --proto mz --held M --script @REPO@/tools/mame/tests/s10_rm.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 1
type l
print feed s10_pl.txt
sh (@FEED@ -v --proto mz --script @REPO@/tools/mame/tests/s10_pl.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_5) &
waitfile @RUN@/flag_5
wait 1
type l
print feed s10_rl.txt:L
sh (@FEED@ -v --proto mz --held L --script @REPO@/tools/mame/tests/s10_rl.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_6) &
waitfile @RUN@/flag_6
wait 1
type l
type w
type q
waitidle 1
screen -
exit
