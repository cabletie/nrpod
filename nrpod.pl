#!/usr/bin/perl -w
# Version 0.7
# ToDo:
# 1. Get cdbxpcmd.exe to sucessfully write mutiple tracks to CD (currenlty failes with pure virtual function call)
# fix concatenating mp3s with ffmpeg
# 2. add GUI to allow selection of sermon tracks
# 3. create selected tracks into one MP3 for sermon upload
# 4. FTP sermon MP3 to server
# 5. Configure server for new sermon


use XML::Smart;
use POSIX qw(strftime);
use File::Basename;
use Switch;
use Getopt::Long;
use Pod::Usage;

my $debug = 0;

my $doing_existing = 0;

my $nowString;
my $projectTemplateFilename;
my $projectFilename;
my $projectFilePath;
my $projectName;
my $AUP;
my $recordingsDirectoryName = "service_recordings";
my $recordingsDirectory;
my $projectDirectory;
my $projectDataDirectory;
my $wavOutputDirectoryName = "wav";
my $wavDirectory;
my $mp3OutputDirectoryName = "mp3";
my $mp3Directory;
my $worshipServiceSuffix = "_service";
my $audacityProjectFilename = "_audacity_project";
my $wavFilenamePrefix;
my $pathToFfMpeg;
my $pathToLame;
my $newAlbumString;
my $mp3GenreString;
my $mp3YearString;
my $mp3ArtistNameString;
my $pathToCdBurnerXp;
my $pathToCreateCD;
my %drives;
my %blanks;
my $windows;

#my $machine ="chippy";
#my $machine ="multimedia";

# Check for existence of and create directory if needed
sub checkDirectory {
        $dtc = shift;
        if (! -e $dtc) {
                mkdir($dtc) or die "Can't create dtc:$!\n";
        }
        print "$dtc\n" if $debug>2;
}

