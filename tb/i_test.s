daddi x1, x0, 2   #0
addi x2, x0, 4   #4
addi x3, x0, -1  #8
slti x4, x1, 2   #12
slti x5, x1 , 0  #16
slti x6, x1 , -1 #20
sltiu x7, x1, 2  #24
sltiu x8, x1, 0  #28
sltiu x9, x2 , -1#32
xori x10, x1, 2  #36
ori  x11, x1, 2  #40
andi x12, x1, 2  #44
slli x13, x1, 2  #48
srli x14, x1, 2  #52
srai x15, x1, 2  #56
lui x16, 12345   #60
auipc x17, 10    #64
