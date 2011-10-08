#!/usr/bin/perl -w
my $debug = 4;
my $pathToCdBurnerXp = "C:/Program Files/CDBurnerXP/cdbxpcmd.exe";
my $pathToCreateCD = "D:/Users/peter/Documents/bin/CreateCD.exe";
print "checking for drives to use\n" if $debug >1;
open (CDBXP, "\"$pathToCdBurnerXp\" --list-drives |") || die "can't fork $pathToCdBurnerXp: $!\n";
my %drives;
my %blanks;
while (<CDBXP>) {
                print if $debug > 1;
                # scan lines for 0: LITE-ON DVDRW LH-20A1H (E:\)
                if (/(\d):\s.*\((.):\\\)/) {$drives{$2} = $1}
        }
close CDBXP || die "can't close $pathToCdBurnerXp: $!\n";
#foreach (keys %drives) {
#                print "$_: $drives{$_}\n";
#                open (CDBXP, "\"$pathToCdBurnerXp\" --eject -device:$drives{$_} |") || die "can't fork $pathToCdBurnerXp: $!\n";
#                                print <CDBXP> if $debug > 1;
#                close CDBXP || die "can't close $pathToCdBurnerXp: $!\n";
#}
#foreach (keys %drives) {
#                print "$_: $drives{$_}\n";
#                open (CDBXP, "\"$pathToCdBurnerXp\" --load -device:$drives{$_} |") || die "can't fork $pathToCdBurnerXp: $!\n";
#                                print <CDBXP> if $debug > 1;
#                close CDBXP || die "can't close $pathToCdBurnerXp: $!\n";
#}
foreach my $drive (keys %drives) {
                print "$drive: $drives{$drive}\n";
                open (CDBXP, "\"$pathToCreateCD\" -info -r:$drive -nologo|") || die "can't fork $pathToCreateCD: $!\n";
                while (<CDBXP>) {
                                print if $debug > 2;
                                next unless /Writable Blank/;
                                $blanks{$drive} = $&;
                }
                close CDBXP || die "can't close $pathToCreateCD: $!\n";
}
foreach (keys %blanks) {print "drive $_ has a blank CD in it\n";}