sub loadConfig {
        # Figure out which machine we're on
        chomp(my $hostname = `hostname`);
        print "hostname: $hostname\n" if $debug > 1;
        $pathToFfMpeg = "C:/Program Files/Audacity 1.3.8 Beta (Unicode)/ffmpeg.exe";
        $pathToAudacity = "C:/Program Files/Audacity 1.3 Beta (Unicode)/audacity.exe";
        $pathToCdBurnerXp = "C:/Program Files/CDBurnerXP/cdbxpcmd.exe";

        switch ($hostname) {
                case /chippy/i       {
                        $baseDirectory = "D:/Users/peter/Documents/Audacity";
                        $pathToCreateCD = "D:/Users/peter/Documents/bin/CreateCD.exe";
			$windows = 1;
                        }
                # wav and mp3 destinations: D:\users\Helix Multimedia\service recordings\service_2009-07-19
                # aup project data: D:\users\Helix Multimedia\service recordings\2009-07-19_NRUC Worship_Service_data
                # wav filename format : 2009-07-19_NRUC Worship_Service-01.wav
                # CDBurnerXp: C:\Program Files\CDBurnerXP
                # Audacity: C:\Program Files\Audacity 1.3 Beta (Unicode)
                case /multimedia/i {
                        $baseDirectory = "D:/users/Helix Multimedia";
                        $pathToCreateCD = "D:/users/Helix Multimedia/bin/CreateCD.exe";
			$windows = 1;
                        }
                case /tilaph/i {
                        $baseDirectory = "/Users/peter/Documents/Audacity";
			$pathToAudacity = "/Applications/Audacity/Audacity.app";
		        $pathToFfMpeg = "ffmpeg";
			$pathToLame = "lame";
			$windows = 0;
		}
                die "unknown host: $hostname";
        }
        print "basedirectory: $baseDirectory\n" if $debug>1;
        
        # Now build the other useful path strings
        # Expected path for multimedia PC at NRUC shown in comments
        
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/
        checkDirectory($projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName");
        print "projectDirectory: $projectDirectory\n" if $debug>1;
        checkDirectory($projectDataDirectory = "$projectDirectory/$projectName"."_Data");
        print "projectDataDirectory: $projectDataDirectory\n" if $debug>1;
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/wav
        checkDirectory($wavDirectory = "$projectDirectory/$wavOutputDirectoryName");
        print "wavDirectory: $wavDirectory\n" if $debug>1;
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/mp3
        checkDirectory($mp3Directory = "$projectDirectory/$mp3OutputDirectoryName");
        print "mp3Directory: $mp3Directory\n" if $debug>1;
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/2009-07-19_audacity_project.aup
        $projectFilePath = "$projectDirectory/$projectName.aup";
        print "projectFilePath: $projectFilePath\n" if $debug>1;
        
        # Prefix for all wav files
        $wavFilenamePrefix = "$projectName";

        # Locate template file
        # D:/users/Helix Multimedia/service_recordings/template.aup
        $projectTemplateFilename = "$baseDirectory/$recordingsDirectoryName/template.aup";
        -f $projectTemplateFilename || die "can't find template file: $projectTemplateFilename";
        
        # Create ALBUM text for the MP3 tags section
	$newAlbumString = "NRUC 9:30am service $nowString";
        $mp3GenreString = "Religious";
        $mp3YearString = strftime "%Y", localtime;
        $mp3ArtistNameString = "North Ringwood Uniting Church";
}
sub promptUser {
   local($promptString,$defaultValue) = @_;
   if ($defaultValue) {
      print $promptString, "[", $defaultValue, "]: ";
   } else {
      print $promptString, ": ";
   }
   $| = 1;               # force a flush after our print
   $_ = <STDIN>;         # get the input from STDIN (presumably the keyboard)
   chomp;
   if ("$defaultValue") {
      return $_ ? $_ : $defaultValue;    # return $_ if it has a value
   } else {
      return $_;
   }
}

sub makeNewProject {
	##############################################
	# Create audacity project file from template
	# Set meta data (tags) for date etc
	##############################################

	#Create a filename for the new project
	#$projectFilename = $nowString."_service.aup";
	print "Creating new project file '$projectFilename' from '$projectTemplateFilename'\n";

	# Open the template aup file
	my $TEMPLATE = XML::Smart->new($projectTemplateFilename);

	# Set ALBUM MP3 tags string
	$TEMPLATE->{project}{tags}{tag}('name','eq','ALBUM'){'value'} = $newAlbumString;

	# Save to a new project file
	$TEMPLATE->save("$projectDirectory/$projectFilename");
}

sub runAudacity {
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
        -f $projectFilePath || die "Can't find $projectFilePath\n";
        # convert to backslash paths for windows
        my $runPath = $projectFilePath;
        $runPath =~ s!/!\\!g if $windows;
	print "Running audacity with $runPath ... " if $debug>1;
	@args = ("open", "-W", "$pathToAudacity", "$runPath");
	system(@args) == 0 or die "system @args failed: $?";
	print "finished\n" if $debug>1;
}

sub convertWav2Mp3 {
        my $trackTitle = shift;
        my $trackNumber = shift;
	my $numberOfTracks = shift;
        my $wav = shift;
        my $mp3 = shift;
	@args = ("$pathToLame", $debug>1?"--quiet":"",
                 "--tl", "$newAlbumString",
                 "--ty", $mp3YearString,
                 "--tt",  "$trackTitle",
                 "--tn", $trackNumber."/".$numberOfTracks,
                 "--ta", "$mp3ArtistNameString",
		 "--tg", "$mp3GenreString",
		 $wav,
                 $mp3);
	print "Running: @args" if $debug > 2;
	system(@args) == 0 or die "system @args failed: $!";
	print "finished\n" if $debug > 2;
}

sub runFfMpeg {
        my $trackTitle = shift;
        my $trackNumber = shift;
        my $wav = shift;
        my $mp3 = shift;
	@args = ("$pathToFfMpeg","-y",
                 "-i", $wav,
                 "-album", $newAlbumString,
                 "-year", $mp3YearString,
                 "-title",  $trackTitle,
                 "-track", $trackNumber,
                 "-author", $mp3ArtistNameString,
                 #"-metadata", "Genre=$mp3GenreString",
                 $mp3);
	print "Running: @args" if $debug > 1;
	system(@args) == 0 or die "system @args failed: $!";
	print "finished\n" if $debug > 1;
}

sub checkTracks {
	my $errors_found = 0;
	##############################################
	# when we return (audacity exits)
	# check labels - times, illegal characters
	# check all wav files exist
	##############################################
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "Checking that exported wav files match Tracks and there are no non-zero length labels\n" if $debug;
	print "Looking in $wavDirectory for wav files\n" if $debug>2;
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	print "found $numlabels tracks\n" if $debug>1;
	$errors_found++ unless $numlabels;
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		$t = $track->{t};
		$t1 = $track->{t1};
		print "checking track $ti: $title ($t:$t1)\n" if $debug>1;
                if ($t1 != $t) {
                        warn "label not zero length: $track->{title} : $track->{t} : $track->{t1}\n" if $debug;
                        # Fix it
                        print "fixing...\n" if $debug;
			$AUP->{project}{labeltrack}{label}[$ti-1]->{t1} = $AUP->{project}{labeltrack}{label}[$ti-1]->{t};
                        $track{t1} = $track{t};
			$errors_found++;
                }
		# Check the wav file exists
		my $tiString = sprintf("%02d", $ti);
		my $wavfile = "$wavDirectory/".$tiString."-$title.wav";
#		my $wavfile = "$wavDirectory/$wavFilenamePrefix-$ti.wav";
		if(-r $wavfile){
			$tr = "OK";
		}else {
			$tr = "missing";
			$errors_found++;
		}
		print "checking for $wavfile: $tr\n" if $debug>2;
#		`lame $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3`; 
#		`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavDirectory/$wavFilenamePrefix-$ti.mp3` if(-f $wavfile);
	}
	# Save to a new project file
	$AUP->save($projectFilePath);
        print "checkTracks: Found $errors_found errors: " if($errors_found);
	print "Finished Checking Tracks with $errors_found errors\n" if $debug>1;
        $errors_found;
} #checkTracks

