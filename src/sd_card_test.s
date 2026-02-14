; ========================================
; SD Card Test with Progress Indicators
; Shows dots while reading to indicate progress
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
    
    ; Line 1
    LDA #<msg_init
    STA LCD_StrPtr
    LDA #>msg_init
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Line 2
    LDA #0
    LDX #1
    JSR LCD_SetCursor
    
    ; Initialize SD card
    JSR SD_Init
    CMP #$00
    BNE error
    
    LDA #'O'
    JSR LCD_WriteChar
    LDA #'K'
    JSR LCD_WriteChar
    LDA #' '
    JSR LCD_WriteChar
    
    ; Read just the FIRST 16 BYTES instead of 512!
    ; This will be much faster
    LDA #$00
    STA SD_PTR_LO
    STA SD_PTR_HI
    
    ; Read block 0 using special fast version
    JSR SD_ReadBlock_Fast
    
    CMP #$00
    BNE error
    
    ; Clear and show data
    JSR LCD_Clear
    LDA #<msg_data
    STA LCD_StrPtr
    LDA #>msg_data
    STA LCD_StrPtr+1
    JSR LCD_WriteString
    
    ; Line 2
    LDA #0
    LDX #1
    JSR LCD_SetCursor
    
    ; Show first 6 bytes
    LDY #0
show_loop:
    LDA $0000,Y
    JSR LCD_WriteHex
    LDA #' '
    JSR LCD_WriteChar
    INY
    CPY #6
    BNE show_loop
    
    JMP done

error:
    LDA #'E'
    JSR LCD_WriteChar
    LDA #'R'
    JSR LCD_WriteChar
    PHA
    JSR LCD_WriteHex
    PLA

done:
    JMP done

; Fast read - only reads first 16 bytes for testing
SD_ReadBlock_Fast:
    JSR SPI_CS_Assert
    
    ; CMD17
    LDA #$51            ; CMD17
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    
    ; Wait for R1
    JSR SD_WaitResponse
    CMP #$00
    BNE .error
    
    ; Wait for data token $FE
    LDX #255
.wait_token:
    PHX
    JSR SPI_ReadByte
    PLX
    CMP #$FE
    BEQ .got_token
    DEX
    BNE .wait_token
    LDA #$FF
    JMP .error

.got_token:
    ; Read only 16 bytes
    LDY #0
.read_loop:
    PHY
    JSR SPI_ReadByte
    PLY
    STA (SD_PTR_LO),Y
    INY
    CPY #16
    BNE .read_loop
    
    ; Skip the rest + CRC
    ; (deassert CS - card will stop sending)
    JSR SPI_CS_Deassert
    LDA #$00
    RTS

.error:
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

msg_init:
    .byte "SD Init:", 0
msg_data:
    .byte "Data:", 0

    .org $FFFC
    .word reset
    .word reset