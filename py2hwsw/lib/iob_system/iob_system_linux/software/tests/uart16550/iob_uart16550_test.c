#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <time.h>

/**
 * IOb-UART16550 Driver Compatibility Test Suite
 *
 * This program validates that a UART core correctly implements the 16550
 * register map by exercising the standard Linux 8250 serial driver through its
 * termios API.
 */

#define TEST_PATTERN                                                           \
  "IOb-UART16550 Loopback Test Pattern - 0123456789 - "                        \
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
#define STRESS_SIZE 4096

typedef struct {
  speed_t speed;
  int baud;
} baud_map_t;

/* Map of standard baud rates to test clock divider accuracy */
baud_map_t baud_rates[] = {
    {B9600, 9600},   {B19200, 19200},   {B38400, 38400},
    {B57600, 57600}, {B115200, 115200},
};

/**
 * Configures a serial port using the termios API.
 * This exercises the driver's ability to program the UART's LCR, DLL, and DLM
 * registers.
 */
int configure_port(int fd, speed_t speed, int data_bits, int stop_bits,
                   char parity, int flow_ctrl) {
  struct termios tty;
  if (tcgetattr(fd, &tty) != 0)
    return -1;

  /* Set Baud Rate (DLL/DLM registers) */
  cfsetospeed(&tty, speed);
  cfsetispeed(&tty, speed);

  /* Set Data Bits (LCR[1:0]) */
  tty.c_cflag &= ~CSIZE;
  switch (data_bits) {
  case 5:
    tty.c_cflag |= CS5;
    break;
  case 6:
    tty.c_cflag |= CS6;
    break;
  case 7:
    tty.c_cflag |= CS7;
    break;
  case 8:
    tty.c_cflag |= CS8;
    break;
  default:
    return -1;
  }

  /* Set Parity (LCR[5:3]) */
  tty.c_cflag &= ~(PARENB | PARODD);
  if (parity == 'E')
    tty.c_cflag |= PARENB;
  else if (parity == 'O')
    tty.c_cflag |= (PARENB | PARODD);

  /* Set Stop Bits (LCR[2]) */
  if (stop_bits == 2)
    tty.c_cflag |= CSTOPB;
  else
    tty.c_cflag &= ~CSTOPB;

  /* Set Hardware Flow Control (MCR/MSR interaction) */
  if (flow_ctrl)
    tty.c_cflag |= CRTSCTS;
  else
    tty.c_cflag &= ~CRTSCTS;

  /* Raw mode: disable all processing (canonical, echo, etc.) */
  tty.c_lflag = 0;
  tty.c_oflag = 0;
  tty.c_iflag = 0;
  tty.c_cc[VMIN] = 0;
  tty.c_cc[VTIME] = 10; // 1.0 second read timeout

  tcflush(fd, TCIFLUSH);
  if (tcsetattr(fd, TCSANOW, &tty) != 0)
    return -1;
  return 0;
}

/**
 * Transfers data from TX to RX and verifies integrity.
 * Exercises FIFO (FCR) and Interrupts (IER/IIR/LSR).
 */
int run_transfer_test(int fd_tx, int fd_rx, const char *pattern, size_t size) {
  char rx_buf[STRESS_SIZE + 1];
  memset(rx_buf, 0, sizeof(rx_buf));

  tcflush(fd_tx, TCOFLUSH);
  tcflush(fd_rx, TCIFLUSH);

  /* Write data to TX UART */
  ssize_t written = write(fd_tx, pattern, size);
  if (written != (ssize_t)size) {
    printf("Fail: Written %zd/%zu bytes\n", written, size);
    return -1;
  }

  /* Read data from RX UART with timeout loop */
  size_t total_read = 0;
  while (total_read < size) {
    ssize_t n = read(fd_rx, rx_buf + total_read, size - total_read);
    if (n <= 0)
      break;
    total_read += n;
  }

  /* Compare received data to expected pattern */
  if (total_read != size || memcmp(pattern, rx_buf, size) != 0) {
    printf("Fail: Integrity check failed. Read %zu/%zu bytes\n", total_read,
           size);
    return -1;
  }
  return 0;
}