sub makeMp3s
{
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
        print "Making MP3s\n"  if $debug;
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavDirectory for wav files\n" if $debug>2;
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		print "processing track $ti: $title\n" if $debug > 1;

		# Check the wav file exists
		my $tiString = sprintf("%02d", $ti);
		my $wavfile = "$wavDirectory/".$tiString."-$title.wav";
		if(-r $wavfile){
                        convertWav2Mp3($title, $ti, $numlabels, $wavfile, "$mp3Directory/".$tiString."-$title.mp3");
		}
	}
        print "Finished Making $numlabels MP3s"  if $debug > 1;
}

sub checkBlankMedia
{
        # returns number of blank media found and stored in %blanks
        print "Checking for drives to use\n" if $debug >1;
	print "Looking for CD-R(W) drives and blank disks: running \"drutil list\"\n" if $debug > 2;
        open (DRUTIL, "drutil list |") || die "can't fork drutil: $!\n";
        while (<DRUTIL>) {
                        print if $debug > 2;
                        # scan lines for "CD-Write: -R"
                        if (/^(\d)\s?(.*)/) {$drives{$1} = $2}
#                        my $driveLetter = $2;
                }
        close DRUTIL || die "can't close drutil pipe after list command: $!\n";
	my $foundCdr;
	my $isBlank;
	my $noMedia;
	foreach my $drive (keys %drives) {
		$foundCdr = 0;
		$isBlank = 0;
		$noMedia = 0;
		print "found{$drive: $drives{$drive}}\n" if $debug > 2;
		print "running \"drutil -drive $drive status\"\n" if $debug > 2;
		open (DRUTIL, "drutil -drive $drive status |") || die "problem running drutil: $!\n";
		while (<DRUTIL>) {
				print if $debug > 2;
				if (/TYPE:\s?CD-R/i) {$foundCdr = 1;print "aup: found CD-R\n" if $debug > 2};
				if (/Writability:.*(blank|overwritable)/i) {$isBlank = 1;print "aup: found Blank\n" if $debug > 2};
				if (/Type:.*no media inserted/i) {$noMedia = 1;print "aup: found no media\n" if $debug > 2};
		}
		if ($foundCdr && $isBlank) {$blanks{$drive} = 1};
		if ($noMedia) {$blanks{$drive} = 0 };
		close DRUTIL || die "can't close drutil pipe after status command: $!\n";
	}
	my $anyMedia;
	my @blanks;
        foreach my $drive (keys %blanks) {
		if ($blanks{$drive} == 1) {
			print "drive $drive has a writable CD-R in it\n" if $debug > 2;
			push @blanks,$drive;
		}
		$anyMedia |= $blanks{$drive};
	}
	@blanks;
}

sub BurnCD
{
        # PostScript-CDCover-1.0
        # AudioCd-2.0
        # Filesys-dfPortable-0.85
        # MP3-CreateInlayCard-0.06
	##############################################
	# Burn CD using the wav files and drutil
	##############################################
	my $drive = shift;
        my $wavFolder = shift;
	print "Burning drive $drive from $wavFolder\n" if $debug >1;
	@args = ("drutil", "burn",
		 "-audio",
		 "-noverify",
                 "-eject",
                 "-erase", 
                 "-drive", $drive,
                 "$wavFolder"
		);
        print "Running: @args" if $debug >2 ;
        system(@args) == 0 or die "system @args failed: $!";
        print "Finished Burning CD"  if $debug >1;
}

