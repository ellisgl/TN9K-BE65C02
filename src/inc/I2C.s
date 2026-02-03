; ========================================
; I2C Driver for 6522 VIA
; Bit-banged I2C on PB0 (SDA) and PB1 (SCL)
; ========================================

; Export public routines
    .global I2C_Init
    .global I2C_Start
    .global I2C_Stop
    .global I2C_WriteByte
    .global I2C_SetAddress

; Import VIA definitions
    .extern VIA_PB
    .extern VIA_DDRB

; ========================================
; Zero Page Variables
; ========================================
    .dsect
I2C_Addr:       reserve 1   ; I2C device address (7-bit, pre-shifted left)
I2C_Temp:       reserve 1   ; Temporary storage
    .dend

; ========================================
; Public Routines
; ========================================

; I2C_Init: Initialize I2C interface
; Inputs: None
; Outputs: None
; Destroys: A
I2C_Init:
    LDA #%11111111      ; Set all PB pins as outputs
    STA VIA_DDRB
    LDA #%00000011      ; SDA=1, SCL=1 (idle high)
    STA VIA_PB
    RTS

; I2C_SetAddress: Set the I2C device address
; Inputs: A = 7-bit I2C address
; Outputs: None
; Destroys: A
I2C_SetAddress:
    ASL A               ; Shift left to make room for R/W bit
    STA I2C_Addr
    RTS

; I2C_WriteByte: Write a byte to I2C device
; Inputs: A = byte to write
; Outputs: None
; Destroys: A, Y
I2C_WriteByte:
    STA I2C_Temp        ; Save data byte
    
    JSR I2C_Start
    
    ; Send address
    LDY #8
    LDA I2C_Addr
    JSR _SendByte
    JSR _ClockACK
    
    ; Send data
    LDY #8
    LDA I2C_Temp
    JSR _SendByte
    JSR _ClockACK
    
    JSR I2C_Stop
    RTS

; I2C_Start: Generate I2C start condition
; SDA falls while SCL is high
; Inputs: None
; Outputs: None
; Destroys: A
I2C_Start:
    LDA #%00000011      ; Both high
    STA VIA_PB
    NOP
    NOP
    LDA #%00000010      ; SDA low (start condition)
    STA VIA_PB
    NOP
    LDA #%00000000      ; SCL low
    STA VIA_PB
    NOP
    RTS

; I2C_Stop: Generate I2C stop condition
; SDA rises while SCL is high
; Inputs: None
; Outputs: None
; Destroys: A
I2C_Stop:
    LDA #%00000000      ; Both low
    STA VIA_PB
    NOP
    LDA #%00000010      ; SCL high
    STA VIA_PB
    NOP
    LDA #%00000011      ; SDA high (stop condition)
    STA VIA_PB
    NOP
    NOP
    RTS

; ========================================
; Private Routines
; ========================================

; _SendByte: Shift out 8 bits MSB first
; Inputs: A = byte to send, Y = 8
; Outputs: None
; Destroys: A, Y
_SendByte:
_SendByte_Loop:
    ASL A               ; Shift MSB into carry
    PHA                 ; Save byte
    PHY                 ; Save counter
    BCC _Write0
    JSR _Write1
    JMP _SendByte_Next
_Write0:
    JSR _Write0_Sub
_SendByte_Next:
    PLY                 ; Restore counter
    PLA                 ; Restore byte
    DEY
    BNE _SendByte_Loop
    RTS

; _ClockACK: Clock out ACK bit
; Release SDA, pulse SCL, then reclaim SDA
; Inputs: None
; Outputs: None
; Destroys: A
_ClockACK:
    ; Set SDA as input to read ACK
    LDA VIA_DDRB
    AND #%11111110
    STA VIA_DDRB
    
    ; SCL low
    LDA #%00000000
    STA VIA_PB
    NOP
    
    ; SCL high (slave ACKs during this)
    LDA #%00000010
    STA VIA_PB
    NOP
    NOP
    
    ; SCL low
    LDA #%00000000
    STA VIA_PB
    NOP
    
    ; Set SDA back to output
    LDA VIA_DDRB
    ORA #%00000001
    STA VIA_DDRB
    RTS

; _Write0_Sub: Write a 0 bit (SDA low)
; Inputs: None
; Outputs: None
; Destroys: A
_Write0_Sub:
    LDA #%00000000      ; SDA=0, SCL=0
    STA VIA_PB
    NOP
    LDA #%00000010      ; SDA=0, SCL=1 (clock pulse)
    STA VIA_PB
    NOP
    NOP
    LDA #%00000000      ; SDA=0, SCL=0
    STA VIA_PB
    NOP
    RTS

; _Write1: Write a 1 bit (SDA high)
; Inputs: None
; Outputs: None
; Destroys: A
_Write1:
    LDA #%00000001      ; SDA=1, SCL=0
    STA VIA_PB
    NOP
    LDA #%00000011      ; SDA=1, SCL=1 (clock pulse)
    STA VIA_PB
    NOP
    NOP
    LDA #%00000001      ; SDA=1, SCL=0
    STA VIA_PB
    NOP
    RTS
