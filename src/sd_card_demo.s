; ========================================
; SD Card Driver Demo
; Demonstrates reading and writing blocks
; ========================================

LCD_I2C_ADDR = $27

    .org $8000
    .include "inc/addresses.s"
    .include "inc/1602-I2C.s"
    .include "inc/spi_driver.s"
    .include "inc/sd_driver.s"

reset:
    LDX #$FF
    TXS
    
    JSR I2C_Init
    LDA #LCD_I2C_ADDR
    JSR LCD_Init
    JSR LCD_Clear
    
    ; Display init message
    LDA #<msg_init
    STA LCD_StrPtr
    LDA #>msg_init
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Initialize SD card
    JSR SD_Init
    CMP #$00
    BNE error
    
    ; Line 2
    LDA #0
    LDX #1
    JSR LCD_SetCursor
    
    LDA #<msg_reading
    STA LCD_StrPtr
    LDA #>msg_reading
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Read block 0 to $0200
    LDA #$00
    STA SD_PTR_LO
    LDA #$02
    STA SD_PTR_HI
    
    LDX #$00        ; Block 0 low byte
    LDY #$00        ; Block 0 high byte
    JSR SD_ReadBlock
    
    CMP #$00
    BNE error
    
    ; Display first 8 bytes
    JSR LCD_Clear
    LDA #<msg_data
    STA LCD_StrPtr
    LDA #>msg_data
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Line 2 - show hex data
    LDA #0
    LDX #1
    JSR LCD_SetCursor
    
    LDY #0
show_loop:
    LDA $0200,Y
    JSR LCD_WriteHex
    LDA #' '
    JSR LCD_WriteChar
    INY
    CPY #6          ; Show 6 bytes
    BNE show_loop
    
    JMP done

error:
    JSR LCD_Clear
    LDA #<msg_error
    STA LCD_StrPtr
    LDA #>msg_error
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Line 2 - show error code
    LDA #0
    LDX #1
    JSR LCD_SetCursor
    LDA #<msg_code
    STA LCD_StrPtr
    LDA #>msg_code
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Show error code (still in A from SD_Init/SD_ReadBlock)
    JSR LCD_WriteHex

done:
    JMP done

msg_init:
    .byte "Initializing...", 0
msg_reading:
    .byte "Reading Block 0", 0
msg_data:
    .byte "Block 0 Data:", 0
msg_error:
    .byte "SD Card Error!", 0
msg_code:
    .byte "Code: ", 0

    .org $FFFC
    .word reset
    .word reset