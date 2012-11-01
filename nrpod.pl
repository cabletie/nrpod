#!/usr/bin/perl -w

# ToDo:
# Done (used sox instead 1. fix concatenating mp3s with ffmpeg
# Done 2. add GUI to allow selection of sermon tracks
# Done 3. create selected tracks into one MP3 for sermon upload
# Done 4. FTP sermon MP3 to server
# 5. Configure WordPress server for new sermon
# Done 6. Change using POSIX strftime to using localtime (use Time::localtime;)
#	$tm = localtime;
#	printf("The current date is %04d-%02d-%02d\n", $tm->year+1900, 
#	    ($tm->mon)+1, $tm->mday);
# 7. Move config stuff to config file
# 8. Ask all questions up front
# 9. Improve defaulting when new project file is created from template (either have defaults in program or fix defauts in template file)
# 10. Don't die at any failed command - change to pass through if not critical.
# 11. Add leveling/normalizing via sox
# Done 12. FTP progress bar
# 13. Add "comments" field in ID3 tags/parameters
# Done 14. Fix location of new project file (currently defaults to .)
# Done 15. Fix CD label when there is no sequence number
# Done 16. Make default tag year this year in configureProject. (removed year from template project file)
# Done 17. Insert date into project name if none found when creating a new project (new project date string defaults to current date or to projectDate [--project-date] if provided on command line)

# use strict;
use XML::Smart;
use File::Basename;
use File::Path qw(make_path);
use File::Glob;
use Switch;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use Audio::Wav;
use Config::Simple;
use Time::localtime;
#use LWP;
#use Net::FTP;
use Term::ReadLine;

my $debug = 0;

my $projectTemplateFilename;
my $projectFilename; # base filename with .aup extension
my $projectFilePath; # project filename with .aup extension and full path
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
my $audacityProjectSuffix = "_service";
my $audacityProjectDataDirectorySuffix = "_data";
my $preacherDefault = "Ian Hickingbotham";
my $wavFilenamePrefix;
my $pathToFfMpeg;
my $pathToLame;
my $newAlbumString;
# mp3 prefixes are for individual mp3 files made from tracks
my $mp3GenreString;
my $mp3YearString;
my $mp3ArtistNameString = "North Ringwood Uniting Church";
# project prefixes are for the  aup project file
my $projectArtistNameString = $mp3ArtistNameString;
# Used as track title for whole service recording
my $projectTitleString = "Raw Recording";
my $pathToCdBurnerXp;
my $pathToCreateCD;
my $pathToCD;
my %drives;
my %blanks;
my $windows;
my @selectedTracks;
my $tm = localtime;
my $dateString = sprintf("%04d-%02d-%02d",$tm->year+1900,$tm->mon+1,$tm->mday);
my $pathToSox;
my $recordingNameDefault = "NRUC Service of worship";
my $sequenceNumber;
my $interactive;
my $podcastFilePath;
my @CdInsertFileNames;
my $sermonTitle = "";
my $sermonSeries = "";
my $sermonGenre = "Speech";
my $sermonDescription = "";

# Options variables
my $audacity = 2;
my $help;
my $man;
my $burn = 2;
my $mp3 = 2;
my $fixLabels = 2;
my $podcast = 2;
my $cdInserts = 2;
my $printCdInserts = 2;
my $projectDate;
my $upload = 2;
my $podcastid3 = 2;
my $updatetags;
my $verbose = 0;
my $gui = 1;

my $term = Term::ReadLine->new($0);
my $OUT = $term->OUT || \*STDOUT;
my $LOG;

# Check for existence of and create directory if needed
sub checkDirectory {
        my $dtc = shift;
        make_path($dtc) or die "Can't create $dtc:$!\n" unless -d $dtc;
	print "$dtc\n" if $debug>2;
}

sub dumpCommand {
	my $toFile = shift;
	my @list = @_;
	open OF,">$toFile";
	print OF join(' ',@list);
	close OF;
}


sub promptUser {
	# Prompt user for input, providing default value if available
	# Usage: promptUser promptstring [defaultvalue]
	# Input is returned as function result
	my($promptString,$defaultValue) = @_;
#	$defaultValue = $defaultValue?$defaultValue:"";
	my ($cdrv,$button_rv, $rv);
	if($gui) {
		$cdrv = `$pathToCD inputbox --title "nrpod" --informative-text "$promptString" --text "$defaultValue" --button1 "OK"`;
		($button_rv, $rv) = split /\n/, $cdrv, 2;
	} else { # terminal interface only
		$rv = $term->readline("$promptString ",$defaultValue);
	}
	return $rv;
}

sub promptUserYN {
	# Input is returned as function result
	my($promptString,$defaultValue) = @_;
#	$defaultValue = $defaultValue?$defaultValue:undef;
	my ($rv, $cdrv);
	if($gui) {
		$cdrv = `$pathToCD yesno-msgbox --title "nrpod" --no-newline --label "$promptString"`;
		if($cdrv == 1) 
			{$rv = "Y"} 
		else 
			{$rv = "N"}
	} else { # terminal interface only
		$rv = $term->readline("$promptString ",$defaultValue);
	}
	return $rv;
}

