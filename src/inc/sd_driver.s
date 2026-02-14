; ========================================
; SD Card Driver
; Uses SPI driver for communication
; ========================================
; Usage:
;   .include "inc/spi_driver.s"
;   .include "inc/sd_driver.s"
;   JSR SD_Init
;   ; Check A for success (0) or error code
;
;   ; Read block 0 to $0200
;   LDX #$00  ; Block low
;   LDY #$00  ; Block high
;   LDA #$00
;   STA SD_PTR_LO
;   LDA #$02
;   STA SD_PTR_HI
;   JSR SD_ReadBlock
; ========================================

; Zero page variables
SD_TEMP     = $20
SD_TEMP2    = $21
SD_PTR_LO   = $22
SD_PTR_HI   = $23

; SD Card Response Codes
SD_R1_READY = $00
SD_R1_IDLE  = $01
SD_TIMEOUT  = $FF

; SD Card Commands
SD_CMD0     = $40
SD_CMD8     = $48
SD_CMD17    = $51
SD_CMD24    = $58
SD_CMD55    = $77
SD_ACMD41   = $69

; ========================================
; SD_Init: Initialize SD card
; Outputs: A = 0 on success, error code otherwise
; Destroys: A, X, Y
; ========================================
SD_Init:
    JSR SPI_Init
    
    ; Power-up: 80+ clocks with CS high
    LDX #10
.powerup:
    LDA #$FF
    PHX
    JSR SPI_WriteByte
    PLX
    DEX
    BNE .powerup
    
    ; CMD0
    JSR SD_CMD0_Internal
    CMP #SD_R1_IDLE
    BNE .init_error
    
    ; CMD8
    JSR SD_CMD8_Internal
    
    ; ACMD41 loop
    LDX #255
.acmd41_loop:
    STX SD_TEMP
    JSR SD_CMD55_Internal
    JSR SD_ACMD41_Internal
    CMP #SD_R1_READY
    BEQ .init_success
    LDX SD_TEMP
    DEX
    BNE .acmd41_loop
    
.init_error:
    RTS

.init_success:
    LDA #$00
    RTS

; ========================================
; SD_ReadBlock: Read 512-byte block
; Inputs: X,Y = block number (Y=high, X=low)
;         SD_PTR_LO/HI = destination address
; Outputs: A = 0 on success
; Destroys: A, X, Y
; ========================================
SD_ReadBlock:
    STX SD_TEMP
    STY SD_TEMP2
    
    JSR SPI_CS_Assert
    
    ; CMD17
    LDA #SD_CMD17
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA SD_TEMP2
    JSR SPI_WriteByte
    LDA SD_TEMP
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    
    ; Wait for R1
    JSR SD_WaitResponse
    CMP #SD_R1_READY
    BNE .read_error
    
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
    LDA #SD_TIMEOUT
    JMP .read_error

.got_token:
    ; Read 512 bytes
    LDY #0
.read_loop_high:
    LDX #0
.read_loop_low:
    PHX
    PHY
    JSR SPI_ReadByte
    PLY
    PLX
    STA (SD_PTR_LO),Y
    INY
    BNE .read_loop_low
    
    INC SD_PTR_HI
    INX
    CPX #2
    BNE .read_loop_high
    
    ; Read CRC (ignore)
    JSR SPI_ReadByte
    JSR SPI_ReadByte
    
    JSR SPI_CS_Deassert
    LDA #$00
    RTS

.read_error:
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

; ========================================
; SD_WriteBlock: Write 512-byte block
; Inputs: X,Y = block number
;         SD_PTR_LO/HI = source address
; Outputs: A = 0 on success
; Destroys: A, X, Y
; ========================================
SD_WriteBlock:
    STX SD_TEMP
    STY SD_TEMP2
    
    JSR SPI_CS_Assert
    
    ; CMD24
    LDA #SD_CMD24
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA SD_TEMP2
    JSR SPI_WriteByte
    LDA SD_TEMP
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    
    ; Wait for R1
    JSR SD_WaitResponse
    CMP #SD_R1_READY
    BNE .write_error
    
    ; Send data token
    LDA #$FE
    JSR SPI_WriteByte
    
    ; Write 512 bytes
    LDY #0
.write_loop_high:
    LDX #0
.write_loop_low:
    LDA (SD_PTR_LO),Y
    PHX
    PHY
    JSR SPI_WriteByte
    PLY
    PLX
    INY
    BNE .write_loop_low
    
    INC SD_PTR_HI
    INX
    CPX #2
    BNE .write_loop_high
    
    ; Send CRC (dummy)
    LDA #$FF
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    
    ; Read data response
    JSR SPI_ReadByte
    AND #$1F
    CMP #$05
    BNE .write_error
    
    ; Wait while busy
.wait_busy:
    JSR SPI_ReadByte
    CMP #$00
    BEQ .wait_busy
    
    JSR SPI_CS_Deassert
    LDA #$00
    RTS

.write_error:
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

; ========================================
; Internal Commands
; ========================================

SD_CMD0_Internal:
    JSR SPI_CS_Assert
    LDA #SD_CMD0
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA #$95
    JSR SPI_WriteByte
    JSR SD_WaitResponse
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

SD_CMD8_Internal:
    JSR SPI_CS_Assert
    LDA #SD_CMD8
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    LDA #$AA
    JSR SPI_WriteByte
    LDA #$87
    JSR SPI_WriteByte
    JSR SD_WaitResponse
    PHX
    JSR SPI_ReadByte
    JSR SPI_ReadByte
    JSR SPI_ReadByte
    JSR SPI_ReadByte
    PLX
    JSR SPI_CS_Deassert
    RTS

SD_CMD55_Internal:
    JSR SPI_CS_Assert
    LDA #SD_CMD55
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    JSR SD_WaitResponse
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

SD_ACMD41_Internal:
    JSR SPI_CS_Assert
    LDA #SD_ACMD41
    JSR SPI_WriteByte
    LDA #$40
    JSR SPI_WriteByte
    LDA #$00
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    JSR SPI_WriteByte
    LDA #$01
    JSR SPI_WriteByte
    JSR SD_WaitResponse
    PHA
    JSR SPI_CS_Deassert
    PLA
    RTS

SD_WaitResponse:
    LDX #16
.loop:
    PHX
    JSR SPI_ReadByte
    PLX
    CMP #$FF
    BNE .got
    DEX
    BNE .loop
    LDA #SD_TIMEOUT
.got:
    RTS