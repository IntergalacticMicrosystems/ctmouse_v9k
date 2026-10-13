# exploration 2: PICASSO resident state, mickey step, File menu
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:CTMV9K /SA\n
waittext Installed
sh kill $(cat @RUN@/feed.pid)
waitidle 1
peek cc 4
peek 2ce0 100
type B:\n
waitidle 1
type GETSCRN\n
waitidle 1
items :16e:cha
watchw e0020 4
watchw e0040 4
watchw e0000 2
watchw 2d48 b8
type PICASSO\n
wait 35
peek f0000 4
peek 2ce0 100
unwatch
items :16e:cha
watchw 2d48 b8
watchw e0040 4
sh (printf 'move 1 0\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 0.5
peek 2ce0 100
exit
