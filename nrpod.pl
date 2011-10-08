#!/usr/bin/perl -w
# Version 0.6
use XML::Smart;
use POSIX qw(strftime);
use File::Basename;
use Switch 'Perl6';

my $debug = 1;
my $doing_existing = 0;

my $filename = $ARGV[0];
my $nowString;
my $projectTemplateFilename;
my $projectFilename;
my $projectFilePath;
my $projectName;
my $AUP;
my $recordingsDirectoryName = "service_recordings";
my $recordingsDirectory;
my $projectDirectory;
my $wavOutputDirectoryName = "wav";
my $wavDirectory;
my $mp3OutputDirectoryName = "mp3";
my $mp3Directory;
my $worshipServiceSuffix = "_service";
my $audacityProjectFilename = "_audacity_project";
my $wavFilenamePrefix;
my $pathToFfMpeg;
my $newAlbumString;
my $mp3GenreString;
my $mp3YearString;
my $mp3ArtistNameString;
my $pathToCdBurnerXp;
my $pathToCreateCD;
my %drives;
my %blanks;

#my $machine ="chippy";
#my $machine ="multimedia";

# Check for existence of and create directory if needed
sub checkDirectory {
        $dtc = shift;
        if (! -e $dtc) {
                mkdir($dtc) or die "Can't create dtc:$!\n";
        }
        print "$dtc\n" if $debug>3;
}

sub loadConfig {
        # Figure out which machine we're on
        chomp(my $hostname = `hostname`);
        print "hostname: $hostname\n" if $debug > 1;
        $pathToFfMpeg = "C:/Program Files/Audacity 1.3.8 Beta (Unicode)/ffmpeg.exe";
        $pathToAudacity = "C:/Program Files/Audacity 1.3 Beta (Unicode)/audacity.exe";
        $pathToCdBurnerXp = "C:/Program Files/CDBurnerXP/cdbxpcmd.exe";

        given ($hostname) {
                when "chippy"       {
                        $baseDirectory = "D:/Users/peter/Documents/Audacity";
                        $pathToCreateCD = "D:/Users/peter/Documents/bin/CreateCD.exe";
                        }
                # wav and mp3 destinations: D:\users\Helix Multimedia\service recordings\service_2009-07-19
                # aup project data: D:\users\Helix Multimedia\service recordings\2009-07-19_NRUC Worship_Service_data
                # wav filename format : 2009-07-19_NRUC Worship_Service-01.wav
                # CDBurnerXp: C:\Program Files\CDBurnerXP
                # Audacity: C:\Program Files\Audacity 1.3 Beta (Unicode)
                when "multimedia" {
                        $baseDirectory = "D:/users/Helix Multimedia";
                        $pathToCreateCD = "D:/users/Helix Multimedia/bin/CreateCD.exe";
                        }
                else { die "unknown host: $hostname"};
        }
        print "basedirectory: $baseDirectory\n" if $debug>1;
        
        # Now build the other useful path strings
        # Expected path for multimedia PC at NRUC shown in comments
        
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/
        checkDirectory($projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName");
        print "projectDirectory: $projectDirectory\n" if $debug>1;
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

sub makeNewProject
{
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
	$TEMPLATE->save($projectDirectory/$projectFilename);
}

sub runAudacity
{
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
        -f $projectFilePath || die "Can't find $projectFilePath\n";
        # convert to backslash paths for windows
        my $runPath = $projectFilePath;
        $runPath =~ s!/!\\!g;
	print "Running audacity with $runPath ... " if $debug>1;
	@args = ("$pathToAudacity", "$runPath");
	system(@args) == 0 or die "system @args failed: $?";
	print "finished\n" if $debug>1;
}

sub runFfMpeg
{
        my $trackTitle = shift;
        my $trackNumber = shift;
        my $wav = shift;
        my $mp3 = shift;
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
        #-f $projectFilePath || die "Can't find $projectFilePath\n";
        # convert to backslash paths for windows
        #$wav =~ s!/!\\!g;
        #$mp3 =~ s!/!\\!g;
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

sub checkTracks
{
	my $errors_found = 0;
	##############################################
	# when we return (audacity exits)
	# check labels - times, illegal characters
	# check all wav files exist
	##############################################
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "Checking Tracks: looking in $wavDirectory for wav files\n" if $debug>1;
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
                        warn "label not zero length: $track->{title} : $track->{t} : $track->{t1}\n" if $debug>0;
                        # Fix it
                        print "fixing...\n" if $debug>0;
                        $track{t1} = $track{t};
                }
		# Check the wav file exists
		my $wavfile = "$wavDirectory/$wavFilenamePrefix-$ti.wav";
		if(-r $wavfile){
			$tr = "OK";
		}else {
			$tr = "missing";
			$errors_found++;
		}
		print "checking for $wavfile: $tr\n" if $debug>0;
#		`lame $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3`; 
#		`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavDirectory/$wavFilenamePrefix-$ti.mp3` if(-f $wavfile);
	}
	# Save to a new project file
	$AUP->save($projectFilePath);
        print "checkTracks: Found $errors_found errors: " if($errors_found);
	print "Finished Checking Tracks\n" if $debug>1;
        $errors_found;
}

sub makeMp3s
{
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
        print "Making MP3s"  if $debug>1;
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavDirectory for wav files\n" if $debug>1;
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		print "processing track $ti: $title\n";

		# Check the wav file exists
		my $wavfile = "$wavDirectory/$wavFilenamePrefix-$ti.wav";
		if(-r $wavfile){
                        runFfMpeg($title, $ti, $wavfile, "$mp3Directory/$title.mp3");
			#`"c:/program files/audacity/ffmpeg.exe" $wavfile $mp3Directory/$title.mp3`;
		}
	}
        print "Finished Making MP3s"  if $debug>1;
}

