# Test 9: /U and reinstall, reload on the same port (no detection), reload on the other port. -p AB
waittext >
waitidle 1
type B:FREE\n
waitidle 2
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
type B:FREE\n
waitidle 2
screen -
type CLS\n
waitidle 1
type B:EL /U\n
waittext EL=
waitidle 1
type B:FREE\n
waitidle 2
screen -
peek cc 4
peek 104 4
peek e0001 1
type CLS\n
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
print reload same port, no feeder
type B:EL /SA\n
waittext Resident
print reset message seen
waitidle 1
type B:FREE\n
waitidle 2
screen -
type CLS\n
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_b) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SB\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
type B:FREE\n
waitidle 2
type b:v9kmt\n
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
peek 104 4
peek e0001 1
exit
