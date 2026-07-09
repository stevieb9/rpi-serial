package RPi::Serial;

use strict;
use warnings;

use Carp qw(croak);

our $VERSION = '3.03';

require XSLoader;
XSLoader::load('RPi::Serial', $VERSION);

sub new {
    my ($class, $device, $baud) = @_;

    if (! defined $device){
        croak "new() requires a serial device path\n";
    }

    if (! defined $baud || $baud !~ /^\d+$/ || $baud == 0){
        croak "new() requires a positive integer baud rate\n";
    }

    # Open before blessing so a failed open never leaves a live object whose
    # DESTROY would close a bogus fd

    my $fd = tty_open($device, $baud);

    if ($fd < 0){
        croak "new() could not open serial device '$device'\n";
    }

    my $self = bless {
        rx_data    => '',
        rx_started => 0,
        rx_ended   => 0,
        fd         => $fd,
    }, $class;

    return $self;
}
sub close {
    my ($self) = @_;
    my $fd = $self->fd;
    tty_close($fd) if defined $fd && $fd >= 0;
}
sub crc {
    my ($self, $data) = @_;
    return crc16($data, length($data));
}
sub avail {
    return tty_available($_[0]->fd);
}
sub fd {
    my $self = shift;
    $self->{fd} = shift if @_;
    return $self->{fd};
}
sub flush {
    tty_flush($_[0]->fd);
}
sub putc {
    tty_putc($_[0]->fd, $_[1]);
}
sub puts {
    tty_puts($_[0]->fd, $_[1]);
}
sub getc {
    return tty_getc($_[0]->fd);
}
sub gets {
    # Returns the exact bytes read (binary-safe); may be shorter than the
    # requested count if the port's read timeout elapsed first.
    return tty_gets($_[0]->fd, $_[1]);
}
sub write {
    my ($self, $byte) = @_;

    if (! defined $byte || $byte !~ /^\d+$/ || $byte > 255){
        croak "write() requires a byte value between 0 and 255\n";
    }

    $self->putc(pack("C", $byte));
}
sub rx {
    my ($self, $start, $end) = @_;

    my $c = chr $self->getc; # getc() returns the ord() val on a char* perl-wise

    if ($c ne $start && ! $self->{rx_started}){
        $self->_rx_reset();
        return;
    }

    if ($c eq $start){
        $self->{rx_started} = 1;
        return;
    }

    if ($c eq $end){
        $self->{rx_ended} = 1;
    }

    if ($self->{rx_started} && ! $self->{rx_ended}){
        $self->{rx_data} .= $c;
    }

    if ($self->{rx_started} && $self->{rx_ended}){

        my $l_crc = $self->_local_crc($self->{rx_data});
        my $r_crc = $self->_remote_crc($self->{rx_data});

        if ($r_crc == $l_crc){
            my $rx_data = $self->{rx_data};
            $self->_rx_reset;
            return $rx_data;
        }
        else {
            warn "\ncompiled data '$self->{rx_data}' has mismatching CRC\n\n";
            $self->_rx_reset;
            return;
        }
    }

    # Still assembling a frame: return an explicit undef, not the value of the
    # last if-condition (which would be a defined 0 and read as a complete frame)
    return;
}
sub tx {
    my ($self, $data, $tx_start, $tx_end) = @_;

    my $crc = $self->crc($data);
    my $crc_msb = $crc >> 8;
    my $crc_lsb = $crc & 0xFF;

    my $tx = $tx_start . $data . $tx_end;

    # The delimiters and payload go out as raw characters via putc(); write()
    # is only for the two integer CRC bytes below - it packs an integer, so
    # handing it a character would numify to 0 and corrupt the frame

    for (split //, $tx){
        $self->putc($_);
    }

    $self->write($crc_msb);
    $self->write($crc_lsb);
}

sub DESTROY {
    my ($self) = @_;
    my $fd = $self->fd;
    tty_close($fd) if defined $fd && $fd >= 0;
}

sub _local_crc {
    return $_[0]->crc($_[1]);
}
sub _remote_crc {
    my ($self) = @_;

    while ($self->avail < 2){} # loop until we have two bytes to make up the CRC

    my $crc_msb = $self->getc;
    my $crc_lsb = $self->getc;

    my $crc = ($crc_msb << 8) | $crc_lsb;

    return if $crc_msb == -1 || $crc_lsb == -1;
    return $crc;
}
sub _rx_reset {
    my ($self) = @_;
    $self->{rx_started} = 0;
    $self->{rx_ended} = 0;
    $self->{rx_data} = '';
}
sub __placeholder {} # vim folds
1;