sub promptUserOKCan {
	# Button clicked is returned as function result
	my($promptString,$Button1,$Button2) = @_;
	$Button1 = "OK" unless defined $Button1;
	$Button2 = "Cancel" unless defined $Button2;
	if($gui) {
	return `$pathToCD msgbox --title "nrpod" --label "$promptString" --button1 "$Button1" --button2 "$Button2"`;
	} else { # not GUI
		return 1 if($term->readline("$promptString ",$Button1) =~ /^$Button1/);
		return 2;
	}
}

sub promptUserForTracks {
	# Window title, 
	# label (usualy time total), 
	# array of tracks selected by default (e.g. 1,3,5,6,7), 
	# array of track names/numbers and durations
	my ($title,$label,$ref_selected,$ref_tracks) = @_;
	my ($rv, $cdrv, @rv, $boxes, $button, @boxes);
		my @checkedBoxes; # declare array that big to hold a number for each track
		# my @checkedBoxes = (0) x $#{$ref_tracks}; # declare array that big to hold a number for each track
		# Convert selection array to bitmap array
		# Loop through list and set each specified element to 1
		foreach my $checked (@{$ref_selected})
		{
			push(@checkedBoxes,$checked-1);
		}
		print "$pathToCD checkbox --title \"$title\" --label \"$label\" --width 600 --button1 OK --button2 Recalculate --button3 Cancel --debug --items @{$ref_tracks} --checked @checkedBoxes\n" if ($debug>1);
		open CD, "$pathToCD checkbox --title \"$title\" --label \"$label\" --width 600 --button1 OK --button2 Recalculate --button3 Cancel --debug --items @{$ref_tracks} --checked @checkedBoxes|" or die "$pathToCD @args failed: $!";
		$button = <CD>;
		$boxes = <CD>;
		close CD;
		# Convert bitmap array (0 0 1 0 1 1 0) to selection array (2,4,5)
		(@boxes) = split /\s/,$boxes;
		my $boxnum = 1;
		# Reset selected back to nothing
		@{$ref_selected} = ();
		# Loop and push each selected track back into result
		foreach my $box (@boxes) 
		{
			push @{$ref_selected}, $boxnum if ($box == 1);
			$boxnum++;
		}
		print "Inside:",join(" ",@{$ref_selected}),"\n" if $debug;
	return $button;	
}

sub message {
	# Input is returned as function result
	my $cdrv;
	my($promptString) = @_;
	if($gui) {
		$cdrv = `$pathToCD msgbox --title "nrpod" --label "$promptString" --button1 OK`;
	} else { # terminal interface only
		print "$promptString\n";
	}
}

sub loadConfig {
    # Figure out which machine we're on
    chomp(my $hostname = `hostname`);
    print "hostname: $hostname\n" if $debug > 1;
    $pathToFfMpeg = "C:/Program Files/Audacity 1.3.8 Beta (Unicode)/ffmpeg.exe";
    $pathToAudacity = "C:/Program Files/Audacity 1.3 Beta (Unicode)/audacity.exe";
#	$pathToCdBurnerXp = "C:/Program Files/CDBurnerXP/cdbxpcmd.exe";
	$pathToCdLabelGen = "cdlabelgen";
	$pathToSox = "/Users/peter/Documents/Audacity/nrpod/sox-14.3.2/sox";
	$pathToCD = "/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog";

    switch ($hostname) {
        case /tilaph/i {
            $baseDirectory = "/Users/peter/Documents/Audacity";
			$pathToAudacity = "/Applications/Audacity/Audacity.app";
            $pathToFfMpeg = "ffmpeg";
			$pathToLame = "lame";
			$windows = 0;
			$pathToSox = "sox";	
		}
        case /nrpod/i {
            $baseDirectory = glob("~");
            $pathToAudacity = "/Applications/Audacity/Audacity.app";
            $pathToFfMpeg = "ffmpeg";
            $pathToLame = "lame";
            $windows = 0;
            $pathToSox = "sox";
        }
        die "unknown host: $hostname";
    }
    print "basedirectory: $baseDirectory\n" if $debug>1;
} # loadConfig

sub setupPaths { # Usage: setupPaths projectDirectory
	# ProjectDirtecory contains the .aup file, wav directory, mp3 directory and audacity _data directory
	# Now build the other useful path strings and check that the required ones exist
	
	# Expected path for multimedia PC at NRUC shown in comments
	my $projectDirectory = shift;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/
	#        checkDirectory($projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName");
	checkDirectory($projectDirectory);
	print "projectDirectory: $projectDirectory\n" if $debug>1;
	#        checkDirectory($projectDataDirectory = "$projectDirectory/$projectName"."_Data");
	#        print "projectDataDirectory: $projectDataDirectory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/wav
	checkDirectory($wavDirectory = "$projectDirectory/$wavOutputDirectoryName");
	print "wavDirectory: $wavDirectory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/mp3
	checkDirectory($mp3Directory = "$projectDirectory/$mp3OutputDirectoryName");
	print "mp3Directory: $mp3Directory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/2009-07-19_audacity_project.aup
	$projectFilePath = "$projectDirectory/$projectName.aup";
	print "projectFilePath: $projectFilePath\n" if $debug>1;
	
	# Check and create data directory if it doesn't exist
	checkDirectory $projectDataDirectory;
	
	# Prefix for all wav files
	$wavFilenamePrefix = "$projectName";
	
	# Locate template file
	# D:/users/Helix Multimedia/service_recordings/template.aup
	$projectTemplateFilename = "$baseDirectory/$recordingsDirectoryName/template.aup";
	-f $projectTemplateFilename || die "can't find template file: $projectTemplateFilename";
} #setupPaths