##############################
# main Program Start
##############################

# Options variables
my $audacity = 1;
my $help;
my $man;
my $burn;
my $mp3 = 1;

# Gather options and do help if needed or requested
GetOptions (
	'help|?' => \$help,
	'man' => \$man,
	'audacity!' => \$audacity,
	'mp3!' => \$mp3,
	'debug+' => \$debug,
	'burn!' => \$burn
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
print "audacity: $audacity\n" if $debug > 3;

# Grab remaining project name
my $filename = $ARGV[0];

#Generate a date string
$nowString = strftime "%Y-%m-%d", localtime;
print "today: $nowString\n" if $debug>3;

# Set $projectFilename if given on command line otherwise generate from today's date
if ($filename) {
        $doing_existing = 1;
        $projectFilename = $filename;
        $projectName = fileparse($projectFilename, ".aup");
} else {
        $projectName = "$nowString$audacityProjectFilename";
        $projectFilename = "$projectName.aup";
}

print "projectName: $projectName\n" if $debug>1;
print "projectFilename: $projectFilename\n" if $debug>1;

# Setup directories and load any config from ini file
loadConfig($projectName);

# Create a new projectfile if $filename not specified on command line
makeNewProject unless $filename;

# Run Audacity to capture recording
runAudacity if $audacity;

# Open today's aup file
print "checking project file: $projectFilePath\n" if $debug>0;
die "failed to open Audacity project file: $projectFilePath\n" unless -r $projectFilePath;

$AUP = XML::Smart->new($projectFilePath);

# Save to a backup project file unless one already exists
$AUP->save($projectFilePath . ".bak") unless (-f $projectFilePath . ".bak");

while(checkTracks) {
   my $r = promptUser ("Found missing wav files or incorrect label lengths.\nRe-run Audacity to re-export wav files?","Yes");
   if($r =~ /^Y/i) {runAudacity;}
   if($r =~ /^N/i) {print "Quitting\n"; exit;}
}

makeMp3s if $mp3;

if($burn) {
	my @blanks = checkBlankMedia;
	while($#blanks < 0 &&
	   promptUser ("No blank, writable CDs found\n[T]ry again or [S]kip burning?","Try Again") =~ /^T/i) {
		@blanks = checkBlankMedia;
	}
	if ($debug) {
		my $plural = $#blanks > 0?'s ':' ';
		print "Available blank, writable CD".$plural."in drive".$plural;
		print join(' and ',@blanks)."\n";
	}
	foreach my $drive (@blanks) {
		BurnCD($drive, $wavDirectory);
	}
}
exit;
# Generate MP3 files using ffmpeg - DONE
# Export labels to CDBurnerXP project file
# Run burner X2 discs
# print labels
# upload MP3s to FTP server/iTunes

die "failed to open Audacity project file: file not found" unless -r $filename;

## Create the object and load the file:
my $XML = XML::Smart->new($filename) ;

my $numlabels = $XML->{project}{labeltrack}{numlabels};
my $i=0;
my @llist = @{$XML->{project}{labeltrack}{label}};
while ($i<$numlabels){
	my $title = $XML->{project}{labeltrack}{label}[$i]{title};
	$title = $title;
	my $t = $XML->{project}{labeltrack}{label}[$i]{t};
	$t = $t;
	my $t1 = $XML->{project}{labeltrack}{label}[$i]{t1};
	$t1 = $t1;

	warn "label not zero length: $title : $t : $t1\n" if ($t1 != $t);
	# Fix it
	print "fixing...\n";
	$llist[$i]{t1} = $llist[$i]{t};


	print "$i: $XML->{project}{labeltrack}{label}[$i]{title}: $XML->{project}{labeltrack}{label}[$i]{t}\n";
	$i++;
}
#print $XML->{project}{tags}{tag}[0]{name};
#print $XML->{project}{tags}{tag}[1];
#print $XML->{project}{tags}{tag}[2];
my @tagslist = @{$XML->{project}{tags}{tag}};
#my @tagslist = $XML->{project}{tags}{tag}('@');
#@tagslist = @tagslist;
print "numtags: $#tagslist\n";
foreach my $tg (@tagslist) {
	print "$tg->{name}: $tg->{value}\n";
}

__END__
=head1 AUP

aup - Capture and process NRUC sermon podcast

=head1 SYNOPSIS

aup [options] [project name]

 Options:
   -help            brief help message
   -man             full documentation
   -noaudacity      don't run audacity
   
=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-noaudacity>

Skips running audacity - just processes the project file. Project file must already exist.

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=cut