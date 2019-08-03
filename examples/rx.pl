use warnings;
use strict;

use constant {
    DELIM_COUNT => 3,
    RX_RESET    => '!'
};

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $data;
my ($rx_started, $rx_ended) = (0, 0);

while (1){
    if ($s->avail){
        rx('[', ']');
    }
}

sub rx {
    my ($start, $end) = @_;

    my $c = $s->getc;

    if (chr($c) ne $start && ! $rx_started == DELIM_COUNT){
        _reset();
        return;
    }
    if (chr($c) eq $start){
        $rx_started++;
        return;
    }
    if (chr($c) eq ']'){
        $rx_ended++;
    }
    if ($rx_started == DELIM_COUNT && ! $rx_ended){
        $data .= chr $c;
    }
    if ($rx_started == DELIM_COUNT && $rx_ended == DELIM_COUNT){
        print "$data\n";
        _reset();
    }
}
sub _reset {
    $rx_started = 0;
    $rx_ended = 0;
    $data = '';
}