=head1 NAME

RPi::Serial - Basic read/write interface to a serial port

=head1 SYNOPSIS

    use RPi::Serial;

    # Open the port with a device path and a baud rate

    my $s = RPi::Serial->new('/dev/ttyAMA0', 115200);

    # Single bytes

    $s->putc('A');          # Write one character
    $s->write(65);          # Write one byte by its integer value (0-255)

    my $ord = $s->getc;     # Read one byte; returns its 0-255 value (-1 if none)

    # Strings

    $s->puts("hello, world!");

    my $str = $s->gets(13); # read up to N bytes (may be shorter on timeout)

    # CRC-framed messages (see "CRC FRAMING")

    # Sending a CRC string

    $s->tx('Just Another Perl Hacker!', '<', '>');

    # Receiving a CRC string

    my $msg;

    until (defined $msg) {
        $msg = $s->rx('<', '>') if $s->avail;
    }

    print "$msg\n";        # Just Another Perl Hacker!

    # Check what the CRC checksum was

    my $checksum = $s->crc("Just Another Perl Hacker!");

    # Housekeeping

    my $waiting = $s->avail;   # Bytes waiting to be read
    $s->flush;                 # Discard buffered input/output
    $s->close;

=head1 DESCRIPTION

Provides basic read and write functionality of a UART serial interface

=head1 WARNING

If using on a Raspberry Pi platform, the procedure to enable GPIO pins 14 (TXD)
and 15 (RXD) as a serial interface differs by board. On B<all> boards, first
free the port from the kernel console: in C<raspi-config>, under C<Interface
Options -E<gt> Serial Port>, answer B<no> to the login shell and B<yes> to the
serial hardware.

=head2 Raspberry Pi 3 / 4 (and Zero W)

The on-board Bluetooth modem is wired to the primary PL011 UART, leaving GPIO
14/15 on the inferior, baud-unstable mini-UART (C</dev/ttyS0>). To move the good
UART onto the header pins you must disable Bluetooth. Edit
C</boot/firmware/config.txt> (C</boot/config.txt> on releases before Bookworm)
and add:

    enable_uart=1
    dtoverlay=disable-bt

With that overlay the header serial port becomes C</dev/ttyAMA0>.

=head2 Raspberry Pi 5

Bluetooth has its B<own dedicated UART> and is B<not> shared with the GPIO 14/15
pins, so there is nothing to disable. Just enable the header UART in
C</boot/firmware/config.txt>:

    enable_uart=1

The header serial port is C</dev/ttyAMA0>. (Note that on the Pi 5
C</dev/serial0> maps to the separate 3-pin debug-UART connector, B<not> the
header pins.)

Save the file, then reboot the Pi.

=head1 METHODS

=head2 new($device, $baud);

Opens the specified serial port at the specified baud rate, and returns a new
L<RPi::Serial> object.

Parameters:

    $device

Mandatory, String: The serial device to open (eg: C<"/dev/ttyAMA0">).

    $baud

Mandatory, Integer: A valid baud rate to use.

=head2 close

Closes an already open serial device.

=head2 avail

Returns the number of bytes waiting to be read if any.

=head2 flush

Flush any data currently in the serial buffer.

=head2 fd

Returns the C<ioctl> file descriptor for the current serial object.

=head2 getc

Retrieve a single character from the serial port.

=head2 gets($num_bytes)

Read up to a specified number of bytes and return them as a string.

The read blocks only until the port's configured read timeout (the C<VTIME>
value set when the port was opened) elapses, so the returned string may be
B<shorter> than C<$num_bytes> if fewer bytes arrived in time (or the device
closed). The result is binary-safe: embedded C<NUL> bytes and trailing
whitespace are preserved exactly as received.

Parameters:

    $num_bytes

Mandatory, Integer; The maximum number of bytes to read. If this number is
larger than what is available, the call returns the bytes received before the
read timeout elapsed (possibly an empty string).

Returns: A string of the bytes actually read. Croaks on a read error.

=head2 putc($char)

Writes a single character to the serial device.

Parameters:

    $char

Mandatory, Unsigned Char: The character to write to the port.

=head2 puts($string)

Write a character string to the serial device.

Parameters:

    $string

Mandatory, String: Whatever you want to write to the serial line.

=head2 crc($string)

Calculate and return a CRC-16 checksum. Uses local B<crc16.c> application to
generate the CRC.

Parameters:

    $string

