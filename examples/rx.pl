use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $data;
my ($rx_started, $rx_ended) = (0, 0);

while (1){
    if ($s->avail){
        my $data_populated = rx('[', ']', 3, '!');

        if ($data_populated){
            print "$data\n";
            rx_reset();
        }
    }
}

sub rx {
    my ($start, $end, $delim_count, $rx_reset) = @_;

    my $c = chr($s->getc); # getc() returns the ord() val on a char* perl-wise

    if ($c ne $start && ! $rx_started == $delim_count){
        rx_reset();
        return;
    }
    if ($c eq $rx_reset){
        rx_reset();
        return;
    }
    if ($c eq $start){
        $rx_started++;
        return;
    }
    if ($c eq $end){
        $rx_ended++;
    }
    if ($rx_started == $delim_count && ! $rx_ended){
        $data .= $c;
    }
    if ($rx_started == $delim_count && $rx_ended == $delim_count){
        return 1;
    }
}
sub rx_reset {
    $rx_started = 0;
    $rx_ended = 0;
    $data = '';
}
