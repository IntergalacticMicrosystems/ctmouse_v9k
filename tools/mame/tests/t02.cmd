# Test 2: no port -> usage, EL 1; /SA with no feeder -> "No mouse detected", EL 2, INT 41h and IMR unchanged
waittext >
waitidle 1
peek cc 4
peek 104 4
peek e0001 1
type B:EL\n
waitidle 2
screen -
type CLS\n
waitidle 1
type B:EL /SA\n
waittext EL=
waitidle 1
screen -
peek 104 4
peek e0001 1
peek cc 4
exit
