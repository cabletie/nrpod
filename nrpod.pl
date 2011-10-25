#!/usr/bin/perl -w

# ToDo:
# 1. fix concatenating mp3s with ffmpeg
# Done 2. add GUI to allow selection of sermon tracks
# 3. create selected tracks into one MP3 for sermon upload
# 4. FTP sermon MP3 to server
# 5. Configure server for new sermon
# 6. Change using POSIX strftime to using localtime (use Time::localtime;)
#	$tm = localtime;
#	printf("The current date is %04d-%02d-%02d\n", $tm->year+1900, 
#	    ($tm->mon)+1, $tm->mday);
# 7. Move config stuff to config file
# 8. Ask all questions up front

use XML::Smart;
use POSIX qw(strftime);
use File::Basename;
use Switch;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use Audio::Wav;
use Config::Simple;

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
my @selectedTracks;

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
	$pathToCdLabelGen = "cdlabelgen";

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
	
	# Loads the config. file into a hash: Eventually, all config will be in here
	Config::Simple->import_from('nrpod.cfg', \%Config);

}
sub promptUser {
	# Prompt user for input, providing default value if available
	# Usage: promptUser promptstring [defaultvalue]
	# Input is returned as function result
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
        my $mp3 = shift;
        my @wavs = @_;
	@args = ("$pathToLame", $debug<2?"--quiet":"",
                 "--tl", "$newAlbumString",
                 "--ty", $mp3YearString,
                 "--tt",  "$trackTitle",
                 "--tn", $trackNumber."/".$numberOfTracks,
                 "--ta", "$mp3ArtistNameString",
		 "--tg", "$mp3GenreString",
		 $mp3,
		 @wavs);
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
	print "Checking labels and wav files ..." if $debug;
	
	# Open today's aup file
	print "checking project file: $projectFilePath\n" if $debug>1;
	die "failed to open Audacity project file: $projectFilePath\n" unless -r $projectFilePath;
	
	$AUP = XML::Smart->new($projectFilePath);
	
	# Save to a backup project file unless one already exists
	$AUP->save($projectFilePath . ".bak") unless (-f $projectFilePath . ".bak");
	
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
                        print "fixing...\n" if $debug && $fix;
			# Modify the actual XML structure
			$AUP->{project}{labeltrack}{label}[$ti-1]{t1} = $AUP->{project}{labeltrack}{label}[$ti-1]{t} if $fix;
                        $track{t1} = $track{t} if $fix;
			$errors_found++;
                }
		# Check the wav file exists
		my $tiString = sprintf("%02d", $ti);
		my $wavfile = "$wavDirectory/".$tiString."-$title.wav";
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
        print "$errors_found errors: " if($errors_found);
	print "Errors " . $fix?"fixed\n":"NOT fixed\n"if ($errors_found);
	print "Finished Checking Tracks with $errors_found errors\n" if $debug>1;
	print "OK\n" unless ($errors_found);
        $errors_found;
} #checkTracks

sub makeMp3s {
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
        print "Making MP3s\n"  if $debug;
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
                        convertWav2Mp3($title, $ti, $numlabels, "$mp3Directory/".$tiString."-$title.mp3", $wavfile);
		}
	}
        print "Finished Making $numlabels MP3s\n"  if $debug > 1;
}

