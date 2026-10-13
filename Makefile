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

# The Victor 9000 build (ctmv9k.asm) is 8086-only and independent of ASFLAGS
V9KFLAGS=-c -bin -0

# Pinned baseline commit for the PC build: ctmouse.exe must stay byte-identical to it
PC_BASE=1d93f1e

# Targets ##############################################################

all: ctmouse.exe

v9k: ctmv9k.exe

ctmv9k.exe: ctmv9k-en.msg ctmv9k.asm bin2exe
	$(AS) $(V9KFLAGS) -D\?LANG=ctmv9k-en -Foctmv9k.bin ctmv9k.asm
	python3 tools/ressize.py ctmv9k.bin
	./bin2exe -s 512 ctmv9k.bin ctmv9k.exe

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
	-$(RM) ctmv9k.exe
	-$(RM) ctmouse.ref
	-$(RM) *.o
	-$(RM) *.lst
	-$(RM) *.map
	
distclean: clean
	-$(RM) bin2exe
	-$(RM) ctmouse.exe
	-$(RM) ctm-*.exe

