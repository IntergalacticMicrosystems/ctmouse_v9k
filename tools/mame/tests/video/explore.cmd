# exploration: install, start PICASSO, snapshot
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:CTMV9K /SA\n
waittext Installed
sh kill $(cat @RUN@/feed.pid)
waitidle 1
screen -
peek cc 4
type B:\n
waitidle 1
type GETSCRN\n
waitidle 1
screen -
type PICASSO\n
wait 30
snap
wait 30
snap
wait 60
snap
items :11a
peek f0000 10
screen -
exit
