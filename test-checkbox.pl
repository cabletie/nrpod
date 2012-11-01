#!/usr/bin/perl
use strict;
use warnings;
use Term::ReadLine;

my $term = Term::ReadLine->new($0);
my $gui = 1;
my $pathToCD = "/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog";

my %cbs;
$cbs{one} = "track one";
$cbs{two} = "track two";
$cbs{three} = "track three";

print @cbs;

#print promptUserForTracks("Select Tracks to burn",'Totaltime is: 01h:45m:23s',qw/"01 Track this" "02 Track this" "03 Track this" "04 Track this"/) . "\n";

sub promptUserForTracks {
	my ($title,$label,@tracks) = @_;
	my ($rv, $cdrv, @rv, $boxes, @boxes);
	my $defaultValue = "1-20";
	if($gui) {
		$cdrv = `$pathToCD checkbox --title $title --label $label --width 600 --button1 OK --debug --items @tracks`;
		print $cdrv;
		my ($button, $boxes) = split /\n/, $cdrv;
		(@boxes) = split /\s/,$boxes;
		if($button == 1) # OK button pushed 
			{
				my $boxnum = 1;
				foreach my $box (@boxes) 
				{
					push @rv, $boxnum if ($box == 1);
					$boxnum++;
				}
				$rv = join (',',@rv);
			}
			else {
				return "unrecognised response from CocoaDialog line: $.\n";
			} 
	} else { # terminal interface only
		$rv = $term->readline("$title ",$defaultValue);
	}
	return $rv;	
}
