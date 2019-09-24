use warnings;
use strict;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyUSB0', 9600);

my $beg = '[';
my $end = ']';

while (1){
    if ($s->avail){
        my $data = rx($beg, $end);

        if (defined $data){
            print "$data\n";
        }
    }
}

