# bit-7 check: one move 1 0 at the DOS prompt, peek the resident pos/mickeys
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
watchr e0040 1
print TEXT
sh (printf 'move 1 0\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 0.5
peek 2ce0 100
sh (printf 'move 1 0\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 0.5
peek 2ce0 100
unwatch
type B:\n
waitidle 1
type GETSCRN\n
waitidle 1
type PICASSO\n
wait 35
peek f0000 4
peek 2ce0 100
exit
