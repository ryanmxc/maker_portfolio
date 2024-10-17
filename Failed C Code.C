/*
 * Drum Trigger System - ADC Communication Code
 *
 * Description:
 * This C program interfaces with the MCP3008 ADC using SPI to collect analog data from multiple channels.
 * The analog signals originate from piezo sensors connected to different drums, allowing the system to 
 * capture the nuances of a drum performance in a home recording studio environment.
 * The BeagleBone Black serves as the microcontroller, and it uses SPI communication to sample data
 * from the ADC, which is then processed to detect drum hits and subsequently generate MIDI signals.
 *
 * Workflow:
 * 1. Initialize the SPI communication interface.
 * 2. Read analog values from multiple channels of the MCP3008 ADC.
 * 3. Process the values in real-time to determine if a drum hit has occurred.
 * 4. If a hit is detected, generate a MIDI signal.
 * 5. Continuously monitor all channels and adjust sensitivity using user-defined thresholds.
 *
 * This program uses Linux's SPI drivers and ioctl system calls to communicate with the MCP3008 ADC.
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <linux/spi/spidev.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <time.h>

#define SPI_DEVICE "/dev/spidev1.0"
#define MAX_CHANNELS 8

// SPI Configuration
#define SPI_MODE SPI_MODE_0
#define SPI_BITS 8
#define SPI_SPEED 1000000

// Threshold for detecting a drum hit
#define THRESHOLD 512

// Function prototypes
int init_spi();
uint16_t read_adc(int fd, uint8_t channel);
void cleanup(int sig);
void set_threshold(uint16_t new_threshold);
void log_data(const char *filename, uint16_t *channel_values, int num_channels);
void calibrate_sensors();

// Global variables
int spi_fd = -1;
uint16_t threshold = THRESHOLD;

// Function to initialize the SPI device
int init_spi() {
    int fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) {
        perror("Failed to open SPI device");
        return -1;
    }

    uint8_t mode = SPI_MODE;
    if (ioctl(fd, SPI_IOC_WR_MODE, &mode) == -1) {
        perror("Failed to set SPI mode");
        return -1;
    }

    uint8_t bits = SPI_BITS;
    if (ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) == -1) {
        perror("Failed to set SPI bits per word");
        return -1;
    }

    uint32_t speed = SPI_SPEED;
    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) == -1) {
        perror("Failed to set SPI speed");
        return -1;
    }

    return fd;
}

// Function to read from ADC (MCP3008)
uint16_t read_adc(int fd, uint8_t channel) {
    if (channel > 7) return 0;

    uint8_t tx[] = { 0x01, (0x80 | (channel << 4)), 0x00 };
    uint8_t rx[3] = { 0 };

    struct spi_ioc_transfer tr = {
        .tx_buf = (unsigned long)tx,
        .rx_buf = (unsigned long)rx,
        .len = 3,
        .delay_usecs = 0,
        .speed_hz = SPI_SPEED,
        .bits_per_word = SPI_BITS,
    };

    if (ioctl(fd, SPI_IOC_MESSAGE(1), &tr) == -1) {
        perror("Failed to communicate with ADC");
        return -1;
    }

    return ((rx[1] & 0x03) << 8) | rx[2];
}

// Signal handler for cleanup
void cleanup(int sig) {
    if (spi_fd >= 0) {
        close(spi_fd);
        printf("\nClosed SPI device. Exiting program.\n");
    }
    exit(0);
}

// Function to set a new threshold value
void set_threshold(uint16_t new_threshold) {
    threshold = new_threshold;
    printf("New threshold set to %d\n", threshold);
}

// Function to log data to a file
void log_data(const char *filename, uint16_t *channel_values, int num_channels) {
    FILE *file = fopen(filename, "a");
    if (file == NULL) {
        perror("Failed to open log file");
        return;
    }

    time_t now = time(NULL);
    fprintf(file, "Timestamp: %s", ctime(&now));
    for (int i = 0; i < num_channels; i++) {
        fprintf(file, "Channel %d: Value %d\n", i, channel_values[i]);
    }
    fprintf(file, "\n");

    fclose(file);
}

// Function to calibrate sensors
void calibrate_sensors() {
    printf("Calibrating sensors...\n");
    for (uint8_t channel = 0; channel < MAX_CHANNELS; channel++) {
        uint16_t value = read_adc(spi_fd, channel);
        printf("Channel %d initial value: %d\n", channel, value);
        // Adjust threshold or other calibration settings here as needed
    }
    printf("Calibration complete.\n");
}

int main() {
    // Register signal handler for cleanup
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);

    // Initialize SPI device
    spi_fd = init_spi();
    if (spi_fd < 0) {
        return -1;
    }

    printf("SPI device initialized successfully.\n");

    // Allocate memory for channel values
    uint16_t channel_values[MAX_CHANNELS] = {0};
    
    // Calibrate sensors before starting main loop
    calibrate_sensors();
    
    // Main loop to continuously read from ADC
    while (1) {
        for (uint8_t channel = 0; channel < MAX_CHANNELS; channel++) {
            // Read value from the ADC
            uint16_t value = read_adc(spi_fd, channel);
            channel_values[channel] = value;

            // Print channel values (optional for debugging)
            printf("Channel %d: Value %d\n", channel, value);

            // Check if the value exceeds the threshold
            if (value > threshold) {
                printf("Drum hit detected on channel %d with value %d!\n", channel, value);
                // Here you would send a MIDI signal or trigger an action
            }
        }
        
        // Log the data to a file
        log_data("drum_log.txt", channel_values, MAX_CHANNELS);
        
        usleep(500); // Adjust sample delay to avoid CPU overload
    }

    // Close SPI file descriptor before exiting
    cleanup(0);
    return 0;
}
