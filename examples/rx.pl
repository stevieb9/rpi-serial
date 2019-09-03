use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $data;
my ($rx_started, $rx_ended) = (0, 0);

print $s->crc("hello", 5);
exit;

while (1){
    if ($s->avail){
        my $data_populated = rx('[', ']', '!');

        # print "rx_started: $rx_started, rx_ended: $rx_ended\n";

        if ($data_populated){
            print "$data\n";
            rx_reset();
        }
    }
}

sub rx {
    my ($start, $end, $rx_reset) = @_;

    my $c = chr($s->getc); # getc() returns the ord() val on a char* perl-wise

#     print ">$c<\n";

    if ($c ne $start && ! $rx_started){
        rx_reset();
        return;
    }
    if ($c eq $rx_reset){
        rx_reset();
        return;
    }
    if ($c eq $start){
        # print "start\n";
        $rx_started = 1;
        return;
    }
    if ($c eq $end){
        # print "end\n";
        $rx_ended = 1;
        return;
    }

    if ($rx_started && ! $rx_ended){
        $data .= $c;
    }

    if ($rx_started && $rx_ended){
        if (crc() == 14208 || crc() == 44210){
            return 1;
        }
        return 1;
    }
}
sub crc {
    my $msb = $s->getc;
    my $lsb = $s->getc;

    my $crc = ($msb << 8) | $lsb;

    return 0 if $msb == -1 || $lsb == -1;
    print "crc: $crc, msb: $msb, lsb: $lsb\n";
    return $crc;

}
sub rx_reset {
#    $s->flush;
    $rx_started = 0;
    $rx_ended = 0;
    $data = '';
}
