use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $data;
my ($rx_started, $rx_ended) = (0, 0);

while (1){
    if ($s->avail){
        rx(qw( [ ] 3 !));
    }
}

sub rx {
    my ($start, $end, $delim_count, $rx_reset) = @_;

    my $c = $s->getc;

    if (chr($c) ne $start && ! $rx_started == $delim_count){
        _reset();
        return;
    }
    if (chr($c) eq $rx_reset){
        _reset();
        return;
    }
    if (chr($c) eq $start){
        $rx_started++;
        return;
    }
    if (chr($c) eq $end){
        $rx_ended++;
    }
    if ($rx_started == $delim_count && ! $rx_ended){
        $data .= chr $c;
    }
    if ($rx_started == $delim_count && $rx_ended == $delim_count){
        print "$data\n";
        _reset();
    }
}
sub _reset {
    $rx_started = 0;
    $rx_ended = 0;
    $data = '';
}
