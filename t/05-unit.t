use strict;
use warnings;

use Test::More;
use RPi::Serial;

# HW-free coverage. crc() runs the real XS crc16 (a pure function). Everything
# else blesses a bare object and stubs the XS transport funcs, so no port is
# opened. tty_close is neutralized for the whole file so DESTROY on any test
# object never touches a real fd.
{
    no warnings 'redefine';
    *RPi::Serial::tty_close = sub { };
}

# Pure-Perl reference of crc16.c (POLY 0x8408, init 0xFFFF, reflected, ~out,
# then the final byte-swap). Used to assert the XS crc() against real vectors.
sub ref_crc16 {
    my ($data) = @_;
    my $len = length $data;
    return 0 if $len == 0;   # crc16.c: length 0 returns ~0xFFFF == 0

    my $crc = 0xFFFF;
    for my $ch (split //, $data){
        my $byte = ord($ch) & 0xFF;
        for (1 .. 8){
            if (($crc & 1) ^ ($byte & 1)){
                $crc = (($crc >> 1) ^ 0x8408) & 0xFFFF;
            }
            else {
                $crc = ($crc >> 1) & 0xFFFF;
            }
            $byte >>= 1;
        }
    }
    $crc = (~$crc) & 0xFFFF;
    return ((($crc & 0xFF) << 8) | (($crc >> 8) & 0xFF)) & 0xFFFF;   # byte-swap
}

my $mod = 'RPi::Serial';

# --- crc() vectors: XS matches the documented algorithm ---
for my $vec ('', 'A', '123456789', "\x00\x01\x02\xff", 'RPi::Serial'){
    my $obj = bless {}, $mod;
    is $obj->crc($vec), ref_crc16($vec),
        sprintf('crc(%s) matches reference', $vec eq '' ? "''" : "'$vec'");
}

# --- new(): validation + open-failure croak (tty_open stubbed) ---
{
    no warnings 'redefine';

    eval { $mod->new() };
    like $@, qr/requires a serial device/, 'new(): missing device croaks';

    eval { $mod->new('/dev/x') };
    like $@, qr/positive integer baud/, 'new(): missing baud croaks';

    eval { $mod->new('/dev/x', 0) };
    like $@, qr/positive integer baud/, 'new(): baud 0 croaks';

    eval { $mod->new('/dev/x', 'fast') };
    like $@, qr/positive integer baud/, 'new(): non-integer baud croaks';

    local *RPi::Serial::tty_open = sub { -1 };
    eval { $mod->new('/dev/nope', 115200) };
    like $@, qr/could not open/, 'new(): failed open (fd<0) croaks';

    local *RPi::Serial::tty_open = sub { 7 };
    my $s = $mod->new('/dev/fake', 115200);
    isa_ok $s, $mod;
    is $s->fd, 7, 'new(): fd stored on a successful open';
}

# --- write(): valid bytes pack; invalid croak (no silent wrap) ---
{
    no warnings 'redefine';
    my @sent;
    local *RPi::Serial::tty_putc = sub { push @sent, $_[1] };
    my $s = bless {}, $mod;

    @sent = (); $s->write(65);  is $sent[0], chr(65),  'write(65)  -> 0x41';
    @sent = (); $s->write(0);   is $sent[0], chr(0),   'write(0)   -> 0x00';
    @sent = (); $s->write(255); is $sent[0], chr(255), 'write(255) -> 0xFF';

    eval { $s->write() };    like $@, qr/between 0 and 255/, 'write(undef) croaks';
    eval { $s->write(256) }; like $@, qr/between 0 and 255/, 'write(256) croaks (no wrap)';
    eval { $s->write(-1) };  like $@, qr/between 0 and 255/, 'write(-1) croaks';
    eval { $s->write('x') }; like $@, qr/between 0 and 255/, 'write(non-integer) croaks';
}

# --- tx(): emits start.data.end then CRC msb,lsb (frame characters as chars) ---
{
    no warnings 'redefine';
    my @wire;
    local *RPi::Serial::tty_putc = sub { push @wire, $_[1] };
    my $s = bless {}, $mod;

    $s->tx('AB', '<', '>');
    my $crc = ref_crc16('AB');
    is_deeply \@wire, ['<', 'A', 'B', '>', chr($crc >> 8), chr($crc & 0xFF)],
        'tx(): frame + CRC byte order';
}

# --- rx(): reassembly, pre-start discard, mid-frame undef, CRC-mismatch warn ---
{
    no warnings 'redefine';
    my @q;
    local *RPi::Serial::tty_getc      = sub { @q ? shift @q : -1 };
    local *RPi::Serial::tty_available = sub { scalar @q };

    my $fresh = sub { bless { rx_data => '', rx_started => 0, rx_ended => 0 }, $mod };

    my $crc = ref_crc16('AB');

    {
        my $s = $fresh->();
        @q = (ord('<'), ord('A'), ord('B'), ord('>'), $crc >> 8, $crc & 0xFF);
        my $out;
        $out = $s->rx('<', '>') while @q;
        is $out, 'AB', 'rx(): assembles a CRC-valid frame';
    }
    {
        my $s = $fresh->();
        @q = (ord('<'), ord('A'));
        $s->rx('<', '>');                 # consume start
        is $s->rx('<', '>'), undef, 'rx(): returns undef (not 0) while assembling';
    }
    {
        my $s = $fresh->();
        @q = (ord('X'));
        is $s->rx('<', '>'), undef, 'rx(): character before start is discarded';
        ok ! $s->{rx_started}, '  frame not started by a pre-start char';
    }
    {
        my $s = $fresh->();
        @q = (ord('<'), ord('A'), ord('B'), ord('>'), 0x00, 0x00);   # wrong CRC
        my $warn = '';
        local $SIG{__WARN__} = sub { $warn .= $_[0] };
        my $out;
        $out = $s->rx('<', '>') while @q;
        is $out, undef, 'rx(): CRC mismatch returns undef';
        like $warn, qr/mismatching CRC/, '  warns on CRC mismatch';
    }
}

# --- flush(): calls tty_flush with the fd ---
{
    no warnings 'redefine';
    my $flushed;
    local *RPi::Serial::tty_flush = sub { $flushed = $_[0]; return 0 };
    my $s = bless { fd => 9 }, $mod;
    $s->flush;
    is $flushed, 9, 'flush(): invokes tty_flush on the fd';
}

done_testing();
