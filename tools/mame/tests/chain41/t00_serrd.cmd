# Baseline: PORTA (polled SERIALA) + SERRD, no mouse driver. 40 lines on pty A.
waittext >
waitidle 1
type B:SERRD SERIALA Q\n
waittext SERRD reading
wait 1
sh DONE=@RUN@/doneA python3 @HERE@/sendtext.py $(cat @RUN@/pty_a) --lines 40 --eof > @RUN@/sendA.log 2>&1 & echo $! >> @RUN@/pids
waitfile @RUN@/doneA 60
wait 2
type x
wait 5
screen -
sh cat @RUN@/sendA.log
exit
