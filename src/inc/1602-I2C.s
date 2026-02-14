; ========================================
; LCD 16x2 Driver (HD44780 via PCF8574)
; 4-bit mode via I2C
; DEFINITIVE FIXED VERSION
; ========================================
    .include "inc/I2C.s"

; ========================================
; LCD Commands
; ========================================
LCD_CLEARDISPLAY   = $01
LCD_RETURNHOME     = $02
LCD_ENTRYMODESET   = $04
LCD_DISPLAYCONTROL = $08
LCD_FUNCTIONSET    = $20
LCD_SETDDRAMADDR   = $80

; Display control flags
LCD_DISPLAYON      = $04
LCD_CURSOROFF      = $00
LCD_BLINKOFF       = $00

; Function set flags
LCD_4BITMODE       = $00
LCD_2LINE          = $08
LCD_5x8DOTS        = $00

; PCF8574 pin mapping
LCD_EN        = %00000100
LCD_RS        = %00000001
LCD_BACKLIGHT = %00001000

; ========================================
; Zero Page Variables
; ========================================
    .dsect
LCD_NibbleVal:  reserve 1
LCD_StrPtr:     reserve 2
LCD_CharByte:   reserve 1
    .dend

; ========================================
; Public Routines
; ========================================

; LCD_Init: Initialize LCD in 4-bit mode
LCD_Init:
    JSR I2C_SetAddress
    
    ; HD44780 initialization - send 0x3 three times
    LDA #($03 << 4)
    JSR _WriteNibble
    LDA #($03 << 4)
    JSR _WriteNibble
    LDA #($03 << 4)
    JSR _WriteNibble
    
    ; Switch to 4-bit mode
    LDA #($02 << 4)
    JSR _WriteNibble
    
    ; Function set: 4-bit, 2-line, 5x8 font
    LDA #(LCD_FUNCTIONSET | LCD_4BITMODE | LCD_2LINE | LCD_5x8DOTS)
    JSR _WriteCommand
    
    ; Display ON
    LDA #(LCD_DISPLAYCONTROL | LCD_DISPLAYON | LCD_CURSOROFF | LCD_BLINKOFF)
    JSR _WriteCommand
    
    ; Clear display
    LDA #LCD_CLEARDISPLAY
    JSR _WriteCommand
    
    ; Entry mode
    LDA #(LCD_ENTRYMODESET | $02)
    JSR _WriteCommand
    
    RTS

; LCD_Clear: Clear display
LCD_Clear:
    LDA #LCD_CLEARDISPLAY
    JSR _WriteCommand
    RTS

; LCD_Home: Return cursor home
LCD_Home:
    LDA #LCD_RETURNHOME
    JSR _WriteCommand
    RTS

; LCD_SetCursor: Set cursor position
; Inputs: A = column (0-15), X = row (0-1)
LCD_SetCursor:
    CPX #0
    BEQ _SetCursor_Row0
    CLC
    ADC #$40
_SetCursor_Row0:
    ORA #LCD_SETDDRAMADDR
    JSR _WriteCommand
    RTS

; LCD_WriteChar: Write a single character
; Inputs: A = ASCII character
LCD_WriteChar:
    STA LCD_CharByte
    JSR _WriteData
    RTS

; LCD_WriteHex: Write a byte as two hex characters
; Inputs: A = byte to print
LCD_WriteHex:
    PHA
    ; High nibble
    LSR A
    LSR A
    LSR A
    LSR A
    JSR _HexToAscii
    JSR LCD_WriteChar
    ; Low nibble
    PLA
    AND #$0F
    JSR _HexToAscii
    JSR LCD_WriteChar
    RTS

; _HexToAscii: Convert nibble to ASCII hex character
; Inputs: A = nibble (0-15)
; Outputs: A = ASCII character ('0'-'9', 'A'-'F')
_HexToAscii:
    CMP #$0A
    BCC _HexToAscii_Digit
    ; A-F
    ADC #$36        ; 'A' - 10 - 1 (carry is set)
    RTS
_HexToAscii_Digit:
    ; 0-9
    ADC #$30        ; '0'
    RTS

; LCD_WriteString: Write null-terminated string
; Inputs: LCD_StrPtr (16-bit pointer)
; CRITICAL FIX: Must preserve Y register because I2C_WriteByte destroys it!
LCD_WriteString:
    LDY #0
_WriteString_Loop:
    LDA (LCD_StrPtr),Y
    BEQ _WriteString_Done
    STA LCD_CharByte        ; Save character to write
    
    ; CRITICAL: Save Y before calling any I2C functions
    ; I2C_WriteByte sets Y=8 internally, destroying our string index!
    TYA                     ; Save Y in A temporarily
    PHA                     ; Push to stack
    
    JSR _WriteData          ; This calls I2C_WriteByte which clobbers Y
    
    PLA                     ; Restore Y from stack
    TAY
    INY                     ; Move to next character
    
    JMP _WriteString_Loop
_WriteString_Done:
    RTS

; ========================================
; Private Routines
; ========================================

; _WriteCommand: Send command byte (RS=0)
; Inputs: A = command byte
_WriteCommand:
    PHA
    ; Upper nibble
    AND #$F0
    JSR _WriteNibble
    ; Lower nibble
    PLA
    AND #$0F
    ASL A
    ASL A
    ASL A
    ASL A
    JSR _WriteNibble
    RTS

; _WriteData: Send data byte (RS=1)
; Inputs: LCD_CharByte = data byte to send
_WriteData:
    LDA LCD_CharByte
    PHA
    ; Upper nibble with RS=1
    AND #$F0
    ORA #LCD_RS
    JSR _WriteNibble
    ; Lower nibble with RS=1
    PLA
    AND #$0F
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #LCD_RS
    JSR _WriteNibble
    RTS

; _WriteNibble: Send nibble to LCD with EN pulse
; Inputs: A = nibble in bits 7-4, RS in bit 0
; Uses I2C_WriteByte to send 3 phases: EN=0, EN=1, EN=0
_WriteNibble:
    PHA                     ; Save nibble value
    
    ; Phase 1: EN=0 (setup)
    ORA #LCD_BACKLIGHT      ; Always backlight on
    AND #%11111001          ; Clear EN(bit2), keep nibble(7-4)+backlight(3)+RS(0)
    JSR I2C_WriteByte
    
    ; Phase 2: EN=1 (pulse high)
    PLA
    PHA
    ORA #(LCD_BACKLIGHT | LCD_EN)
    AND #%11111101          ; Keep nibble+backlight+EN+RS, clear bit 1
    JSR I2C_WriteByte
    
    ; Phase 3: EN=0 (latch)
    PLA
    ORA #LCD_BACKLIGHT
    AND #%11111001          ; Clear EN bit, keep backlight
    JSR I2C_WriteByte
    
    RTS