; ========================================
; SPI Driver for VIA6522
; Bit-banging SPI on Port A
; ========================================
; Usage:
;   .include "inc/spi_driver.s"
;   JSR SPI_Init
;   JSR SPI_CS_Assert
;   LDA #$FF
;   JSR SPI_WriteByte
;   JSR SPI_ReadByte
;   JSR SPI_CS_Deassert
; ========================================

; Hardware Configuration
; VIA_BASE_ADR = $6000
; VIA_PA       = VIA_BASE_ADR + 1
; VIA_DDRA     = VIA_BASE_ADR + 3

; Pin definitions (Port A)
SPI_CS   = %00000001    ; PA0 - Chip Select
SPI_MOSI = %00000010    ; PA1 - Master Out Slave In
SPI_SCK  = %00000100    ; PA2 - Clock
SPI_MISO = %00001000    ; PA3 - Master In Slave Out

; ========================================
; SPI_Init: Initialize SPI interface
; Inputs: None
; Outputs: None
; Destroys: A
; ========================================
SPI_Init:
    ; Set CS, MOSI, SCK as outputs; MISO as input
    LDA #(SPI_CS | SPI_MOSI | SPI_SCK)
    STA VIA_DDRA
    
    ; Set initial state: CS high (deasserted), MOSI high, SCK low
    LDA #(SPI_CS | SPI_MOSI)
    STA VIA_PA
    RTS

; ========================================
; SPI_CS_Assert: Pull CS low to select device
; Inputs: None
; Outputs: None
; Destroys: A
; ========================================
SPI_CS_Assert:
    LDA #SPI_MOSI           ; CS=0, MOSI=1, SCK=0
    STA VIA_PA
    RTS

; ========================================
; SPI_CS_Deassert: Pull CS high to deselect device
; Inputs: None
; Outputs: None
; Destroys: A
; ========================================
SPI_CS_Deassert:
    LDA #(SPI_CS | SPI_MOSI)  ; CS=1, MOSI=1, SCK=0
    STA VIA_PA
    RTS

; ========================================
; SPI_WriteByte: Send a byte over SPI
; Inputs: A = byte to send
; Outputs: None
; Destroys: A, X, Y
; ========================================
SPI_WriteByte:
    LDX #8                  ; 8 bits to send
.loop:
    ASL                     ; Shift MSB into carry
    TAY                     ; Save remaining bits
    
    LDA #0
    BCC .send_bit
    ORA #SPI_MOSI          ; Set MOSI if bit was 1
.send_bit:
    STA VIA_PA             ; Output bit with SCK low
    EOR #SPI_SCK           ; Toggle SCK high
    STA VIA_PA             ; Clock the bit
    
    TYA                    ; Restore remaining bits
    DEX
    BNE .loop
    RTS

; ========================================
; SPI_ReadByte: Read a byte over SPI
; Inputs: None
; Outputs: A = received byte
; Destroys: A, X, Y
; ========================================
SPI_ReadByte:
    LDY #0                 ; Clear result
    LDX #8                 ; 8 bits to read
.loop:
    ; Clock low with MOSI high (idle)
    LDA #SPI_MOSI
    STA VIA_PA
    
    ; Clock high
    LDA #(SPI_MOSI | SPI_SCK)
    STA VIA_PA
    
    ; Read MISO
    LDA VIA_PA
    AND #SPI_MISO
    
    ; Shift into result
    CLC
    BEQ .bit_not_set
    SEC
.bit_not_set:
    TYA
    ROL
    TAY
    
    DEX
    BNE .loop
    
    TYA                    ; Return result in A
    RTS