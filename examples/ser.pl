use strict;
use warnings;

use RPi::Serial;

my $s = RPi::Serial->new('/dev/ttyAMA0', 115200);

$s->putc(5);

my $c = $s->getc;
print "char: $c\n";

$s->puts("hello world");

my $str = $s->gets(8);

print "$str\n";

for (1..100){
    $s->putc($_);
    print $s->getc . "\n";
}