sub updateTag {
	my $tagname = shift;
	$tag = $PROJECT->{project}{tags}{tag}('name','eq','ARTIST'){'value'};
	if($tag) {
		print "ARTIST tag: $tag\n" if $debug;
		$projectArtistNameString = promptUser("Recording Artist", $tag);
		$PROJECT->{project}{tags}{tag}('name','eq','ARTIST'){'value'} = $mp3ArtistNameString;
	} else {
		print "ARTIST attribute undefined in project file, creating." if($debug >1);
#		$projectArtistNameString = promptUser "Artist", $projectArtistNameString;
		my $newtag = {
			name	=> 'ARTIST' ,
			value	=> $projectArtistNameString
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
	}
}

sub configureProject {
	# Open the aup project file and get tags or set them from command prompts
	
	my $PROJECT;
	my $tag;
	my $safePreacher;
	my $fileSafeRecordingName;
	my $tagsWereModified;
	
	if(-e $projectFilePath) {
		print "Reading from existing project file\n";
		$PROJECT = XML::Smart->new($projectFilePath)
	} else {
#		print "$projectFilePath does not exist\n";
		if (promptUserYN("$projectFilePath does not exist - create?", "Y") !~ /^Y/i) {
				message "Don't know what project file to use - quitting\n";
				exit;
			}
		$updatetags = 1; # New project file - tags must be updated
		print "Creating new project file " . basename($projectFilePath) . " from " . basename($projectTemplateFilename) . "\n";
		$PROJECT = XML::Smart->new($projectTemplateFilename);
	}
	
	$recordingName = $PROJECT->{project}{tags}{tag}('name','eq','ALBUM'){'value'};
	if($recordingName) {
		$recordingName =~ s/\s(\d\d\d\d-\d\d-\d\d)//;
		print "ALBUM tag: $recordingName\n" if $debug;
		$recordingName = promptUser("Recording Name", $recordingName) if $updatetags;
		$newAlbumString = "$recordingName $dateString";
		$PROJECT->{project}{tags}{tag}('name','eq','ALBUM'){'value'} = $newAlbumString;
	} else {
		print "ALBUM attribute undefined in project file, creating." if($debug >1);
		$recordingName = promptUser ("Recording Name", $recordingNameDefault);
		## Add a new tag node:
		my $newtag = {
			name	=> 'ALBUM' ,
			value	=> $recordingName
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	print ("RecordingName: $recordingName") if ($debug);
	($fileSafeRecordingName = lc $recordingName) =~ tr/: /-_/;
	
	$projectArtistNameString = $PROJECT->{project}{tags}{tag}('name','eq','ARTIST'){'value'};
	if($projectArtistNameString) {
		print "ARTIST tag: $projectArtistNameString\n" if $debug;
		$projectArtistNameString = promptUser("Recording Artist", $projectArtistNameString) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','ARTIST'){'value'} = $mp3ArtistNameString;
	} else {
		print "ARTIST attribute undefined in project file, creating." if($debug >1);
#		$projectArtistNameString = promptUser "Artist", $projectArtistNameString;
		my $newtag = {
			name	=> 'ARTIST' ,
			value	=> $projectArtistNameString
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	
	$mp3YearString = $PROJECT->{project}{tags}{tag}('name','eq','YEAR'){'value'};
	if($mp3YearString) {
		print "YEAR tag: $mp3YearString\n" if $debug;
		$mp3YearString = promptUser("Recording Year", $mp3YearString) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','YEAR'){'value'} = $mp3YearString;
	} else {
		print "YEAR attribute undefined in project fie, creating." if($debug >1);
		$mp3YearString = $tm->year+1900;		
		my $newtag = {
			name	=> 'YEAR' ,
			value	=> $mp3YearString
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	
	$mp3GenreString = $PROJECT->{project}{tags}{tag}('name','eq','GENRE'){'value'};
	if($mp3GenreString) {
		print "GENRE tag: $mp3GenreString\n" if $debug;
		$mp3GenreString = promptUser("Recording Genre", $mp3GenreString) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','GENRE'){'value'} = $mp3GenreString;
	} else {
		print "GENRE attribute undefined in project file, creating." if($debug >1);
		$mp3GenreString = "Contemporary Christian";
		my $newtag = {
			name	=> 'GENRE' ,
			value	=> $mp3GenreString
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	
	$projectTitleString = $PROJECT->{project}{tags}{tag}('name','eq','TITLE'){'value'};
	if($projectTitleString) {
		print "TITLE tag: $projectTitleString\n" if $debug;
		$projectTitleString = promptUser("Track Title", $projectTitleString) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','TITLE'){'value'} = $projectTitleString;
	} else {
		print "TITLE attribute undefined in project file, creating." if($debug >1);
		$projectTitleString = "Raw recording";
		my $newtag = {
			name	=> 'TITLE' ,
			value	=> $projectTitleString
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	
	$preacher = $PROJECT->{project}{tags}{tag}('name','eq','PREACHER'){'value'};
	if($preacher) {
		print "PREACHER tag: $preacher\n" if $debug;
		$preacher = promptUser("Preacher/speaker name", $preacher) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','PREACHER'){'value'} = $preacher;
	} else {
		print "PREACHER attribute undefined in project file, creating." if($debug >1);
		$preacher = promptUser("Preacher/speaker name", $preacherDefault);
		my $newtag = {
			name	=> 'PREACHER' ,
			value	=> $preacher
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
	($safePreacher = $preacher) =~ tr/ /-/;
	
	$sequenceNumber = $PROJECT->{project}{tags}{tag}('name','eq','SEQUENCE'){'value'};
	if($sequenceNumber) {
		print "SEQUENCE tag: $sequenceNumber\n" if $debug;
		$sequenceNumber = promptUser("Sermon sequence number",$sequenceNumber) if $updatetags;
		$PROJECT->{project}{tags}{tag}('name','eq','SEQUENCE'){'value'} = $sequenceNumber;
	} else {
		print "SEQUENCE attribute undefined in project file, creating.\n" if $debug;
		$sequenceNumber = promptUser (
        	"Enter Sermon sequence number without the year or '#' (e.g. 23)\n".
			"Only used for placed minister. Leave blank otherwise",$sequenceNumber);
		my $newtag = {
			name	=> 'SEQUENCE' ,
			value	=> $sequenceNumber
		};
		push(@{$PROJECT->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}

	$podcastFilePath = "$mp3Directory/$dateString\_$fileSafeRecordingName\_$safePreacher\.mp3";
	
	# Save to a new project file if it was updated or missing tags were modified
	$PROJECT->save($projectFilePath) if ($updatetags || $tagsWereModified);

	# Loads the config. file into a hash: Eventually, all config will be in here
	#	Config::Simple->import_from('nrpod.cfg', \%Config);

} #configureProject

sub runAudacity {
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
	message "Starting audacity\nExport tracks using 'export multiple' to wav directory: $wavDirectory\nthen exit program\n";
	print "Waiting for Audacity to exit ...";
        -f $projectFilePath || die "Can't find $projectFilePath\n";
        # convert to backslash paths for windows
        my $runPath = $projectFilePath;
	my @args;
        $runPath =~ s!/!\\!g if $windows;
	print "Running audacity with $runPath ... " if $debug>1;
	@args = ("open", "-W", "$pathToAudacity", "$runPath");
	dumpCommand("$projectDirectory/runaudacity.bash",@args);
	system(@args) == 0 or die "system @args failed: $?";
	print "finished\n" if $debug>1;
}

sub convertWav2Mp3 {
    my $trackTitle = shift;
    my $trackNumber = shift;
	my $numberOfTracks = shift;
    my $wav = shift;
    my $mp3 = shift;
	my @args;
	@args = ("$pathToLame", $debug<3?"--quiet":"",
                 "--tl", "$newAlbumString",
                 "--ty", $mp3YearString,
                 "--tt", "$trackTitle",
                 "--tn", $trackNumber."/".$numberOfTracks,
                 "--ta", "$mp3ArtistNameString",
		 "--tg", "$mp3GenreString",
		 $wav,
		 $mp3);
	print "Running: @args\n" if $debug > 2;
	dumpCommand("$projectDirectory/lame.bash",@args);
	system(@args) == 0 or die "system @args failed: $!";
	print "finished\n" if $debug > 2;
}

sub runFfMpeg {
    my $trackTitle = shift;
    my $trackNumber = shift;
    my $wav = shift;
    my $mp3 = shift;
	my @args;
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
	dumpCommand("$projectDirectory/ffmpeg.bash",@args);
	system(@args) == 0 or die "system @args failed: $!";
	print "finished\n" if $debug > 1;
}

sub checkTracks {
	my $errors_found = 0;
	my $projectFilePath = shift;
	##############################################
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
    if (!(@llist && $#llist == 0 && $llist[0]->{title} eq "")) { # Check for empty list 
    #	if(@llist && $#llist > 0 && $llist[0]->{title}) {
		foreach my $track (@llist) {
	#need to add check for zero count tracks
			my $title = $track->{title};
			my $ti = $track->i()+1;
			print "checking track ",$track->i()+1,": $track->{title} ($track->{t}:$track->{t1})\n" if $debug>1;
			if ($track->{t1} != $track->{t}) {
				warn "label not zero length: $track->{title} : $track->{t} : $track->{t1}\n" if $debug;
				# Fix it
				print "fixing...\n" if ($debug && $fixLabels);
				# Modify the actual XML structure
				$AUP->{project}{labeltrack}{label}[$ti-1]{t1} = $AUP->{project}{labeltrack}{label}[$ti-1]{t} if $fixLabels;
				$errors_found++;
			}
			# Check the wav file exists
			my $tiString = sprintf("%02d", $ti);
			my $wavfile = "$wavDirectory/".$tiString."-$title.wav";
			my $tr;
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
	} else {
		message "No tracks saved - nothing to check";
		return 1; # Error found
	}
	# Save to a new project file
	$AUP->save($projectFilePath);
        my $msgtext = "$errors_found errors: " if($errors_found);
	if($errors_found) {
		if($fixLabels) {
			message $msgtext."fixed"}
		else {
			message $msgtext."NOT fixed"}
	}
#	print "Errors " . $fixLabels?"fixed\n":"NOT fixed\n" if ($errors_found);
	message "Finished Checking Tracks with $errors_found errors\n" if $debug>1;
	print "OK\n" unless ($errors_found);
    $errors_found;
} #checkTracks

sub makeMp3s {
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
    print "Making MP3s\n" if($verbose);
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
		print "$title\n" if($verbose);
		if(-r $wavfile){
                        convertWav2Mp3($title, $ti, $numlabels, $wavfile, "$mp3Directory/".$tiString."-$title.mp3");
		}
	}
        print "Finished Making $numlabels MP3 files from wav files\n" if($verbose);
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
	my @args;
	# Create symlink in subdir for each selected track
	foreach my $track (@selectedTracks) {
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
	dumpCommand("$projectDirectory/burncd.bash",@args);
        system(@args) == 0 or die "system @args failed: $!";
        print "Finished Burning CD\n"  if $debug >1;
}

sub expandSelection {
	my $range = shift;
    my $min = shift;
    my $max = shift;
	my @result;
   
	print "min: $min max: $max\n" if($debug > 2);

	$range =~ s/[^\d\-\,]//gs; #remove extraneous characters
	my @items = split(/,/,$range); # split on comma separators for expressions
	foreach (@items){
		print "dealing with list entry \'$_\'\n" if($debug > 2);
		# Test for a single number and push on the array if within bounds
		if (m/^\d+$/) {
			print "Testing: $_\n" if($debug > 2);
			next unless($_ >= $min and $_ <= $max);
			print "Pushing: $_\n" if($debug > 2);
			push(@result,$_);
			next; # Push and do next if in range
		}
        # Test for a range, loop through each value and push on array if within bounds
        my ($start,$finish) = split /-/; # Split range expressions
        print "Testing: $start .. $finish\n" if($debug > 2);
		next unless ($start < $finish);
        $finish = ($finish <= $max)?$finish:$max;
        $start = ($start >= $min)?$start:$min;
		print "Pushing: $start .. $finish\n" if($debug > 2);
        push(@result,($start .. $finish))
	}
	print join(',',@result),"\n" if($debug >1);
	return @result;
}


# Convert decimal seconds to a string of the form HHhMMmSS.Ss
sub sec2Hms {
	my $sec = shift;
	my $whole_hours = ($sec/(60*60))%24;
	my $whole_minutes = ($sec/60)%60;
	my $remaining_seconds = $sec - ($whole_hours*60*60)-($whole_minutes*60);
	sprintf "%02dh%02dm%02ds" ,$whole_hours,$whole_minutes,$remaining_seconds;
}


sub selectTracks {
	# Prompt user to list tracks selected for inclusion either in sermon or on CD
	# Usage: selectTracks <prompt message>
	# Returns array of hashes %result{'filename' => <full path to track wav file>,'length' => <track length in seconds>}
	my $message = shift;
	my %track_lengths;
	my @result;
	my @filelist;
	my $total_length = 0;
	my $selected_total = 0;
	my $selectionString;
	my @selectedArray;
	my $initialSelectionString = "1";
	my %options = (
		'.01compatible'   => 0,
		'oldcooledithack' => 0,
		'debug'           => $debug>2,
	);
	my $wav = Audio::Wav -> new( %options );

	# Announce our intentions
	print("Selecting tracks ($message)\n") if($verbose);

	# Grab a file glob from the wav directory
	chomp (@filelist = glob("$wavDirectory/[0-9][0-9]-*.wav"));

	# Define a default list of selected tracks (all of them)
	$initialSelectionString = "1";
	if($#filelist > 0) {
		$initialSelectionString .= "-".eval($#filelist+1);
	}
	@selectedArray = expandSelection($initialSelectionString,1,$#filelist+1);

	if($gui)
	{
		my $button;
		do {
			my %checkBoxStrings = ();
			my @checkBoxStrings = ();
			# Reset totals
			$total_length = 0; 
			$selected_total = 0;
			# Construct checkbox label strings for each wav filename and track time
			foreach my $file (@filelist) {
				# Start with open quote (we want to include the quote as part of the parameter to keep passing as parameters simple)
				$checkBoxStrings{$file} = "\"";
				# Add the filename
				$checkBoxStrings{$file} .= basename($file,".wav");
				# Read wav file and get duration
				my $read = $wav -> read($file); #need to capture and print error details here
				$track_lengths{$file} = $read -> length_seconds();
				# Add this track's length to total
				$total_length += $track_lengths{$file};
				$checkBoxStrings{$file} .= sprintf("\t\t%s", sec2Hms($track_lengths{$file}));
				$checkBoxStrings{$file} .= "\"";
				push(@checkBoxStrings,$checkBoxStrings{$file});
			}

			$selected_total = 0;
			foreach $selection (@selectedArray) {
				$selected_total += $track_lengths{$filelist[$selection-1]};
			}
			print "Before:",join(" ",@selectedArray),"\n" if $debug;

			$button = promptUserForTracks (
				"Select tracks for $message",
				sprintf ("Total selected: %s, Total all tracks: %s", sec2Hms($selected_total), sec2Hms($total_length)),
				\@selectedArray,
				\@checkBoxStrings);
			print "After:",join(" ",@selectedArray),"\n" if $debug;
			return 0 if ($button == 3); # Cancel
			my $selection;
			$selected_total = 0;
			foreach $selection (@selectedArray) {
				push @result, {'filename' => $filelist[$selection-1], 'length' => $track_lengths{$filelist[$selection-1]}};
				$selected_total += $track_lengths{$filelist[$selection-1]};
			}
			print $OUT "\nTotal time: ", sec2Hms $selected_total, "\n";
			$button = promptUserOKCan(
				sprintf("******** WARNING WILL ROBINSON DANGER DANGER ******\nTotal time exceeds 80min: %s",
					 sec2Hms($selected_total)),
				"Cool, continue",
				"I'll try that again") 
				if ($selected_total > 80*60);
		} until $button == 1;
	} else {
		# Iterate over them, printing the basename and saving and summing the recording time	
		do {
			$selected_total = 0;
			foreach my $file (@filelist) {
				print $OUT basename($file,".wav");
				my $read = $wav -> read($file); #need to capture and print error details here
				$track_lengths{$file} = $read -> length_seconds();
				$total_length += $track_lengths{$file};
				printf $OUT ("\t\t%5.0fs\n", $track_lengths{$file});
			}
			printf $OUT ("\nTotal time: %s\n", sec2Hms($total_length));
			#printf "\nTotal time: %02dh%02dm%05.2fs (%.4f seconds)\n" ,$whole_hours,$whole_minutes,$remaining_seconds,$sec;
			print $OUT "Enter track numbers to use for $message, \n";
			print $OUT "separated by commas or use '-' for a range. e.g. 1-5,12,15.\n";
			my $defaultFileList = "1";
			if($#filelist > 0) {
				$defaultFileList .= "-".eval($#filelist+1);
			}
			$selectionString = promptUser ("Track numbers: ", $selectionString?$selectionString:$defaultFileList);
			my @selected = expandSelection($selectionString,1,$#filelist+1);
			print $OUT "\nYou have selected the following:\n";
			my $selection;
			foreach my $selection (@selected) {
				print $OUT $selection;
				print $OUT ": " . basename ($filelist[$selection-1],".wav");
				printf $OUT ("\t\t%5.4fs\n", $track_lengths{$filelist[$selection-1]});
				push @result, {'filename' => $filelist[$selection-1], 'length' => $track_lengths{$filelist[$selection-1]}};
				$selected_total += $track_lengths{$filelist[$selection-1]};
			}
			print $OUT "\nTotal time: ", sec2Hms $selected_total, "\n";
			print $OUT "\n******** WARNING WILL ROBINSON DANGER DANGER ******\nTotal time exceeds 80min: ", sec2Hms $selected_total, "\n" 
				if ($selected_total > 80*60);		
		} until promptUser("\nAre these selections correct?","Yes") =~ /^Y/i;
	}
	return @result;
}

# Create PostScript files with CD labels, one each for Library and Master
sub createCdInserts {
	# Create a file with the track labels contained in @selectedTracks
	my @tracks = @_;
	my @items;
	my $totalLength;
	my @args;
	print "Creating CD labels\n";
	foreach my $item (@tracks) {
		my $timeString = sec2Hms $item -> {'length'};
		$totalLength += $item -> {'length'};
		my $entry = sprintf("{#M}%-38s %12s",basename($item -> {'filename'},".wav"),$timeString);
		push @items,$entry;
	}
	push @items, sprintf("{#MB}%51s", "Total:". sec2Hms($totalLength));
	#my $recordingName = promptUser "Recording Name", "NRUC 9:30am Service";
	#my $preacher = promptUser "Preacher/speaker name", "Ian Hickingbotham";
	#my $sequenceNumber = promptUser "Sermon sequence number without the year or '#' (e.g. 23)";
	my $yr = $tm->year % 100;

	my $sequenceString = $sequenceNumber !~ /\s*/?" \#$yr\-$sequenceNumber":"";
	# use cdlabelgen to create the ps file
	# Command format example is:
	# ./cdlabelgen --category "NRUC 9:30am Service Ian Hickingbotham #09-25(Master)" --items "line one%line two%line three" --slim-case --no-date --output-file cover.ps
	foreach my $copy ("Master","Library") {
		push @CdInsertFileNames, "$projectDirectory/CD_insert_$copy.ps";
		@args = ("$pathToCdLabelGen",
			"--category", "$recordingName $preacher $sequenceString ($copy)",
			"--items", join("%",@items),
			"--slim-case",
			"--no-date",
			"--subcategory", "$dateString",
			"--output-file", $CdInsertFileNames[$#CdInsertFileNames],
		);
		print "Running: @args" if $debug > 1;
		dumpCommand("$projectDirectory/cdlabelgen_$copy.bash",@args);
		system(@args) == 0 or die "system @args failed: $!";
	}
	print "Done creating CD labels\n";
	print "finished \n" if $debug > 1;
}

sub printCdInserts {
	print "printing CD inserts\n";
	my @args;
	push @args, "lp";
	push @args, @CdInsertFileNames;
	dumpCommand("$projectDirectory/printcdinserts.bash",@args);
	system(@args) == 0 or die "printing failed: $!";
	print "done printing CD Inserts\n";
}

sub createPodcast {
	print "Creating podcast\n" if $debug;
	my @tracks = @_;
	my @args;
	push @args, "$pathToSox";
	push @args, "--no-show-progress" if($debug<2);
	foreach my $item (@tracks) {
		push @args,$item -> {'filename'};
		print "Adding " . $item -> {'filename'} . " to \@args\n" if($debug>2);
	}
	push @args, $podcastFilePath;
	print "Running ", join (":",@args), "\n" if $debug;
	dumpCommand("$projectDirectory/createpodcast.bash",@args);
	system(@args) == 0 or die "system @args failed: $!";
	# Now apply ID3 tags to resulting file
	$sermonTitle = promptUser("Sermon title?",$sermonTitle);
	$preacher = promptUser("Preacher name?", $preacher);
	$sermonSeries = promptUser("Series?", $sermonSeries);
	$sermonGenre = "speech";
	$sermonDescription = promptUser("Sermon decription?", $sermonDescription);
	if($podcastid3) {
		print "Applying ID3 Tags to MP3 file\n";
	#	`mp3info2 -t title -a artist -l album -y year -g genre -c comment -n tracknumber`;
		@args = ("mp3info2",
			 "-u", "-2",
			 "-t", $sermonTitle,
			 "-a", $preacher,
			 "-l", $sermonSeries,
			 "-y", $mp3YearString,
			 "-g", $sermonGenre,
			 "-c", $sermonDescription,
			 "-n", "1",
			 $podcastFilePath);
		print "Running ", join (":",@args), "\n" if $debug;
		dumpCommand("$projectDirectory/applyid3tags.bash",@args);
		system(@args) == 0 or (print "Setting ID3 tags failed ($!) skipping\n" && return);	
	} else {
		print "Not applying ID3 tags\n";
	}
	print "Done creating podcast\n" if ($debug);
}

sub uploadPodcast {
	my $srcFilePath = shift;
	my $ftpHost = "nruc.org.au";
	my $ftpPath = "/httpdocs/podcast/";
	my $ftpLogin = "nruc";
	my $ftpPassword = "church123";
	
	my $srcFileName = basename($srcFilePath);
	
	print "Uploading podcast ",$srcFileName,"\n";

	my @args = ("ftp", "-v", "-u");
	push @args, "ftp://" . $ftpLogin . ":" . $ftpPassword . "\@" . $ftpHost . $ftpPath . $srcFileName, $srcFilePath;
	
	print "Running ", join (":",@args), "\n";
	dumpCommand("$projectDirectory/upload.bash",@args);
	system(@args) == 0 or (print "File upload failed ($!) - skipping\n" && return);	
	
	print "Done uploading podcast\n";
}
##############################
# main Program Start
##############################


# Gather options and do help if needed or requested
GetOptions (
	'help|?' => \$help,
	'man' => \$man,
	'audacity!' => \$audacity,
	'mp3!' => \$mp3,
	'debug+' => \$debug,
	'burn!' => \$burn,
	'podcast!' => \$podcast,
	'cd-inserts!' => \$cdInserts,
	'project-date=s' => \$projectDate,
	'fix-labels!' => \$fixLabels,
	'interactive' => \$interactive,
	'ftp!' => \$upload,
	'print-inserts!' => \$printCdInserts,
	'podcastid3!' => \$podcastid3,
	'updatetags!' => \$updatetags,
	'upload!' => \$upload,
	'gui!' => \$gui
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Load any config from ini file
loadConfig;

# Use projectDate if provided on command line
$dateString = $projectDate if(defined $projectDate);

# Grab remaining project file name if provided
# path information is used from this to set base directory for other files for this project
# Expect full path of directory aup file is in or aup file itself
if ($#ARGV >= 0) {
        my $given = shift;
	$given =~ s/\/$//; # Get paramter and remove trailing slashes (/) if any
	if ($given =~ /\.aup$/i) {
		# It's an aup file, extract the directory it's in and use that as the $projectDirectory
		$projectFilePath = $given;
		($projectName,$projectDirectory,) = fileparse($projectFilePath,".aup");
		$projectFilename = fileparse($projectName);
		print "full path to project file given: $projectFilename\n" if($debug);
	} else { # no .aup extension, must be a directory
		if($given =~ m!^\.*/!) { # if given starts with / or ./ then leave path as-is otherwise prepend base dir.
			$projectDirectory = $given;
			} else {
			$projectDirectory = "$baseDirectory/$recordingsDirectoryName/$given";
		}
		$projectFilename = basename($projectDirectory) . ".aup";
		print "got project base name from directory: $projectFilename\n" if ($debug);
	}
	# Find a date in the file/path name if available and override $dateString if it is
	if($projectFilename =~ /((\d{4})-(\d{2})-(\d{2}))/) {
		print "Matched date in $projectFilename\n" if($debug>1);
		$dateString = $1;
	}
    $projectName = fileparse($projectFilename, ".aup");
} else { # create project and directory names if nothing given on command line
        $projectName = "$dateString" . "$audacityProjectSuffix";
        $projectFilename = "$projectName\.aup";
	$projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName";
}
$projectFilePath = "$projectDirectory/$projectFilename";
$projectDataDirectory = "$projectDirectory/$projectName$audacityProjectDataDirectorySuffix";

# Setup directories constructed from projectName
setupPaths $projectDirectory;

print "projectDate: $projectDate\n" if $debug;
print "dateString: $dateString\n" if $debug;
print "projectName: $projectName\n" if $debug;
print "projectFilename: $projectFilename\n" if $debug;
print "projectFilePath: $projectFilePath\n" if $debug;
print "projectDataDirectory: $projectDataDirectory\n" if $debug;

# Read tags from project file if it exists, otherwise from template, get user confirmation then
# create a new projectfile if $filename not specified on command line

configureProject; 

print $OUT "audacity: $audacity\n" if $debug > 1;
print $OUT "podcast: $podcast\n" if $debug > 1;

# If any steps are explicity requested, set all others still enabled by default (i.e. value == 2) to disabled
if(($audacity eq 1) ||
   ($mp3 == 1) ||
   ($burn == 1) ||
   ($podcast eq 1) ||
   ($cdInserts == 1) ||
   ($fixLabels == 1) ||
   ($upload == 1) ||
   ($printCdInserts == 1) ||
   ($podcastid3 == 1) )
{
	print $OUT "Found execute-only option, turning of on-by-default options\n" if $debug;
	$audacity = 0 if $audacity == 2;
	$mp3 = 0 if $mp3 == 2;
	$burn = 0 if $burn == 2;
	$podcast = 0 if $podcast == 2;
	$cdInserts = 0 if $cdInserts == 2;
	$fixLabels = 0 if $fixLabels == 2;
	$upload = 0 if $upload == 2;
	$printCdInserts = 0 if $printCdInserts == 2;
	$podcastid3 = 0 if $podcastid3 == 2;
	print $OUT "Options: ",
		$audacity?"audacity ":"",
		$mp3?"mp3 ":"",
		$burn?"burn ":"",
		$podcast?"podcast ":"",
		$cdInserts?"cdinserts ":"",
		$fixLabels?"fixlabels ":"",
		$upload?"upload ":"",
		$printCdInserts?"printcdinserts ":"",
		$podcastid3?"podcastid3 ":"","\n";
};

# Run Audacity to capture recording
runAudacity if $audacity;

## Open today's aup file
while(checkTracks($projectFilePath)) {
   print "Missing wav files or incorrect label lengths.\n";
   my $r = promptUser ("Re-run Audacity to re-export wav files?","Yes");
   if($r =~ /^Y/i) {runAudacity;}
   if($r =~ /^N/i) {print "Quitting\n"; exit;}
}

# Create mp3 files from wav files
$mp3?makeMp3s:print "Not making MP3s\n";

# Burn CDs
@selectedTracks = selectTracks("burning to CD and/or Label inserts") if ($cdInserts || $burn);
if($burn) {
	my @blanks = checkBlankMedia;
	while($#blanks < 0 &&
	   promptUserOKCan ("No blank, writable CDs found\nTry again or Skip burning?","Try Again","Skip") == 1) {
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

# Assume CD labels are only wanted when CDs are burned
createCdInserts(@selectedTracks) if $cdInserts;
printCdInserts() if ($printCdInserts and $cdInserts);

# Create podcast file and FTP to web server.
if ($podcast) {
	@selectedTracks = selectTracks("sermon podcast");
	createPodcast(@selectedTracks);
} else { print "Not creating podcast\n"}

# Upload podcast unless noupload or podcastFilePath doesn't exist
if($upload) {
	if(-r $podcastFilePath) {
		uploadPodcast($podcastFilePath);
	} else {
		warn "Can't upload: $podcastFilePath not found";
	}
} else {
	print "Not uploading podcast\n";
}

print "Everything's done\n";
exit;
__END__

=head1 nrpod

nrpod - Capture and process NRUC sermon podcast

=head1 SYNOPSIS

nrpod [options] [project name]

 Options:
   --help               brief help message
   --man                full documentation
   --project-date YYYY-MM-DD
                        specify date for project files and labels (ignored if 
                        project name already contains a valid date string)

 Optons - process steps:
   --[no]audacity       [don't] run audacity
   --[no]mp3            [don't] create mp3 files
   --[no]burn           [don't] burn CD
   --[no]podcast        [don't] create podcast MP3 or upload it
   --[no]fix            [don't] automatically fix non-zero length track labels
                        in audacity project file
   --[no]cd-inserts     [don't] create CD label files
   --[no]upload         [don't] FTP mp3 podcast to webserver
   --[no]ftp            [don't] Same as --upload
   --[no]podcast        [don't] create podcast file
   --[no]print-inserts  [don't] send CD Inserts to the printer
   --[no]podcastid3     [don't] apply ID3 tags to podcast file

   --debug             Turns on debugging. Can be specified mutiple times
                       to increase verbosity.
   --fix-labels        I have no idea.
   --interactive       Asks all option questions interactively (not operational)
   --updatetags        Requests confirmation of all tags in aup project file.
                       This is also what happens when a new file is created.
	
By default all process steps are executed.
Specifying the [no] prefix to that step prevents it from running.
For all process step related options, specifying any one in the positive disables all other steps unless they are also specificed in the positive as an option.

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
