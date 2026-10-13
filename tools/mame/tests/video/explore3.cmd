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
type PICASSO\n
wait 35
peek f0000 4
peek 2ce0 100
sh (printf 'move 1 0\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 0.5
print after move 1 0
peek 2ce0 100
sh sleep 1000 > $(cat @RUN@/pty_a) & echo $! > @RUN@/hold.pid
wait 1
print holder
peek 2ce0 100
sh (printf 'move 1 0\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 0.5
print after move 1 0
peek 2ce0 100
sh (printf 'move 0 2\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 0.5
print after move 0 2
peek 2ce0 100
sh (printf 'move 5 5\n' | @FEED@ -v --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 0.5
print after move 5 5
peek 2ce0 100
sh kill $(cat @RUN@/hold.pid)
snap
exit
