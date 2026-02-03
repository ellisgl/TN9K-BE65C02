; ========================================
; Main Program
; Demonstrates LCD 16x2 via I2C
; ========================================

; Import drivers
    .extern I2C_Init
    .extern LCD_Init
    .extern LCD_Clear
    .extern LCD_SetCursor
    .extern LCD_WriteChar
    .extern LCD_WriteString
    .extern LCD_StrPtr

; ========================================
; Hardware Definitions
; ========================================
VIA_BASE_ADR = $6000

    .global VIA_PB
    .global VIA_DDRB

VIA_PB   = VIA_BASE_ADR + 0
VIA_DDRB = VIA_BASE_ADR + 2

; I2C LCD address
LCD_I2C_ADDR = $27

; ========================================
; Program Start
; ========================================
    .org $8000

start:
    ; Initialize I2C
    JSR I2C_Init
    
    ; Initialize LCD at address 0x27
    LDA #LCD_I2C_ADDR
    JSR LCD_Init
    
    ; Write "Hello World!"
    LDA #<msg_hello
    STA LCD_StrPtr
    LDA #>msg_hello
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Set cursor to second line (row 1, col 0)
    LDA #0              ; Column 0
    LDX #1              ; Row 1
    JSR LCD_SetCursor
    
    ; Write "6502 + I2C LCD"
    LDA #<msg_6502
    STA LCD_StrPtr
    LDA #>msg_6502
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Done - infinite loop
loop:
    JMP loop

; ========================================
; Data
; ========================================
msg_hello:
    .byte "Hello, World!", 0

msg_6502:
    .byte "6502 + I2C LCD", 0

; ========================================
; Vectors
; ========================================
    .org $FFFC
    .word start         ; Reset vector
    .word start         ; NMI vector
