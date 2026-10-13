# Makefile to create CTMOUSE.EXE
# tools used:
# - GNU make
# - JWasm v2.12pre
# - gcc or clang
# - bin2exe (built from source included in the repo)

# As default, just the English version CTMOUSE.EXE is created.
# To create all versions, enter "wmake alllang".

# Macros for building, deleting ########################################

AS=jwasm
GCC=gcc
RM=rm -f

# Uncomment this to build for 8088/8086
ASFLAGS=-c -bin -0
# Uncomment this to build for 286 and better
# ASFLAGS=-c -bin -2

# The Victor 9000 build (ctmousev.asm) is 8086-only and independent of ASFLAGS.
# `make v9k-chain41` builds the experimental INT 41h sharing variant (-DCHAIN41=1)
# as ctmousev-chain41.exe, a separate target so the two configurations never alias.
V9KFLAGS=-c -bin -0

# Pinned baseline commit for the PC build: ctmouse.exe must stay byte-identical to it
PC_BASE=1d93f1e

# Targets ##############################################################

all: ctmouse.exe

v9k: ctmousev.exe

ctmousev.exe: ctmousev-en.msg ctmousev.asm ctmousev-video.inc bin2exe
	$(AS) $(V9KFLAGS) -D\?LANG=ctmousev-en -Foctmousev.bin ctmousev.asm
	python3 tools/ressize.py ctmousev.bin
	./bin2exe -s 512 ctmousev.bin ctmousev.exe

v9k-chain41: ctmousev-chain41.exe

ctmousev-chain41.exe: ctmousev-en.msg ctmousev.asm ctmousev-video.inc bin2exe
	$(AS) $(V9KFLAGS) -DCHAIN41=1 -D\?LANG=ctmousev-en -Foctmousev-chain41.bin ctmousev.asm
	python3 tools/ressize.py ctmousev-chain41.bin
	./bin2exe -s 512 ctmousev-chain41.bin ctmousev-chain41.exe

verify-pc: ctmouse.exe
	git show $(PC_BASE):ctmouse.exe > ctmouse.ref
	cmp ctmouse.exe ctmouse.ref || { $(RM) ctmouse.ref; exit 1; }
	$(RM) ctmouse.ref

alllang: ctm-en.exe ctm-br.exe ctm-de.exe ctm-es.exe ctm-fr.exe \
	ctm-hu.exe ctm-it.exe ctm-lv.exe ctm-pl.exe ctm-pt.exe ctm-sk.exe

ctmouse.exe: ctm-en.msg ctmouse.asm bin2exe
	$(AS) $(ASFLAGS) -D\?LANG=ctm-en -Foctmouse.bin ctmouse.asm
	./bin2exe -s 512 ctmouse.bin ctmouse.exe

%.exe: %.msg ctmouse.asm bin2exe
	$(AS) $(ASFLAGS) -D\?LANG=$* -Fo$*.bin ctmouse.asm
	./bin2exe -s 512 $*.bin $*.exe
	
bin2exe: bin2exe.c
	$(GCC) bin2exe.c -o bin2exe

# Clean up #############################################################

clean:
	-$(RM) *.bin
	-$(RM) ctmouse.exe
	-$(RM) ctmousev.exe ctmousev-chain41.exe
	-$(RM) ctmouse.ref
	-$(RM) *.o
	-$(RM) *.lst
	-$(RM) *.map
	
distclean: clean
	-$(RM) bin2exe
	-$(RM) ctmouse.exe
	-$(RM) ctm-*.exe

