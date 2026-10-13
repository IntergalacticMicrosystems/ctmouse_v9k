# Test 9b: install on A, reload on B (feeder on B), then motion on B moves, motion on A does not. -p AB
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
sh @FEED@ --hello M --port $(cat @RUN@/pty_b) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SB\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
screen -
peek 104 4
peek e0001 1
type CLS\n
waitidle 1
type B:V9KMT\n
waittext P=
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s09.txt --port $(cat @RUN@/pty_b) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s09.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 1
type l
type q
waitidle 1
screen -
exit
