# Test 14: driver on A, HK41 hooks INT 41h after us, CTMOUSEV /U -> unload failed, EL 2, vectors/IMR unchanged
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:EL /SA\n
waittext EL=
sh kill $(cat @RUN@/feed.pid)
waitidle 1
peek cc 4
peek 104 4
peek e0001 1
type b:hk41\n
waittext HK41 resident
waitidle 1
screen -
peek cc 4
peek 104 4
peek e0001 1
type CLS\n
waitidle 1
type B:EL /U\n
waittext EL=
waitidle 1
screen -
peek cc 4
peek 104 4
peek e0001 1
type CLS\n
waitidle 1
type B:V9KMT\n
waittext P=
wait 1
type l
sh (@FEED@ --script @REPO@/tools/mame/tests/s09.txt --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 1
type l
type q
waitidle 1
screen -
exit
