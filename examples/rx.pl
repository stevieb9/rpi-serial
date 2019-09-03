use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $data;
my ($rx_started, $rx_ended) = (0, 0);

while (1){
    if ($s->avail){
        my $data_populated = rx('[', ']', '!');

        if ($data_populated){
            print "$data\n";
            rx_reset();
        }
    }
}

sub rx {
    my ($start, $end, $rx_reset) = @_;

    my $c = chr($s->getc); # getc() returns the ord() val on a char* perl-wise

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
#        return;
    }
    if ($rx_started && ! $rx_ended){
        $data .= $c;
    }
    if ($rx_started && $rx_ended){
        my $r_crc = get_crc();
        my $c_crc = calc_crc($data, 5);

        if ($r_crc == $c_crc){
            return 1;
        }

        return;
    }
}
sub calc_crc {
    my ($data) = @_;
    return $s->crc($data, length $data);
}
sub get_crc {

    my ($msb, $lsb);

    while ($s->avail < 2){}

    $msb = $s->getc;
    $lsb = $s->getc;

    my $crc = ($msb << 8) | $lsb;

    print "crc: $crc, msb: $msb, lsb: $lsb\n";

    return  if $msb == -1 || $lsb == -1;
    return $crc;

}
sub rx_reset {
#    $s->flush;
    $rx_started = 0;
    $rx_ended = 0;
    $data = '';
}
