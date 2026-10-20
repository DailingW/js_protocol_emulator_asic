/* SPDX-License-Identifier: Apache-2.0 */
/* Link at 0x80 (Ibex reset PC). Use only registers available in RV32E. */
.option norvc
.section .text
.global _start
_start:
    lui  t0, 0x10000
    addi t1, zero, 0x123
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    addi t2, t2, 1
    sw   t2, 4(t0)
    addi a0, zero, 0xab
    sb   a0, 5(t0)
    lbu  a1, 5(t0)
    addi a1, a1, 1
    sh   a1, 6(t0)
    lui  a2, 0x6
    addi a2, a2, 0xd
    sw   a2, 8(t0)
    wfi
1:  j 1b
