    .section .data
SPI_DEVICE:
    .asciz "/dev/spidev1.0"          @ SPI device file path
exit_message:
    .asciz "Closed SPI device. Exiting program.\n"
log_filename:
    .asciz "drum_log.txt"
threshold_val:
    .word 512                        @ Initial threshold value

    .section .bss
channel_values:
    .space 16                        @ Space for storing channel values (8 channels * 2 bytes each)

    .section .text
    .global _start

init_spi:
    @ Open SPI Device
    LDR R0, =SPI_DEVICE              @ Load address of SPI_DEVICE path string
    MOV R1, #2                       @ O_RDWR flag for open syscall
    SWI 0                            @ System call to open device
    CMP R0, #0                       @ Check if file descriptor is valid
    BLT error_exit                   @ Branch to error_exit if fd < 0

    @ Set SPI mode (SPI_IOC_WR_MODE)
    MOV R1, R0                       @ fd for ioctl
    MOV R2, #SPI_IOC_WR_MODE         @ Command to set mode
    LDR R3, =SPI_MODE                @ SPI mode value
    SWI 54                           @ ioctl syscall number
    CMP R0, #0
    BLT error_exit

    @ Set SPI bits per word (SPI_IOC_WR_BITS_PER_WORD)
    MOV R1, R0
    MOV R2, #SPI_IOC_WR_BITS_PER_WORD
    LDR R3, =SPI_BITS
    SWI 54
    CMP R0, #0
    BLT error_exit

    @ Set SPI speed (SPI_IOC_WR_MAX_SPEED_HZ)
    MOV R1, R0
    MOV R2, #SPI_IOC_WR_MAX_SPEED_HZ
    LDR R3, =SPI_SPEED
    SWI 54
    CMP R0, #0
    BLT error_exit

    BX LR                            @ Return from init_spi

error_exit:
    @ Error handling
    BL perror                        @ Call perror to print error message
    MOV R0, #-1                      @ Return -1 for failure
    BX LR

read_adc:
    CMP R1, #7                       @ Check if channel is within valid range
    BGT return_zero                  @ If channel > 7, return 0

    @ Prepare SPI transfer for ADC communication
    MOV R2, #0x01                    @ Start bit for ADC
    ORR R2, R2, R1, LSL #4           @ Combine channel into command byte
    STRB R2, [SP, #-1]!              @ Push byte to stack
    MOV R2, #0x00                    @ Empty byte for receiving data
    STRB R2, [SP, #-1]!

    @ SPI transfer via ioctl (SPI_IOC_MESSAGE)
    LDR R0, [SP, #4]                 @ Load fd
    MOV R1, RSP                      @ Transfer message struct pointer
    MOV R2, #1                       @ Number of messages
    SWI 54                           @ ioctl syscall

    @ Extracting ADC value
    LDR R3, [SP, #4]                 @ Load received byte from stack
    AND R3, R3, #0x03                @ Mask first two bits
    LDR R4, [SP, #3]                 @ Load next byte from stack
    ORR R3, R3, R4, LSL #8           @ Combine to get full 10-bit value
    MOV R0, R3                       @ Return value in R0
    BX LR

return_zero:
    MOV R0, #0                       @ Return 0 for invalid channel
    BX LR

cleanup:
    CMP R0, #0
    BLT close_spi                    @ If fd is valid, close it
    LDR R0, =exit_message            @ Load address of exit message string
    BL printf                        @ Print message
    SWI 1                            @ Exit syscall

close_spi:
    MOV R1, R0                       @ Pass fd to close
    SWI 6                            @ Close syscall number
    BX LR

set_threshold:
    LDR R1, =threshold_val           @ Load the address of threshold
    STR R0, [R1]                     @ Store new threshold value
    LDR R0, =threshold_message       @ Print new threshold message
    BL printf
    BX LR

log_data:
    LDR R0, =log_filename            @ Load filename
    MOV R1, #2                       @ O_APPEND flag for fopen
    SWI 5                            @ System call to open file
    CMP R0, #0                       @ Check if file is opened successfully
    BLT return_from_log              @ Return if failed

    MOV R1, #channel_values          @ Load channel values address
    MOV R2, #MAX_CHANNELS            @ Number of channels
log_loop:
    LDR R3, [R1], #4                 @ Load value and increment pointer
    MOV R4, R3                       @ Move to output register
    BL fprintf                       @ Print value to file
    SUBS R2, R2, #1                  @ Decrement count
    BNE log_loop                     @ Continue until all channels are logged

    SWI 6                            @ Close the file
return_from_log:
    BX LR

calibrate_sensors:
    LDR R0, =calibration_message     @ Print calibration start message
    BL printf

    MOV R2, #0                       @ Initialize channel index
calibrate_loop:
    MOV R1, R2                       @ Set channel
    BL read_adc                      @ Call read_adc to read value
    STR R0, [channel_values, R2, LSL #2] @ Store result in channel_values
    ADD R2, R2, #1                   @ Increment channel index
    CMP R2, #MAX_CHANNELS
    BLT calibrate_loop

    LDR R0, =calibration_done        @ Print calibration complete message
    BL printf
    BX LR

_start:
    @ Register signal handler for cleanup (this is simplified for illustration)
    MOV R0, #SIGINT
    LDR R1, =cleanup
    SWI 48                           @ Syscall to register signal handler

    @ Initialize SPI device
    BL init_spi
    CMP R0, #0
    BLT end_program                  @ If init failed, exit

    @ Calibrate sensors before starting main loop
    BL calibrate_sensors

main_loop:
    MOV R2, #0                       @ Initialize channel index
read_loop:
    MOV R1, R2                       @ Set channel index
    BL read_adc                      @ Read from ADC
    STR R0, [channel_values, R2, LSL #2] @ Store the value

    @ Check if value exceeds threshold
    LDR R3, =threshold_val           @ Load threshold value
    LDR R3, [R3]
    CMP R0, R3
    BLE skip_hit
    @ If threshold exceeded, trigger action
    LDR R0, =drum_hit_message
    BL printf

skip_hit:
    ADD R2, R2, #1                   @ Increment channel index
    CMP R2, #MAX_CHANNELS
    BLT read_loop                    @ Loop over all channels

    @ Log data
    BL log_data

    @ Delay (simplified)
    MOV R0, #500
    SWI 162                          @ Simulated delay (usleep)

    B main_loop                      @ Repeat indefinitely

end_program:
    BL cleanup
    SWI 1                            @ Exit

