# Tests 3 and 4: scripted moves/clicks (s03.txt), then --garbage + s04.txt resync, then --burst 20
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:CTMV9K /SA\n
waittext Installed
sh kill $(cat @RUN@/feed.pid)
waitidle 1
type CLS\n
waitidle 1
type B:V9KMT\n
waittext P=
wait 1
type l
print feed s03
sh (@FEED@ --script @REPO@/tools/mame/tests/s03.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
print feed garbage
sh (@FEED@ --garbage 40 --seed 1 --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s04.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 1
type l
print feed burst
sh (@FEED@ --burst 20 --seed 2 --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 2
type l
type q
waitidle 1
screen -
exit