int main(int argc, char *argv[]) {
  const char *dev1 = "/dev/ttyS1";
  const char *dev2 = "/dev/ttyS2";
  int failure_count = 0;

  if (argc >= 3) {
    dev1 = argv[1];
    dev2 = argv[2];
  }

  /* Open devices in non-blocking mode to allow precise control */
  int fd1 = open(dev1, O_RDWR | O_NOCTTY | O_NONBLOCK);
  int fd2 = open(dev2, O_RDWR | O_NOCTTY | O_NONBLOCK);

  if (fd1 < 0 || fd2 < 0) {
    perror("Error opening UART devices");
    return 1;
  }

  printf("Starting IOb-UART16550 Driver Compatibility Test\n");
  printf("Ports: %s <-> %s\n\n", dev1, dev2);

  /* Test 1: Configuration Matrix Sweep (LCR/DLL/DLM validation) */
  printf("[1/3] Testing Configuration Matrix (Baud/Data/Parity/Stop)...\n");
  for (int b = 0; b < 5; b++) {
    for (int db = 7; db <= 8; db++) {
      for (int sb = 1; sb <= 2; sb++) {
        char parities[] = {'N', 'E', 'O'};
        for (int p = 0; p < 3; p++) {
          printf("  Baud:%-6d Bits:%d Stop:%d Parity:%c ... ",
                 baud_rates[b].baud, db, sb, parities[p]);

          if (configure_port(fd1, baud_rates[b].speed, db, sb, parities[p], 0) <
                  0 ||
              configure_port(fd2, baud_rates[b].speed, db, sb, parities[p], 0) <
                  0) {
            printf("Config Error\n");
            failure_count++;
            continue;
          }

          if (run_transfer_test(fd1, fd2, TEST_PATTERN, strlen(TEST_PATTERN)) ==
              0) {
            printf("OK\n");
          } else {
            printf("FAILED\n");
            failure_count++;
          }
        }
      }
    }
  }

  /* Test 2: Stress Test (FIFO & Interrupt pressure) */
  printf("\n[2/3] Testing Stress Transfer (4KB at 115200)...\n");
  char *stress_pattern = malloc(STRESS_SIZE);
  for (int i = 0; i < STRESS_SIZE; i++)
    stress_pattern[i] = (char)(i & 0xFF);

  configure_port(fd1, B115200, 8, 1, 'N', 0);
  configure_port(fd2, B115200, 8, 1, 'N', 0);

  if (run_transfer_test(fd1, fd2, stress_pattern, STRESS_SIZE) == 0) {
    printf("  Stress Test: PASS\n");
  } else {
    printf("  Stress Test: FAIL\n");
    failure_count++;
  }

  /* Test 3: Hardware Flow Control (MCR/MSR validation) */
  printf("\n[3/3] Testing Hardware Flow Control (RTS/CTS)...\n");
  if (configure_port(fd1, B115200, 8, 1, 'N', 1) == 0 &&
      configure_port(fd2, B115200, 8, 1, 'N', 1) == 0) {
    if (run_transfer_test(fd1, fd2, TEST_PATTERN, strlen(TEST_PATTERN)) == 0) {
      printf("  HW Flow Control: PASS\n");
    } else {
      printf(
          "  HW Flow Control: FAIL (Check wiring or core RTS/CTS support)\n");
      failure_count++;
    }
  }

  free(stress_pattern);
  close(fd1);
  close(fd2);

  if (failure_count > 0) {
    printf("\nValidation Complete: %d TESTS FAILED.\n", failure_count);
    return 1;
  } else {
    printf("\nValidation Complete: ALL TESTS PASSED.\n");
    return 0;
  }
}
