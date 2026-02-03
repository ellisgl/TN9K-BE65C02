; ========================================
; LCD 16x2 Driver (HD44780 via PCF8574)
; 4-bit mode via I2C
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
; P7-P4: LCD D7-D4 (data)
; P3: Backlight
; P2: Enable
; P1: R/W
; P0: RS
LCD_EN        = %00000100
LCD_RS        = %00000001
LCD_BACKLIGHT = %00001000

; ========================================
; Zero Page Variables
; ========================================
    .dsect
LCD_NibbleVal:  reserve 1
LCD_StrPtr:     reserve 2
    .dend

; ========================================
; Public Routines
; ========================================

; LCD_Init: Initialize LCD in 4-bit mode
; Inputs: A = I2C address (7-bit, e.g., $27)
; Outputs: None
; Destroys: A, X, Y
LCD_Init:
    ; Set I2C address
    JSR I2C_SetAddress
    
    ; HD44780 initialization sequence
    ; Wait for power-on (normally 40ms+ needed, but we're lazy)
    
    ; Send 0x3 three times (8-bit mode init)
    LDX #($03 << 4)
    JSR _WriteNibble
    LDX #($03 << 4)
    JSR _WriteNibble
    LDX #($03 << 4)
    JSR _WriteNibble
    
    ; Switch to 4-bit mode
    LDX #($02 << 4)
    JSR _WriteNibble
    
    ; Function set: 4-bit, 2-line, 5x8 font
    LDX #LCD_FUNCTIONSET | LCD_4BITMODE | LCD_2LINE | LCD_5x8DOTS
    JSR _WriteCommand
    
    ; Display ON, cursor OFF, blink OFF
    LDX #LCD_DISPLAYCONTROL | LCD_DISPLAYON | LCD_CURSOROFF | LCD_BLINKOFF
    JSR _WriteCommand
    
    ; Clear display
    LDX #LCD_CLEARDISPLAY
    JSR _WriteCommand
    
    ; Entry mode: increment cursor, no shift
    LDX #LCD_ENTRYMODESET | $02
    JSR _WriteCommand
    
    RTS

; LCD_Clear: Clear display and return home
; Inputs: None
; Outputs: None
; Destroys: X
LCD_Clear:
    LDX #LCD_CLEARDISPLAY
    JSR _WriteCommand
    RTS

; LCD_Home: Return cursor to home position
; Inputs: None
; Outputs: None
; Destroys: X
LCD_Home:
    LDX #LCD_RETURNHOME
    JSR _WriteCommand
    RTS

; LCD_SetCursor: Set cursor position
; Inputs: A = column (0-15), X = row (0-1)
; Outputs: None
; Destroys: A, X
LCD_SetCursor:
    CPX #0
    BEQ _SetCursor_Row0
    ; Row 1: DDRAM address starts at 0x40
    CLC
    ADC #$40
_SetCursor_Row0:
    ; Row 0: DDRAM address starts at 0x00
    ORA #LCD_SETDDRAMADDR
    TAX
    JSR _WriteCommand
    RTS

; LCD_WriteChar: Write a single character
; Inputs: A = ASCII character
; Outputs: None
; Destroys: A, X
LCD_WriteChar:
    TAX
    JSR _WriteData
    RTS

; LCD_WriteString: Write null-terminated string
; Inputs: LCD_StrPtr (16-bit pointer to string)
; Outputs: None
; Destroys: A, X, Y
LCD_WriteString:
    LDY #0
_WriteString_Loop:
    LDA (LCD_StrPtr),Y
    BEQ _WriteString_Done
    TAX
    JSR _WriteData
    INY
    BRA _WriteString_Loop
_WriteString_Done:
    RTS

; ========================================
; Private Routines
; ========================================

; _WriteCommand: Send command byte (RS=0)
; Inputs: X = command byte
; Outputs: None
; Destroys: A, X
_WriteCommand:
    TXA
    PHA
    AND #$F0            ; Upper nibble
    TAX
    JSR _WriteNibble
    
    PLA
    AND #$0F            ; Lower nibble
    ASL A
    ASL A
    ASL A
    ASL A
    TAX
    JSR _WriteNibble
    RTS

; _WriteData: Send data byte (RS=1)
; Inputs: X = data byte
; Outputs: None
; Destroys: A, X
_WriteData:
    TXA
    PHA
    AND #$F0            ; Upper nibble
    ORA #LCD_RS         ; Set RS=1 for data
    TAX
    JSR _WriteNibble
    
    PLA
    AND #$0F            ; Lower nibble
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #LCD_RS         ; Set RS=1 for data
    TAX
    JSR _WriteNibble
    RTS

; _WriteNibble: Send nibble to LCD with EN pulse
; Inputs: X = nibble in bits 7-4, RS flag in bit 0
; Outputs: None
; Destroys: A, Y, X
_WriteNibble:
    PHX                 ; Save nibble for all 3 transactions
    
    ; EN = 0 (setup)
    JSR I2C_Start
    LDY #8
    LDA I2C_Addr        ; Need to access I2C_Addr from i2c.asm
    ; Actually, let's use a different approach - call a wrapper
    PLX
    PHX
    TXA
    AND #%11110001      ; Keep nibble + RS, clear others
    ORA #LCD_BACKLIGHT  ; Always keep backlight on
    JSR _SendI2CByte
    NOP
    NOP
    
    ; EN = 1 (pulse high)
    JSR I2C_Start
    PLX
    PHX
    TXA
    AND #%11110001
    ORA #(LCD_BACKLIGHT | LCD_EN)
    JSR _SendI2CByte
    NOP
    NOP
    
    ; EN = 0 (latch)
    JSR I2C_Start
    PLX
    TXA
    AND #%11110001
    ORA #LCD_BACKLIGHT
    JSR _SendI2CByte
    NOP
    NOP
    NOP
    NOP
    RTS

; _SendI2CByte: Helper to send a byte via I2C
; This duplicates some I2C_WriteByte logic but without the full wrapper
; Inputs: A = byte to send
; Outputs: None
; Destroys: A, Y
_SendI2CByte:
    PHA                 ; Save data byte
    
    ; Send address (already started)
    LDY #8
    LDA I2C_Addr
    JSR _I2C_SendByte
    JSR _I2C_ClockACK
    
    ; Send data
    PLA
    LDY #8
    JSR _I2C_SendByte
    JSR _I2C_ClockACK
    
    JSR I2C_Stop
    RTS

; Note: We need to access some I2C internals here
; Let's import them
    .extern I2C_Addr
    .extern _SendByte
    .extern _ClockACK

; Rename for clarity
_I2C_SendByte = _SendByte
_I2C_ClockACK = _ClockACK