sub checkBlankMedia
{
        # returns number of blank media found and stored in %blanks
        print "Checking for drives to use\n" if $debug >1;
        open (CDBXP, "\"$pathToCdBurnerXp\" --list-drives |") || die "can't fork $pathToCdBurnerXp: $!\n";
        while (<CDBXP>) {
                        print if $debug > 1;
                        # scan lines for 0: LITE-ON DVDRW LH-20A1H (E:\)
                        if (/(\d):\s.*\((.):\\\)/) {$drives{$2} = $1}
                        my $driveLetter = $2;
                }
        close CDBXP || die "can't close $pathToCdBurnerXp: $!\n";
#foreach my $drive (keys %drives) {
#                print "$drive: $drives{$drive}\n";
        open (CDBXP, "\"$pathToCreateCD\" -info -r:$driveLetter -nologo|") || die "can't fork $pathToCreateCD: $!\n";
        while (<CDBXP>) {
                        print if $debug > 2;
                        next unless /Writable Blank/;
                        $blanks{$driveLetter} = $&;
        }
        close CDBXP || die "can't close $pathToCreateCD: $!\n";
#}
        foreach (keys %blanks) {print "drive $_ has a blank CD in it\n";}
        keys %blanks;
}

sub BurnCDs
{
        # PostScript-CDCover-1.0
        # AudioCd-2.0
        # Filesys-dfPortable-0.85
        # MP3-CreateInlayCard-0.06
	##############################################
	# Burn CD using the wav files and CDBurnerXP
	##############################################
        while ((checkBlankMedia() < 1) || promptUser("No blank CDs found - insert balnk CD and [T]ry again or [S]kip burning?","T" =~ /^T$/i)) {
                1;
        }
        foreach (keys %drives) {
                print "Burning CD in drive $drives{$_}"  if $debug>1;
                @args = ("$pathToCdBurnerXp",
                         "--burn-audio", "-dao", "-close", "-eject",
                         "-device:$_",
                         "-folder:$wavDirectory",
                         #"--name:\"$mp3ArtistNameString\"",
                         #"-metadata", "Genre=$mp3GenreString",
                         #$mp3,
                         );
                print "Running: @args" if $debug > 1;
                #system(@args) == 0 or die "system @args failed: $!";
        }
        print "Finished Burning CDs"  if $debug>1;
}

##############################
# main Program Start
##############################

#Generate a date string
$nowString = strftime "%Y-%m-%d", localtime;
print "today: $nowString\n" if $debug>2;

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
runAudacity;

# Open today's aup file
print "checking project file: $projectFilePath\n" if $debug>0;
die "failed to open Audacity project file: $projectFilePath\n" unless -r $projectFilePath;

$AUP = XML::Smart->new($projectFilePath);

# Save to a backup project file unless one already exists
$AUP->save($projectFilePath . ".bak") unless (-f $projectFilePath . ".bak");

while(checkTracks &&
   promptUser ("Found missing wav files or incorrect label lengths.\nRe-run Audacity to fix?","Yes") =~ /^Y/i) {
        runAudacity;
}

makeMp3s;

exit;
# Generate MP3 files using ffmpeg
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

