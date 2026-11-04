.syntax unified
.cpu cortex-a9
.arm
.section .vectors,"ax"
.global _start
_start:
 cpsid if
 mrc p15,0,r0,c1,c0,0
 tst r0,#5
 bne 2f
 ldr sp,=__stack_top
 ldr r0,=__bss_start
 ldr r1,=__bss_end
 mov r2,#0
0: cmp r0,r1
 strlo r2,[r0],#4
 blo 0b
 bl main
1: wfi
 b 1b
2: wfi
 b 2b
