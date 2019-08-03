use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyS0', 9600);

my $data;

for (qw(x [[[hello]]] ! [[[world]]] a b)){
    # x     = reset because no start marker yet
    # [[[   = start data ok
    # hello = data
    # ]]]   = end data ok
    # !     = RX reset command
    # [[[   = start data ok
    # world = data
    # ]]]   = end data ok
    # a     = no start markers set, reset
    # b     = no start markers set, reset

    $s->puts($_);
}