sub checkBlankMedia {
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

sub BurnCD {
        # PostScript-CDCover-1.0
        # AudioCd-2.0
        # Filesys-dfPortable-0.85
        # MP3-CreateInlayCard-0.06
	##############################################
	# Burn CD using the wav files and drutil
	##############################################
	my $drive = shift;
	my @selectedTracks = @_;
#        my $wavFolder = shift;
	print "Burning drive $drive from $wavDirectory/burn\n" if $debug;
	
	# Create burn directory for symlinks
	checkDirectory("$wavDirectory/burn");
	my $bn;
	# Create symlink in subdir for each selected track
	foreach $track (@selectedTracks) {
		$bn = basename($track->{'filename'});
		#print "$bn\n";
		print "Creating $wavDirectory/burn/$bn -> ../$bn\n" if($debug > 1);
		symlink "../$bn","$wavDirectory/burn/$bn";
	}
	@args = ("drutil", "burn",
		 "-audio",
		 "-pregap",
		 "-noverify",
                 "-eject",
                 "-erase", 
                 "-drive", $drive,
                 "$wavDirectory/burn"
		);
        print "Running: @args" if $debug >2 ;
        system(@args) == 0 or die "system @args failed: $!";
        print "Finished Burning CD\n"  if $debug >1;
}

sub expand {
	my $range = shift;            
	my @result; 
	$range =~ s/[^\d\-\,]//gs; #remove extraneous characters
	my @items = split(/,/,$range);    
	foreach (@items){                 
		m/^\d+$/ and push(@result,$_) and next;  my ($start,$finish) = split /-/;   push(@result,($start .. $finish)) if $start < $finish;                    
	}                                 
	return @result;                        
}

sub selectTracks {
	# Prompt user to list tracks selected for inclusion either in sermon or on CD
	my $message = shift;
	my %track_lengths;
	my @result;
	my $total_length = 0;
	my $selected_total = 0;
	my %options = (
		'.01compatible'   => 0,
		'oldcooledithack' => 0,
		'debug'           => 0,
	);
	my $wav = Audio::Wav -> new( %options );

	# Announce our intentions
	print("Selecting tracks\n") if($debug);

	# Grab a file glob from the wav directory	
	chomp (@filelist = <$wavDirectory/[0-9][0-9]-*.wav>);

	# Iterate over them, printing the basename and saving and summing the recording time	
	do {
		foreach $file (@filelist) {
			print basename($file,".wav");
			my $read = $wav -> read($file);
			$track_lengths{$file} = $read -> length_seconds();
			$total_length += $track_lengths{$file};
			printf ("\t%5.4fs\n", $track_lengths{$file});
		}
#		$total_length = 123.456789;
		my $fractional_minutes = $total_length / 60;
		my $whole_minutes = int($fractional_minutes);
		my $remaining_seconds = ($fractional_minutes - $whole_minutes) * 60;
		printf "\nTotal time: %dm%05.2fs (%.4f seconds)\n" ,$whole_minutes,$remaining_seconds,$total_length;
		@selected = expand(
			promptUser ("Enter track numbers to use for $message, separated by commas:",
				    "1-".eval($#filelist+1)));
		print "You have selected the following:\n";
		my $selection;
		foreach $selection (@selected) {
			print $selection;
			print ": " . basename ($filelist[$selection-1],".wav");
			printf ("\t%5.4fs\n", $track_lengths{$filelist[$selection-1]});
			push @result, {'filename' => $filelist[$selection-1], 'length' => $track_lengths{$filelist[$selection-1]}};
			$selected_total += $track_lengths{$filelist[$selection-1]};
		}
		$fractional_minutes = $selected_total / 60;
		$whole_minutes = int($fractional_minutes);
		$remaining_seconds = ($fractional_minutes - $whole_minutes) * 60;
		printf "\nTotal time: %dm%05.2fs (%.4f seconds)\n" ,$whole_minutes,$remaining_seconds,$selected_total;
	} until promptUser("Are these selections correct?","Yes") =~ /^Y/i;
	return @result;
}

sub printCDLabel {
	# Create a file with the track labels contained in @selectedTracks
	my @tracks = @_;
	my @items;
	foreach $item (@tracks) {
		push @items,basename($item -> {'filename'})
	}
	
	my $recordingName = "NRUC 9:30am Service";
	my $preacher = promptUser "Preacher/speaker name", "Ian Hickingbotham";
	my $sequenceNumber = promptUser "Sermon sequence number without the year or '#' (e.g. 23)";
	(my $yr) = (localtime)[5];
	my $sequenceString = " \#$yr\-$sequenceNumber" if $sequenceNumber;
	# use cdlabelgen to create the ps file
	# Command format example is:
	# ./cdlabelgen --category "NRUC 9:30am Service Ian Hickingbotham #09-25(Master)" --items "line one%line two%line three" --slim-case --no-date --output-file cover.ps
	@args = ("$pathToCdLabelGen",
		 "--category", "$recordingName $preacher$sequenceString (Master)",
		"--items", join("%",@items),
		"--slim-case", "--no-date",
		"--outputfile", "$projectDirectory/CD_cover.ps",
	);
	print "Running: @args" if $debug > 1;
	system(@args) == 0 or die "system @args failed: $!";
	print "finished\n" if $debug > 1;
}

##############################
# main Program Start
##############################

# Options variables
my $audacity = 1;
my $help;
my $man;
my $burn = 1;
my $mp3 = 1;
my $fix = 1;
my $podcast = 1;
my $cdLabel = 1;

# Gather options and do help if needed or requested
GetOptions (
	'help|?' => \$help,
	'man' => \$man,
	'audacity!' => \$audacity,
	'mp3!' => \$mp3,
	'debug+' => \$debug,
	'burn!' => \$burn,
	'podcast!' => \$podcast
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

## Open today's aup file
while(checkTracks) {
   my $r = promptUser ("Missing wav files or incorrect label lengths.\nRe-run Audacity to re-export wav files?","Yes");
   if($r =~ /^Y/i) {runAudacity;}
   if($r =~ /^N/i) {print "Quitting\n"; exit;}
}

# CReate mp3 files from wav files
$mp3?makeMp3s:print "Not making MP3s\n";

# Burn CDs
@selectedTracks = selectTracks("burning to CD and/or Label inserts") if ($cdLabel || $burn);
if($burn) {
	my @blanks = checkBlankMedia;
	while($#blanks < 0 &&
	   promptUser ("No blank, writable CDs found\n[T]ry again or [S]kip burning?","T") =~ /^T/i) {
		@blanks = checkBlankMedia;
	}
	if ($debug) {
		my $plural = $#blanks > 0?'s ':' ';
		print "Available blank, writable CD".$plural."in drive".$plural;
		print join(' and ',@blanks)."\n";
	}
	foreach my $drive (@blanks) {
		BurnCD($drive, @selectedTracks);
	}
} else { print "Not burning CDs\n";}

# Create CD label inserts (does not print at this stage)
# Assume CD labels are only wanted when CDs are burned
printCDLabel(@selectedTracks) if $cdLabel;


# Create podcast file and FTP to web server.
if ($podcast) {
	@selectedTracks = selectTracks("sermon podcast");
} else { print "Not creating podcast\n"}

exit;
# Generate MP3 files - DONE
# Export labels to CDBurnerXP project file
# Run burner X2 discs
# print labels
# upload MP3s to FTP server/iTunes

__END__
=head1 AUP

aup - Capture and process NRUC sermon podcast

=head1 SYNOPSIS

aup [options] [project name]

 Options:
   --help            brief help message
   --man             full documentation
   --noaudacity      don't run audacity
   --nomp3           don't create mp3 files
   --noburn          don't burn CD
   --nopodcast       don't create podcast MP3 or upload it
   --nofix           don't automatically fix non-zero length track labels in audactiy project file
   --noCDlabel	     don't create CD label files
   
=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints this manual page and exits.

=item B<-noaudacity>

Skips running audacity - just processes the project file. Project file must already exist.

=back

=head1 DESCRIPTION

New project file based on the template will be created for today's if no project file is sepcified.
First, it runs audacity (unless --noaudacity is specified). The operator is expected to create track labels and export multiple wav files into the wav subdirectory for the project.
The operator then exits audacity and nrpod continues, checking for correct track labels (i.e. no non-zero length labels) and checks that all wav files exists for all tracks. It nrpod will fix non-zero track labels automatically unless --nofix is specified.

=cut