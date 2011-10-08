#!/usr/bin/perl -w
# Version 0.3
use XML::Smart;
use POSIX qw(strftime);
use File::Basename;
use Switch 'Perl6';

my $debug = 1;

my $filename = $ARGV[0];
my $nowString;
my $projectTemplateFilename;
my $projectFilename;
my $AUP;
my $recordingsDirectoryName = "service_recordings";
my $recordingsDirectory;
my $todaysDirectory;
my $wavOutputDirectoryName = "wav";
my $wavDirectory;
my $mp3OutputDirectoryName = "mp3";
my $mp3Directory;
my $worshipServiceSuffix = "_service";
my $audacityProjectFilename = "_audacity_project";
my $wavFilenamePrefix;
#my $machine ="chippy";
#my $machine ="multimedia";

# Check for existence of and create directory if needed
sub checkDirectory {
        $dtc = shift;
        if (! -e $dtc) {
                mkdir($dtc) or die "Can't create dtc:$!\n";
        }
}

sub loadConfig {
        #Generate a date string
        $nowString = strftime "%Y-%m-%d", localtime;
        print "today: $nowString\n" if $debug;
        
        # Figure out which machine we're on
        chomp(my $hostname = `hostname`);
        print "hostname: $hostname\n" if $debug;

        given ($hostname) {
                when "chippy"       {
                        $baseDirectory = "D:/Users/peter/Documents/Audacity";
                        $pathToAudacity = "C:/Program Files/Audacity 1.3 Beta (Unicode)/audacity.exe";
                        }
                # wav and mp3 destinations: D:\users\Helix Multimedia\service recordings\service_2009-07-19
                # aup project data: D:\users\Helix Multimedia\service recordings\2009-07-19_NRUC Worship_Service_data
                # wav filename format : 2009-07-19_NRUC Worship_Service-01.wav
                # CDBurnerXp: C:\Program Files\CDBurnerXP
                # Audacity: C:\Program Files\Audacity 1.3 Beta (Unicode)
                when "multimedia" {
                        $baseDirectory = "D:/users/Helix Multimedia/service recordings";
                        $pathToAudacity = "C:/Program Files/Audacity 1.3 Beta (Unicode)/audacity.exe";
                        }
                else { die "unknown host: $hostname"};
        }
        print "basedirectory: $baseDirectory\n" if $debug;
        
        # Now build the other useful path strings
        # Expected path for multimedia PC at NRUC shown in comments
        
        # D:/users/Helix Multimedia/service_recordings
        checkDirectory($recordingsDirectory = "$baseDirectory/$recordingsDirectoryName");
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/
        checkDirectory($todaysDirectory = "$recordingsDirectory/$nowString$worshipServiceSuffix");
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/wav
        checkDirectory($wavDirectory = "$todaysDirectory/$wavOutputDirectoryName");
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/mp3
        checkDirectory($mp3Directory = "$todaysDirectory/$mp3OutputDirectoryName");
        # D:/users/Helix Multimedia/service_recordings/2009-07-19_service/2009-07-19_audacity_project.aup
        $projectFilename = "$todaysDirectory/$nowString$audacityProjectFilename.aup";
        
        # Prefix for all wav files
        $wavFilenamePrefix = "$nowString$worshipServiceSuffix";
        
        # Locate template file
        # D:/users/Helix Multimedia/service_recordings/template.aup
        $projectTemplateFilename = "$recordingsDirectory/template.aup";
        -f $projectTemplateFilename || die "can't find template file: $projectTemplateFilename";
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

sub makeNewProject()
{
	##############################################
	# Create audacity project file from template
	# Set meta data (tags) for date etc
	##############################################

	# Create ALBUM text for the MP3 tags section
	$newAlbumString = "NRUC 9:30am service $nowString";
	#Create a filename for the new project
	#$projectFilename = $nowString."_service.aup";
	print "Creating new project file '$projectFilename' from '$projectTemplateFilename'\n";

	# Open the template aup file
	my $TEMPLATE = XML::Smart->new($projectTemplateFilename);

	# Set ALBUM MP3 tags string
	$TEMPLATE->{project}{tags}{tag}('name','eq','ALBUM'){'value'} = $newAlbumString;

	# Save to a new project file
	$TEMPLATE->save($projectFilename);
}

sub runAudacity()
{
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
	print "Running audacity with $projectFilename ... ";
	@args = ("audacity.exe", "$projectFilename");
	system(@args) == 0 or die "system @args failed: $?";
	print "finished\n";
}

sub checkTracks()
{
	my $errors_found = 0;
	##############################################
	# when we return (audacity exits)
	# check labels - times, illegal characters
	# check all wav files exist
	##############################################
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavDirectory for wav files\n";
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	print "found $numlabels tracks\n";
	$errors_found++ unless $numlabels;
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		$t = $track->{t};
		$t1 = $track->{t1};
		print "track $ti: $title ($t:$t1)\n";
                if ($t1 != $t) {
                        warn "label not zero length: $track->{title} : $track->{t} : $track->{t1}\n";
                        # Fix it
                        print "fixing...\n";
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
		print "checking for $wavfile: $tr\n";
#		`lame $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3`; 
#		`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavDirectory/$wavFilenamePrefix-$ti.mp3` if(-f $wavfile);
	}
	# Save to a new project file
	$AUP->save($projectFilename);
        print "checkTracks: Found $errors_found errors: " if($errors_found);
        $errors_found;
}

sub makeMp3s()
{
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavDirectory for wav files\n";
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		print "processing track $ti: $title\n";

		# Check the wav file exists
		my $wavfile = "$wavDirectory/$wavFilenamePrefix-$ti.wav";
		if(-r $wavfile){
			`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavDirectory/$wavFilenamePrefix-$ti.mp3`;
		}
	}
}


# Setup directories and load any config from ini file
loadConfig($projectFilename);

# Set $projectflename if given on command line
$projectFilename = $filename if $filename;

# Create a new projectfile if $filename not specified on command line
makeNewProject unless $filename;

# Run Audacity to capture recording
runAudacity;

# Open today's aup file
print "checking project file: $projectFilename\n";
die "failed to open Audacity project file: $projectFilename\n" unless -r $projectFilename;

$AUP = XML::Smart->new($projectFilename);

# Save to a backup project file unless one already exists
$AUP->save($projectFilename . ".bak") unless (-f $projectFilename . ".bak");

while(checkTracks &&
   promptUser ("found missing wav files or incorrect label lengths - re-run Audacity to fix?","Yes") =~ /^Y/i) {
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

