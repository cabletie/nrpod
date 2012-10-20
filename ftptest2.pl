#!/usr/bin/perl -w

use File::Basename;

sub uploadPodcast {
    my $srcFilePath = shift;
    my $ftpHost = "nruc.org.au";
    my $ftpPath = "/httpdocs/podcast/";
    my $ftpLogin = "nruc";
    my $ftpPassword = "church123";
    
    print "Uploading podcast ",basename($srcFilePath),"\n";

    my @args = ("ftp", "-v", "-u");
    push @args, "ftp://" . $ftpLogin . ":" . $ftpPassword . "\@" . $ftpHost . $ftpPath, $srcFilePath;

    print "Running ", join (":",@args), "\n";
    system(@args) == 0 or (print "File upload failed ($!)\n");	
}

uploadPodcast("test-file.rdm");
exit;
