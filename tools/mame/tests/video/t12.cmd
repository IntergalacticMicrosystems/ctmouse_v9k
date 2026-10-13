# Test 12: mode change with the cursor visible (text -> PICASSO graphics -> text), then fn 0 + show.
# Driver-segment writes to screen RAM (F0000-F0FFF) and all CRTC writes are logged (watchw);
# analyze_t12.py checks them against the R12 mode at that time.
waittext >
waitidle 1
sh @FEED@ --hello M --port $(cat @RUN@/pty_a) > @RUN@/feed.log 2>&1 & echo $! > @RUN@/feed.pid
wait 0.5
type B:CTMOUSEV /SA\n
waittext Installed
sh kill $(cat @RUN@/feed.pid)
waitidle 1
peek cc 4
type CLS\n
waitidle 1
type B:V9KMT sq\n
waittext fn 01 AX
waitidle 1
sh (printf 'move 50 30\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_1) &
waitfile @RUN@/flag_1
wait 0.3
print step 000 text cursor shown
screenraw @OUT@/t000.txt
mem 2ce0 100 @OUT@/r000.bin
watchw f0000 1000
watchw e8000 2
type B:\n
waitidle 1
type GETSCRN\n
waitidle 2
type PICASSO\n
wait 35
print step 001 PICASSO up
items :11a
peek f0000 2
mem 2ce0 100 @OUT@/r001.bin
snap
sh (printf 'move -1000 -1000\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_2) &
waitfile @RUN@/flag_2
wait 0.5
print step 002 on File
peek 2daa 4
snap
sh (printf 'press L\nsleep 300\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nsleep 300\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_3) &
waitfile @RUN@/flag_3
wait 0.5
print step 003 on Quit
peek 2daa 4
snap
sh (printf 'release L\n' | @FEED@ --held L --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_4) &
waitfile @RUN@/flag_4
wait 2
snap
sh (printf 'move 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 4 0\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nmove 0 4\nsleep 300\npress L\nsleep 300\nrelease L\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_6) &
waitfile @RUN@/flag_6
peek 2daa 4
wait 5
waitidle 2
print step 004 after Quit
items :11a
screenraw @OUT@/t004.txt
mem 2ce0 100 @OUT@/r004.bin
snap
screen -
unwatch
type CLS\n
waitidle 1
type B:V9KMT sq\n
waittext fn 01 AX
waitidle 1
print step 005 V9KMT fn 0 + show
screenraw @OUT@/t005.txt
mem 2ce0 100 @OUT@/r005.bin
sh (printf 'move 30 20\n' | @FEED@ --script /dev/stdin --port $(cat @RUN@/pty_a) >> @RUN@/feed.log 2>&1; touch @RUN@/flag_5) &
waitfile @RUN@/flag_5
wait 0.3
print step 006 moved
screenraw @OUT@/t006.txt
mem 2ce0 100 @OUT@/r006.bin
snap
exit
