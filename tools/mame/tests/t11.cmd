# Test 11: V9KMT n (fn 7 -50..900, fn 8 -50..500), large motion both ways, fn 4 to 0,0 and 799,399
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
type CLS\n
waitidle 1
type B:V9KMT n\n
waittext P=
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s11a.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s11b.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 2
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s11c.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 2
type l
type 4
wait 0.5
sh (@FEED@ --script @REPO@/tools/mame/tests/s11a.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 1
type l
type q
waitidle 1
screen -
type DIR B:\n
waitidle 2
screen -
exit
