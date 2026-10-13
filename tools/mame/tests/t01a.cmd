# Test 1 (port A): install with --hello M, then V9KMT signature / fn 24h / fn 4Dh
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:CTMOUSEV /SA\n
waittext Installed
sh kill $(cat @RUN@/feed.pid)
waitidle 1
type B:V9KMT q\n
waittext P=
waitidle 1
screen -
peek 104 4
peek e0001 1
exit
