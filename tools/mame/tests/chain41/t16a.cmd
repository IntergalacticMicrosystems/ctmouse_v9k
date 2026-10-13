# Test 16a: PORTA (polled SERIALA on A) loaded from CONFIG.SYS, then CTM@V@ /SB (CHAIN41=@V@),
# then SERRD reads SERIALA while pty A gets 1360 text bytes and pty B 200 mouse packets at once.
waittext >
waitidle 1
peek 104 4
peek e0001 1
sh python3 @REPO@/tools/v9kmouse.py --hello M --port $(cat @RUN@/pty_b) > @RUN@/hello.log 2>&1 & echo $! > @RUN@/hello.pid; echo $! >> @RUN@/pids
wait 0.5
type B:CTM@V@ /SB\n
waitidle 2
sh kill $(cat @RUN@/hello.pid)
screen -
peek 104 4
peek e0001 1
mem 0 a0000 @RUN@/mem1.bin
sh python3 @HERE@/ivt41.py @RUN@/mem1.bin
type B:SERRD SERIALA Q\n
waittext SERRD reading
wait 1
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 --eof > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
sh DONE=@RUN@/doneB python3 @REPO@/tools/v9kmouse.py --script @HERE@/mouse200.txt --port $(cat @RUN@/pty_b) > @RUN@/sendB.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 90
wait 2
type x
wait 5
screen -
sh cat @RUN@/sendA.log
peek 104 4
peek e0001 1
type DIR B:\n
waitidle 2
screen -
exit
