# Test 16d: CTM@V@ /SB, then A41 hooks INT 41h; V9KMT (INT 33h fn 0 -> enable7201) re-hooks INT 41h
# to CTMOUSEV and orphans A41 (before 843a392); since 843a392 INT 41h stays A41's and /U refuses.
waittext >
waitidle 1
sh python3 @REPO@/tools/v9kmouse.py --hello M --port $(cat @RUN@/pty_b) > @RUN@/hello.log 2>&1 & echo $! > @RUN@/hello.pid; echo $! >> @RUN@/pids
wait 0.5
type B:CTM@V@ /SB\n
waitidle 2
sh kill $(cat @RUN@/hello.pid)
print -- after CTM
peek 104 4
mem 0 a0000 @RUN@/mem1.bin
sh python3 @HERE@/ivt41.py @RUN@/mem1.bin
type B:A41\n
waitidle 2
print -- after A41
peek 104 4
type B:V9KMT q\n
waitidle 2
print -- after V9KMT (fn 0)
peek 104 4
mem 0 a0000 @RUN@/mem2.bin
sh python3 @HERE@/ivt41.py @RUN@/mem2.bin
type B:CTM@V@ /U\n
waitidle 2
screen -
print -- after /U
peek 104 4
peek e0001 1
exit
