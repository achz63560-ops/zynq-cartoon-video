ENTRY(_start)
MEMORY { APP (rwx) : ORIGIN = 0x00100000, LENGTH = 0x00100000 }
SECTIONS {
 .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) } > APP
 .data : { *(.data*) } > APP
 .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > APP
 .stack (NOLOAD) : { . = ALIGN(16); . += 16384; __stack_top = .; } > APP
 __framebuffer_start = 0x10000000;
 __framebuffer_end = 0x10600000;
 ASSERT(__stack_top < __framebuffer_start, "ELF overlaps reserved framebuffer")
}