Mandatory, String: The string to perform the checksum on.

=head2 write($byte)

Writes a single byte to the serial device. The byte is packed into an unsigned
char before being sent, making this a convenience wrapper around L</putc($char)>
that accepts an integer value rather than a character.

Parameters:

    $byte

Mandatory, Unsigned Integer (0-255): The byte value to write to the port.
Croaks if not supplied.

=head2 rx($start, $end)

Reads a single character from the serial port and assembles framed data across
successive calls. A frame begins when the C<$start> delimiter is received and
ends when the C<$end> delimiter is received, at which point the two trailing
CRC-16 bytes are read and validated against the assembled payload.

Call this repeatedly (eg: in a loop). Until a complete, CRC-valid frame has been
received it returns C<undef>; characters seen before the C<$start> delimiter are
discarded.

Parameters:

    $start

Mandatory, Char: The single character that marks the beginning of a frame.

    $end

Mandatory, Char: The single character that marks the end of a frame.

Returns: The assembled payload string once a full frame with a matching CRC has
been received, or C<undef> otherwise. Warns and discards the frame if the
received CRC does not match the locally computed one.

=head2 tx($data, $tx_start, $tx_end)

Transmits a frame of data. The C<$data> is wrapped between the C<$tx_start> and
C<$tx_end> delimiters and written to the port, followed by the two bytes (most
significant first) of the CRC-16 checksum calculated over C<$data>.

Parameters:

    $data

Mandatory, String: The payload to transmit.

    $tx_start

Mandatory, Char: The single character to send before the payload.

    $tx_end

Mandatory, Char: The single character to send after the payload.

=head1 CRC FRAMING

L</tx($data, $tx_start, $tx_end)> and L</rx($start, $end)> together implement a
small, robust message protocol on top of the raw byte stream: you send a whole
payload and the far end can confirm it arrived intact. Each message is wrapped
between a start and an end delimiter and followed by a two-byte CRC-16 of the
payload:

    +---------+--------------+---------+-----------+-----------+
    | $start  |  payload...  |  $end   |  CRC MSB  |  CRC LSB  |
    +---------+--------------+---------+-----------+-----------+
              \___ the CRC covers the payload only ___/

L</tx($data, $tx_start, $tx_end)> writes that entire frame in one call.

L</rx($start, $end)> is the receiver, and it is B<stateful>: it consumes one byte
per call, so you call it repeatedly until it hands you a message. It discards
input until it sees C<$start>, accumulates the payload until it sees C<$end>,
then reads the two trailing CRC bytes and compares them against a CRC it
recomputes over what it received. On a match it returns the payload string; on a
mismatch it warns and discards the frame. Until a complete, CRC-valid frame has
arrived it returns C<undef>.

The C<$start> and C<$end> delimiter characters must not occur inside the payload,
or the frame will be cut short. Any other byte value is fine, including binary
data - the two CRC bytes are read by position, so they may take any value.

=head2 The checksum

L</crc($string)> is a CRC-16 with polynomial C<0x8408> (the reflected form of the
CCITT C<0x1021>), initial value C<0xFFFF>, reflected input and output, and a
final XOR of C<0xFFFF> - that is, B<CRC-16/X-25> - with the two bytes of the
result swapped before it is returned. An empty string hashes to C<0>. Because
both ends use this same function, the reflection and byte-swap cancel out and the
framing simply works; the swap only matters if you compare the value against an
outside CRC-16 implementation.

=head2 Example

Send and receive CRC-framed messages. This works between two devices running the
same protocol, or on a single Pi with TX (GPIO 14) wired to RX (GPIO 15):

    use RPi::Serial;

    my $s = RPi::Serial->new('/dev/ttyAMA0', 115200);

    my @messages = ('PING', 'temp=23.5C', 'cmd:led=on;pin=17');

    # Transmit each message as its own CRC-framed packet
    for my $msg (@messages) {
        $s->tx($msg, '<', '>');
    }

    # Receive them back. rx() yields one payload per complete, CRC-valid frame
    # and undef in between, so poll it while there are bytes to consume.
    my @received;

    while (@received < @messages) {
        next if $s->avail < 1;            # nothing to read yet

        my $frame = $s->rx('<', '>');     # advances one byte per call
        push @received, $frame if defined $frame;
    }

    print "received: $_\n" for @received; # PING / temp=23.5C / cmd:led=on;pin=17

    $s->close;

On a real link you would also bound the wait - a timeout or a maximum number of
polls - so a lost or corrupted frame cannot block the loop forever.

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2026 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
