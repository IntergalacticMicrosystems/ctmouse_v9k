# Test 16b: A41 (interrupt-driven INT 41h owner of channel A, PORTA only sets the format) first,
# then CTM@V@ /SB (CHAIN41=@V@); 1360 text bytes on pty A and 200 mouse packets on pty B at once.
waittext >
waitidle 1
type B:A41\n
waitidle 2
sh DONE=@RUN@/done0 python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) 'PRE-CHECK\r\n' > @RUN@/send0.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/done0 30
wait 1
type B:A41 S\n
waitidle 2
sh cat @RUN@/send0.log
peek 104 4
peek e0001 1
sh python3 @REPO@/tools/v9kmouse.py --hello M --port $(cat @RUN@/pty_b) > @RUN@/hello.log 2>&1 & echo $! > @RUN@/hello.pid; echo $! >> @RUN@/pids
wait 0.5
type B:CTM@V@ /SB\n
waitidle 2
sh kill $(cat @RUN@/hello.pid)
peek 104 4
peek e0001 1
mem 0 a0000 @RUN@/mem1.bin
sh python3 @HERE@/ivt41.py @RUN@/mem1.bin
type B:V9KMT\n
waitidle 2
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
sh python3 @REPO@/tools/v9kmouse.py --script @HERE@/mouse200.txt --port $(cat @RUN@/pty_b) > @RUN@/sendB.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 120
wait 2
type lq
waitidle 2
type B:A41 S\n
waitidle 2
screen -
sh cat @RUN@/sendA.log
peek 104 4
peek e0001 1
# diagnostics: RR0A (bit 1 = any 7201 interrupt pending, bit 0 = Rx A), RR0B, 8259 state
peek e0042 1
peek e0043 1
items :7l
type DIR B:\n
waitidle 3
screen -
exit
