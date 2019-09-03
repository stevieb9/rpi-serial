#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
// #include "crc16.h"

#define POLY 0x8408

int crc15() {
    printf("hello %d\n", 10);
}

unsigned short crc16(char *data_p, unsigned short length){
      printf("%d\n", 5);
      unsigned char i;
      unsigned int data;
      unsigned int crc = 0xffff;

        printf("%s, %d\n", data_p, length);
      if (length == 0)
            return (~crc);
      do {
            for (i=0, data=(unsigned int)0xff & *data_p++; i < 8; i++, data >>= 1){
                  if ((crc & 0x0001) ^ (data & 0x0001))
                        crc = (crc >> 1) ^ POLY;
                  else  crc >>= 1;
            }
      } while (--length);

      crc = ~crc;
      data = crc;
      crc = (crc << 8) | (data >> 8 & 0xff);

      return crc;
}

void tty_close (int fd){
  close (fd);
}

int tty_available (int fd){
    int bytes_available;
    ioctl(fd, FIONREAD, &bytes_available);
    return bytes_available;
}

int tty_putc(int fd, char b){
    int n = write(fd,&b,1);
    if( n!=1)
        return -1;
    return 0;
}

int tty_puts(int fd, const char* str){
    int len = strlen(str);
    int n = write(fd, str, len);
    if( n!=len )
        return -1;
    return 0;
}

int tty_getc (int fd){
  uint8_t x;

  if (read (fd, &x, 1) != 1)
    return -1;

  return ((int)x) & 0xFF;
}

char* tty_gets(int fd, char* buf, int nbytes){
    int bytes_read = 0;

    while (bytes_read < nbytes){
        int result = read(fd, buf + bytes_read, nbytes - bytes_read);

        if (0 >= result){
            if (0 > result){
                exit(-1);
            }
            break;
        }
        bytes_read += result;
    }

    return buf;
}

int tty_open(const char *serialport, int baud){
    struct termios toptions;
    int fd;

    fd = open(serialport, O_RDWR | O_NOCTTY | O_NDELAY);

    if (fd == -1)  {
        perror("open(): Unable to open port ");
        return -1;
    }

    if (tcgetattr(fd, &toptions) < 0) {
        perror("init_serialport: Couldn't get term attributes");
        return -1;
    }
    speed_t brate = baud;
    switch(baud) {
    case 4800:   brate=B4800;   break;
    case 9600:   brate=B9600;   break;
#ifdef B14400
    case 14400:  brate=B14400;  break;
#endif
    case 19200:  brate=B19200;  break;
#ifdef B28800
    case 28800:  brate=B28800;  break;
#endif
    case 38400:  brate=B38400;  break;
    case 57600:  brate=B57600;  break;
    case 115200: brate=B115200; break;
    }

    cfsetispeed(&toptions, brate);
    cfsetospeed(&toptions, brate);

    // 8N1
    toptions.c_cflag &= ~PARENB;
    toptions.c_cflag &= ~CSTOPB;
    toptions.c_cflag &= ~CSIZE;
    toptions.c_cflag |= CS8;
    // no flow control
    toptions.c_cflag &= ~CRTSCTS;

    toptions.c_cflag |= CREAD | CLOCAL;  // turn on READ & ignore ctrl lines
    toptions.c_iflag &= ~(IXON | IXOFF | IXANY); // turn off s/w flow ctrl

    toptions.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG); // make raw
    toptions.c_oflag &= ~OPOST; // make raw

    toptions.c_cc[VMIN]  = 0;
    toptions.c_cc[VTIME] = 10;

    if( tcsetattr(fd, TCSANOW, &toptions) < 0) {
        perror("init_serialport: Couldn't set term attributes");
        return -1;
    }

    return fd;
}

MODULE = RPi::Serial  PACKAGE = RPi::Serial

PROTOTYPES: DISABLE

int
tty_available (fd)
	int	fd

int
tty_putc (fd, b)
	int	fd
	char b

int
tty_puts (fd, str)
	int	fd
	const char *str

int
tty_getc (fd)
	int	fd

char *
tty_gets (fd, buf, nbytes)
	int	fd
	char *buf
	int	nbytes

int
tty_open (serialport, baud)
	const char *serialport
	int	baud

void
tty_close (fd)
    int fd

int crc15()

unsigned short
crc16(data_p, length)
    char *data_p
    unsigned short length
