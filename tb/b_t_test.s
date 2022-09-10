addi x1, x0, 5
addi x2, x0, 5
addi x3, x0, 4
addi x8, x0, -5
beq  x1, x2, _j1
addi x4, x0, 1
_j1:bne  x1, x3, _j2
addi x5, x0, 1
_j2:blt  x8, x1, _j3
addi x6, x0, 1
_j3:bge  x1, x8, _j4
addi x7, x0, 1
_j4:addi x0,x0, 0
bltu  x1, x8, _j5
addi x9, x0, 1
_j5:bgeu  x8, x1, _j6
addi x10, x0, 1
_j6:addi x0,x0, 0