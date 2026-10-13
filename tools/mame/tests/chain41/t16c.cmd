# Test 16c (reverse order): CTM@V@ /SB first, then A41 hooks INT 41h over it (A41 never chains).
# Traffic on both ports, then CTM@V@ /U must refuse (INT 41h is no longer ours). No V9KMT here:
# its fn 0 runs enable7201, which re-hooks INT 41h over A41 (t16d shows that).
waittext >
waitidle 1
sh python3 @REPO@/tools/v9kmouse.py --hello M --port $(cat @RUN@/pty_b) > @RUN@/hello.log 2>&1 & echo $! > @RUN@/hello.pid; echo $! >> @RUN@/pids
wait 0.5
type B:CTM@V@ /SB\n
waitidle 2
sh kill $(cat @RUN@/hello.pid)
peek 104 4
peek e0001 1
print -- after CTM
peek e0042 1
peek e0043 1
items :7l
type B:A41\n
waitidle 2
peek 104 4
peek e0001 1
print -- after A41
peek e0042 1
peek e0043 1
items :7l
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
sh python3 @REPO@/tools/v9kmouse.py --script @HERE@/mouse200.txt --port $(cat @RUN@/pty_b) > @RUN@/sendB.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 120
# the pty is drained into MAME long before the 7201 has clocked it in: 1360 bytes = 11.3 s
wait 14
type B:A41 S\n
waitidle 2
sh cat @RUN@/sendA.log
print -- after traffic
peek e0042 1
peek e0043 1
items :7l
waitidle 2
type B:CTM@V@ /U\n
waitidle 2
screen -
peek 104 4
peek e0001 1
exit
