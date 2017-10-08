#!env perl
#use kkmdrv;
use strict;
use v5.10;
use IO::Handle qw( );  # For autoflush
use Device::SerialPort;
#use Text::Iconv;

my $debug=0;
my $port="/dev/cu.SLAB_USBtoUART";
my $com = new Device::SerialPort ($port, 1);
die "Can't open port" unless $com;

$com->user_msg("ON");
$com->databits(7);
$com->baudrate(19200);
$com->parity("none");
$com->stopbits(1);
$com->handshake("none");

#$com->baudrate(2400);
#$com->parity("odd");

$com->read_char_time(1);    # don't wait for each character
$com->read_const_time(100); # 1 second per unfulfilled "read" call
 
$com->write_settings || undef $com;

#$com->save("com.cfg");

my $STALL_DEFAULT=1; # how many seconds to wait for new input
my $timeout=$STALL_DEFAULT;

my $s=0;
my $flushed=0;
my $mode={
    0x3b => {
        mode => 'Voltage',
        unit => 'V',
        range => [
            [0.001], [0.01],  [0.1],  [1], [0.1, 'm']
        ],
        acdc=>1,
        sub=>'Hz',
    },
    0x33 => {
        mode => 'Resistance',
        unit => 'Ω',
        range => [
            [0.1], [0.001,'K'],  [0.01,'K'],  [0.1,'K'], [0.001,'M'], [0.01,'M']
        ]
    },
    0x30 => { #66.00A
        mode => 'Current',
        unit => 'A',
        range => [
            [0.01]
        ],
        acdc=>1,
        sub=>'Hz',
    },
    0x39 => { #manual A
        mode => 'Current',
        unit => 'A',
        range => [ [0.001], [0.01], [0.1], [1] ],
        acdc=>1,
        sub=>'Hz',
    },
     0x3d => { #uA
        mode => 'Current',
        unit => 'A',
        range => [ [0.1, 'u'],[1, 'u'] ],
        acdc=>1,
        sub=>'Hz',
    },
    0x3f => { #mA
        mode => 'Current',
        unit => 'A',
        range => [ [0.01, 'm'],[0.1, 'm'] ],
        acdc=>1,
        sub=>'Hz',
     },
    0x32 => { #Freq
        mode => 'Freq',
        unit => 'Hz',
        range => [ [0.01],[0.1],[1],[10],[100],[1000],[10000] ],
        acdc=>1,
        sub=>'%',
    },
    0x36 => {
        mode => 'Capacitance',
        unit => 'F',
        range => [
            [0.001, 'n'], [0.01, 'n'],  [0.1, 'n'],  
            [0.001, 'u'], [0.01, 'u'],  [0.1, 'u'],  
            [0.001, 'm'], [0.01, 'm'],  
        ]
    },


};

my $pv=-1;
while(1){
    my($c,$b)=$com->read(17);
    if($c){
	my @bytes = map { ord ($_) } split //, $b;
        my $tm=undef;
        my $invalid=0;
        my $unit='?';
        my $value=0;
        my $dunit='?';
        my $cm=$mode->{$bytes[10]};
        my $acdc='';

        for(2..9){
            if($bytes[$_]>=0x30 && $bytes[$_]<=0x39){
                $bytes[$_]-=0x30;
            }else{
                $invalid=1;
            }
        }

        my $m=$bytes[2]*1000+$bytes[3]*100+$bytes[4]*10+$bytes[5];
        my $sunit='';
        my $s=0;

        if($cm){
            $tm=$cm->{mode};

            my $mrange;
            if($bytes[0]>=0x30 && $bytes[0]<=0x39){
                $mrange=$cm->{range}->[$bytes[0]-0x30];
            }else{
                $invalid='range';
            }

            $unit=$cm->{unit};
            if($mrange){
                $m=$mrange->[0]*$m;
                $value=$m;
                if($mrange->[1]){
                    $dunit=$mrange->[1].$unit;
                    if($mrange->[1] eq 'm'){
                        $value/=1000;
                    }elsif($mrange->[1] eq 'u'){
                        $value/=1000000;
                    }elsif($mrange->[1] eq 'n'){
                        $value/=1000000000;
                    }elsif($mrange->[1] eq 'K'){
                        $value*=1000;
                    }elsif($mrange->[1] eq 'M'){
                        $value*=1000000;
                    }
                }else{
                    $dunit=$unit;
                }
            }else{
                $invalid='mul';
            }


            $m*=-1 if($bytes[12]&1); #negative

            if($cm->{acdc}){
                if($bytes[12]&4){
                    $acdc='AC';
                }elsif($bytes[12]&8){
                    $acdc='DC';
                }
            }


            if($cm->{sub}){
                $s=$bytes[6]*10+$bytes[7]+$bytes[8]/10+$bytes[9]/100;
                $sunit=$cm->{sub};
                if($bytes[1]>=0x30 && $bytes[1]<=0x39){
                    my $msub=$bytes[1]-0x30;
                    $s*=10**$msub;
                }else{
                    $invalid=1;
                }
                if($bytes[13]&4){ #overflow
                    $s=(9**9**9);
                }
                if($cm->{sub} eq 'Hz' && !($bytes[14]&1)){
                    $sunit=undef;
                }
            }

            if($bytes[13]&8){ #overflow
                $m=(9**9**9);
            }


        }elsif($bytes[10] == 0x35){
            $tm="Continiuty [unsupported]";
        }elsif($bytes[10] == 0x31){
            $tm="Diode [unsupported]";
        }elsif($bytes[10] == 0x34){
            $tm="Temp [unsupported]";
        }else{
            $tm="unknown";
            $invalid='mode '.$bytes[10];
        }
        


        if($invalid){
            say("INVALID ".$invalid);
        }else{
            if($value!=$pv){
                printf "%10s %7.3f %s %s", 
                $tm, $m, $dunit, $acdc;
                if($sunit){
                    printf " [ %5.2f %s ]", $s, $sunit;
                }
                printf "     (%10.4f %s)", $value, $unit;
                printf("\n");
                $pv=$value;
            }
        }
    }
}


$com->close || die "failed to close";
undef $com;


