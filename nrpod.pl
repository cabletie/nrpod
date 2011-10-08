#!/usr/bin/perl -w
# Version 0.2
use XML::Smart;
use POSIX qw(strftime);
use File::Basename;

my $filename = $ARGV[0];
my $nowString;
my $projectTemplateFilename;
my $projectFilename;
my $AUP;

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
	$projectFilename = $nowString."_service.aup";
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
	@args = ("audacity", "$projectFilename");
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
	my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavsDirectory for wav files\n";
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
		my $wavfile = "$wavsDirectory/$wavsDirectory-$ti.wav";
		if(-r $wavfile){
			$tr = "OK";
		}else {
			$tr = "missing";
			$errors_found++;
		}
		print "checking for $wavfile: $tr\n";
#		`lame $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3`; 
#		`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3` if(-f $wavfile);
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
	my $wavsDirectory = fileparse($projectFilename, ".aup");
	print "looking in $wavsDirectory for wav files\n";
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	my @llist = @{$AUP->{project}{labeltrack}{label}};
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		print "processing track $ti: $title\n";

		# Check the wav file exists
		my $wavfile = "$wavsDirectory/$wavsDirectory-$ti.wav";
		if(-r $wavfile){
			`"c:/program files/audacity/ffmpeg.exe" $wavfile $wavsDirectory/$wavsDirectory-$ti.mp3`;
		}
	}
}

#Generate a date string
$nowString = strftime "%Y-%m-%d", localtime;
$projectTemplateFilename = 'template.aup';

# If no filename specified on command line, run as normal (create project from template, run audacity)
# Otherwise, just check tracks
$projectFilename = $filename;
if(!$projectFilename) {
	makeNewProject;
	runAudacity;
}

# Open today's aup file
print "checking project file: $projectFilename\n";
die "failed to open Audacity project file: $projectFilename\n" unless -r $projectFilename;

$AUP = XML::Smart->new($projectFilename);

# Save to a backup project file unless one already exists
$AUP->save($projectFilename . ".bak") unless (-f $projectFilename . ".bak");

if(!checkTracks |
   promptUser ("found missing wav files or incorrect label lengths - re-run Audacity to fix?","Yes") !~ /^Y/i) {
	makeMp3s;
} else {
        print "you will have to re-run this script when done.";
        exec "c:/program files/audacity/audacity.exe", "$projectFilename";
}

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

