# Test 10: t10c: --hello M, CTMOUSEV /SA /3 /L, feeder proto ms3, scripts[:held]: s10_pm.txt s10_mv.txt:M s10_rm.txt:M s10_pl.txt s10_rl.txt:L
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA /3 /L\n
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
print feed s10_pm.txt
sh (@FEED@ -v --proto ms3 --script @REPO@/tools/mame/tests/s10_pm.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
print feed s10_mv.txt:M
sh (@FEED@ -v --proto ms3 --held M --script @REPO@/tools/mame/tests/s10_mv.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 1
type l
print feed s10_rm.txt:M
sh (@FEED@ -v --proto ms3 --held M --script @REPO@/tools/mame/tests/s10_rm.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 1
type l
print feed s10_pl.txt
sh (@FEED@ -v --proto ms3 --script @REPO@/tools/mame/tests/s10_pl.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 1
type l
print feed s10_rl.txt:L
sh (@FEED@ -v --proto ms3 --held L --script @REPO@/tools/mame/tests/s10_rl.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_5) &
waitfile @RUN@/flag_5
wait 1
type l
type w
type q
waitidle 1
screen -
exit
