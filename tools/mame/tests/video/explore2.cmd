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
sh (printf 'move 1 0\nmove 2 0\nmove 0 2\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 0.3
peek 2ce0 100
sh (printf 'move -1000 -1000\nmove 115 20\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 0.3
peek 2ce0 100
snap
sh (printf 'press L\nsleep 300\nmove 0 20\nmove 0 20\nmove 0 20\nmove 0 20\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 1
peek 2ce0 100
snap
sh (printf 'move 0 40\nmove 0 40\nmove 0 40\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 1
snap
peek 2ce0 100
exit
