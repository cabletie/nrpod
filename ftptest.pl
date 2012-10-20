#!/usr/bin/perl -w

use Net::FTP;

#use strict;
$|++;
my $VERSION = "1.0";

# Progress Bar: Term::ProgressBar - progress bar with LWP.
# http://disobey.com/d/code/ or contact morbus@disobey.com.
# Original routine by tachyon at http://tachyon.perlmonk.org/
#
# This code is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#

# make sure we have the modules we need, else die peacefully.
eval("use LWP 5.6.9;"); 
die "[err] LWP is not the required version.\n" if $@;
eval("use Term::ProgressBar;"); # prevent word-wrapping.
die "[err] Term::ProgressBar not installed.\n" if $@;

my $debug = 0;
my $hashes = 0;  # our downloaded data.
my $total_size;      # total size of the file in bytes.
my $progress;        # progress bar object.
my $next_update = 0; # reduce ProgressBar use.

if (open(HASHES, "-|")) {
	# Parent
	$total_size = -s "./test-file.rdm";
	my $total_hashes = int($total_size / 1024);
	
	# initialize our progress bar.
	$progress = Term::ProgressBar->new({count => $total_hashes, ETA => 'linear'});
	$progress->minor(0);           # turns off the floating asterisks.
	$progress->max_update_rate(1); # only relevant when ETA is used.
	# Update progress bar as we count ashes
	while (<HASHES>) {
		$hashes .= $_;
		$next_update = $progress->update(length($hashes))if length($hashes) >= $next_update;
		print STDERR length($hashes), "\n";
		print STDERR $_;
	}
	# top off the progress bar.
	$progress->update($total_hashes);
}
else {
	# Child
#	STDOUT->autoflush(1);
	$|++;
	uploadPodcast("./test-file.rdm");
	exit;
}


sub uploadPodcast {
	#my $srcFilePath = shift;
	#my $ftpHost = "snoopy.bigpond";
	#my $ftpPath = ".";
	#my $ftpLogin = "peter";
	#my $ftpPassword = "Rgrt0Thng";
	
	my $srcFilePath = shift;
	my $ftpHost = "nruc.org.au";
	my $ftpPath = "/httpdocs/podcast/";
	my $ftpLogin = "nruc";
	my $ftpPassword = "church123";

print STDERR "to STDERR\n";
print STDOUT "to STDOUT\n";

	my $ftpConn = Net::FTP->new($ftpHost, Debug => $debug, Hash => \*STDOUT)
		or warn "Cannot connect to $ftpHost: $@";
	STDOUT->autoflush(1);
	$|++;
	$ftpConn->login($ftpLogin,$ftpPassword)
		or warn "Cannot login ", $ftp->message;
	$ftpConn->cwd($ftpPath)
		or die "Cannot change working directory ", $ftp->message;
	$ftpConn->binary()
		or warn "set binary mode failed ", $ftp->message;
	$ftpConn->put($srcFilePath)
		or warn "FTP put failed ", $ftp->message;
	$ftpConn->quit;
	print "Done uploading podcast\n";
}


#close HASHES;