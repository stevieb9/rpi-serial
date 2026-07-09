use strict;
use warnings;

use Test::More;
use RPi::Serial;

# Live loopback test: requires the serial TX wired directly to RX. Enable with
# RPI_SERIAL_LOOPBACK=1; override the device with RPI_SERIAL_DEV (defaults to
# /dev/ttyAMA0, the Pi 5 header UART). Skipped otherwise so it is inert on
# CPAN testers and unwired machines.

plan skip_all => "RPI_SERIAL_LOOPBACK not set (needs serial TX wired to RX)"
    if ! $ENV{RPI_SERIAL_LOOPBACK};

my $dev  = $ENV{RPI_SERIAL_DEV} // '/dev/ttyAMA0';
my $baud = 115200;

my $s = RPi::Serial->new($dev, $baud);
isa_ok $s, 'RPi::Serial';
ok defined $s->fd && $s->fd >= 0, "opened $dev (fd @{[ $s->fd ]})";

# Single byte round-trip
$s->flush;
$s->write(0x41);
is _read_byte($s), 0x41, 'byte round-trip: 0x41';

# String round-trip
$s->flush;
$s->puts('hello');
select(undef, undef, undef, 0.05);
is $s->gets(5), 'hello', 'string round-trip: hello';

# CRC-framed tx()/rx() round-trip
for my $payload ('AB', 'hello', 'RPi::Serial rocks!'){
    $s->flush;
    $s->tx($payload, '<', '>');
    select(undef, undef, undef, 0.05);

    my $frame;
    for (1 .. 500){
        $frame = $s->rx('<', '>');
        last if defined $frame;
        select(undef, undef, undef, 0.002);
    }

    is $frame, $payload, "tx/rx CRC frame round-trip: '$payload'";
}

# flush() discards buffered input
$s->puts('junk');
select(undef, undef, undef, 0.05);
$s->flush;
is $s->avail, 0, 'flush(): discards buffered input';

$s->close;

done_testing();

sub _read_byte {
    my ($s) = @_;
    for (1 .. 500){
        return $s->getc if $s->avail >= 1;
        select(undef, undef, undef, 0.002);
    }
    return undef;
}
