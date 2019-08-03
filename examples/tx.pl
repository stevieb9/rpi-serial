use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyS0', 9600);

my $data;

for ('[[[hello]]]', '!', '[[[world]]]'){
    $s->puts($_);
    #select(undef, undef, undef, 0.3);
}

