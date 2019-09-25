package RPi::Serial;

use strict;
use warnings;

our $VERSION = '3.01';

require XSLoader;
XSLoader::load('RPi::Serial', $VERSION);

sub new {
    my ($class, $device, $baud) = @_;

    my $self = bless {
        rx_data     => '',
        rx_started  => 0,
        rx_ended    => 0,
    }, $class;

    $self->fd(tty_open($device, $baud));

    return $self;
}
sub close {
    tty_close($_[0]->fd);
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
    my $buf = "";
    my $char_ptr = tty_gets($_[0]->fd, $buf, $_[1]);
    my $unpacked = unpack "A*", $char_ptr;
    return $unpacked;
}
sub write {
    my ($self, $byte) = @_;
    if (! defined $byte){
        die "write() requires a byte of data sent in\n";
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
}
sub tx {
    my ($self, $data, $tx_start, $tx_end) = @_;

    my $crc = $self->crc($data);
    my $crc_msb = $crc >> 8;
    my $crc_lsb = $crc & 0xFF;

    my $tx = $tx_start . $data . $tx_end;

    for (split //, $tx){
        $self->write($_);
    }

    $self->write($crc_msb);
    $self->write($crc_lsb);
}
sub DESTROY {
    tty_close($_[0]->fd);
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

    my $dev  = "/dev/ttyAMA0";
    my $baud = 115200;
    
    my $ser = RPi::Serial->new($dev, $baud);

    $ser->putc(5);
    $ser->puts("hello, world!");

    my $char = $ser->getc;

    my $num_bytes = 12;
    my $str  = $ser->gets($num_bytes);

    my $crc = $ser->crc($str);

    $ser->flush;

    my $bytes_available = $ser->avail;

    $ser->close;

=head1 DESCRIPTION

Provides basic read and write functionality of a UART serial interface

=head1 WARNING

If using on a Raspberry Pi platform:

In order to use GPIO pins 14 and 15 as a serial interface on the Raspberry Pi,
you need to disable the built-in Bluetooth adaptor. This distribution will not
operate correctly without this being done.

To disable Bluetooth on the Pi, edit the C</boot/config.txt>, and add the
following line:

    dtoverlay=pi3-disable-bt-overlay

Save the file, then reboot the Pi.

=head1 METHODS

=head2 new($device, $baud);

Opens the specified serial port at the specified baud rate, and returns a new
L<RPi::Serial> object.

Parameters:

    $device

Mandatory, String: The serial device to open (eg: C<"/dev/ttyAMA0">.

    $baud

Mandatory, Integer: A valud baud rate to use.

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

Read a specified number of bytes into a string.

Parameters:

    $num_bytes

Mandatory, Integer; The number of bytes to read. If this number is larger than
what is available to be read, a 10 second timeout will briefly hand your
application.

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

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2019 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
