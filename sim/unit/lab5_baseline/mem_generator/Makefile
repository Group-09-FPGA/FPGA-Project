#//////////////////////////////////////////////////////
#/////////////////INCLUDING CROSS-COMPILER/////////////

CC      = /tools/Xilinx/2026.1/gnu/riscv/lin/bin/riscv64-unknown-elf-gcc
AR      = /tools/Xilinx/2026.1/gnu/riscv/lin/bin/riscv64-unknown-elf-ar
OBJDUMP = /tools/Xilinx/2026.1/gnu/riscv/lin/bin/riscv64-unknown-elf-objdump
OBJCOPY = /tools/Xilinx/2026.1/gnu/riscv/lin/bin/riscv64-unknown-elf-objcopy
READELF = /tools/Xilinx/2026.1/gnu/riscv/lin/bin/riscv64-unknown-elf-readelf


#///// flags for RV32i architecture///////////////////
CFLAGS  = -march=rv32i -mabi=ilp32


#////Source for c code file ///////////////////////////
SRC_ADDITION     = code_addition.c
SRC_SORT     = code_sort.c
SRC_NEGATIVE = code_negative.c

TARGET   = code.elf

.PHONY: all clean

#/// generating .text file of code cross-compiled from highlevel-c code to risc-v code
# ////////////// Copying and converting the text file into binary files
#/////// Python script to convert the binary files into the required hex files

addition: $(SRC_ADDITION)
	$(CC) -c  $(SRC_ADDITION) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python3 bin2hex.py

sort: $(SRC_SORT)
	$(CC) -c  $(SRC_SORT) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python3 bin2hex.py

negative: $(SRC_NEGATIVE)
	$(CC) -c  $(SRC_NEGATIVE) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python3 bin2hex.py


# /////clean function
clean:
	$(RM) $(TARGET) ./imem_dmem/imem.bin ./imem_dmem/imem.hex ./imem_dmem/dmem.bin ./imem_dmem/dmem.hex ./imem_dmem/code.dis

fibo: code_fibo.c
	$(CC) -c  code_fibo.c -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python3 bin2hex.py

xor: code_xor.c
	$(CC) -c  code_xor.c -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && python3 bin2hex.py
