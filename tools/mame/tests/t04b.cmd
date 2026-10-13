# Burst (gap 0, 40 x move 4 -3 = +160,-120 exact, no acceleration), --burst 60, then motion during DIR
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
type B:V9KMT\n
waittext P=
wait 1
type l
sh (@FEED@ --gap 0 --script @REPO@/tools/mame/tests/s04burst.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 2
type l
sh (@FEED@ --burst 60 --seed 5 --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 2
type l
type q
waitidle 1
screen -
type CLS\n
waitidle 1
sh (@FEED@ --gap 0 --script @REPO@/tools/mame/tests/s16dir.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
type DIR B:\n
waitidle 1
type DIR A:\n
waitidle 1
waitfile @RUN@/flag_3
wait 1
screen -
type CLS\n
waitidle 1
type B:V9KMT - q\n
waittext P=
waitidle 1
screen -
exit
