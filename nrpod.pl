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
# Done 8. Ask all questions up front
# Done 9. Improve defaulting when new project file is created from template (either have defaults in program or fix defauts in template file)
# Done 10. Don't die at any failed command - change to pass through if not critical.
# 11. Add leveling/normalizing via sox
# Done 12. FTP progress bar
# Done 13. Add "comments" field in ID3 tags/parameters
# Done 14. Fix location of new project file (currently defaults to .)
# Done 15. Fix CD label when there is no sequence number
# Done 16. Make default tag year this year in configureProject. (removed year from template project file)
# Done 17. Insert date into project name if none found when creating a new project (new project date string defaults to current date or to projectDate [--project-date] if provided on command line)
# Done 18. re-factor configureProject()
# 19. Add support for Scripture readings
# Done 20. Fix dialog boxes that say "Alert" - maybe add icons? (message now has two parts - text and informative-text


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
use IO::File;
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
my $eventTimeDefault = "9:30am";
my $eventTime = "";
my $scriptureReadingsDefault = "Genesis 1:1-5;Matthew 1:1-17";
my $scriptureReadings;
my $wavFilenamePrefix;
my $pathToFfMpeg;
my $pathToLame;
#my $newAlbumString;
# mp3 prefixes are for individual mp3 files made from tracks
my $mp3GenreStringDefault = "Christian worship";
my $mp3GenreString = "";
my $tm = localtime;
my $mp3YearStringDefault = $tm->year+1900;
my $mp3YearString;
my $mp3ArtistNameStringDefault = "North Ringwood Uniting Church";
my $mp3ArtistNameString = "";
# project prefixes are for the  aup project file
my $projectArtistNameStringDefault = $mp3ArtistNameStringDefault;
my $projectArtistNameString = "";
# Used as track title for whole service recording
my $projectTitleStringDefault = "Message podcast";
my $projectTitleString = "";
my $pathToCdBurnerXp;
my $pathToCreateCD;
my $pathToCD;
my %drives;
my %blanks;
my $windows;
my @selectedTracks;
my @burnSelectedTracks;
my @podcastSelectedTracks;
my $dateString = sprintf("%04d-%02d-%02d",$tm->year+1900,$tm->mon+1,$tm->mday);
my $pathToSox;
# The string (%s) in $recordingNameDefault is replaced with $eventTime (e.g. 9:30am)
my $recordingNameDefault = "NRUC %s Service";
my $sequenceNumber;
my $interactive;
my $podcastFilePath;
my @CdInsertFileNames;
my $sermonTitle = "";
my $sermonTitleDefault = "";
my $sermonSeries = "";
my $sermonSeriesDefault = "General";
my $sermonGenre = "Speech";
my $sermonDescription = "";
my $sermonRegexDefault = "welcome|script|message|benediction|prayer";

# Error tracking
my $globalErrorCount = 0;
my $globalErrorMessages = "Message log:\n";

# Options variables
my $audacity = 2;
my $help;
my $man;
my $burn = 2;
my $mp3 = 0;
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
my $optionsPrompt = 1;

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
		$cdrv = `$pathToCD inputbox --title "nrpod" --informative-text "$promptString" --no-newline --text "$defaultValue" --button1 "OK" --icon 'gear'`;
		($button_rv, $rv) = split /\n/, $cdrv, 2;
	} else { # terminal interface only
		$rv = $term->readline("$promptString ",$defaultValue);
	}
	return $rv;
}

sub promptUserAup {
	# Prompt user to browse and select an existing aup file
	# Usage: promptUserAup promptstring [defaultdirectory]
	my($promptString,$defaultDirectory) = @_;
	my $rv;
	$rv = `$pathToCD fileselect --title "nrpod" --text "$promptString" --with-extensions .aup --with-directory $defaultDirectory --icon 'document'`;
	return $rv;
}

sub promptUserYN {
	# Input is returned as function result
	my($promptString,$defaultValue) = @_;
#	$defaultValue = $defaultValue?$defaultValue:undef;
	my ($rv, $cdrv);
	if($gui) {
		$cdrv = `$pathToCD yesno-msgbox --title "nrpod" --no-newline --label "$promptString" --icon 'gear'`;
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
	return `$pathToCD msgbox --title "nrpod" --label "$promptString" --button1 "$Button1" --button2 "$Button2" --icon 'gear'`;
	} else { # not GUI
		return 1 if($term->readline("$promptString ",$Button1) =~ /^$Button1/);
		return 2;
	}
}

sub promptUserRadio {
	# Button clicked is returned as function result
	my($promptString,$Button1,$Button2,@items) = @_;
	$Button1 = "OK" unless defined $Button1;
	$Button2 = "Cancel" unless defined $Button2;
    print $OUT ("Select from:\n") if $verbose;
    if($verbose) {
        for my $i (0 .. $#items) {
            print "$i: $items[$i]\n";
        }
    }
	my($button,$option) = split /\n/,`$pathToCD radio --title "nrpod" --label "$promptString" --button1 "$Button1" --button2 "$Button2" --items @items --selected 0 'gear'`;
    print ("Selected: $option\n") if $verbose;
	return $button,$option;
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
    open CD, "$pathToCD checkbox --title \"$title\" --label \"$label\" --width 600 --button1 OK --button2 Recalculate --button3 Cancel --debug --items @{$ref_tracks} --checked @checkedBoxes --icon 'gear'|" or die "$pathToCD failed: $!";
    chomp($button = <CD>);
    $boxes = <CD>;
    close CD;
    if(defined $boxes) {
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
		print $OUT "Inside:",join(" ",@{$ref_selected}),"\n" if $debug>2;
    }
	return $button;
}

# Presents and requsts selection of a subset of options
sub promptUserForOptions {
	my @optionList = (
		{name => "Run audacity",ref => \$audacity},
		{name => "Create MP3 files",ref => \$mp3},
		{name => "Burn CD(s)",ref => \$burn},
		{name => "Create podcast file",ref => \$podcast},
		{name => "Create CD insert PDF",ref => \$cdInserts},
		{name => "Upload podcast to FTP server",ref => \$upload},
		{name => "Print CD Inserts",ref => \$printCdInserts},
        {name => "Debugging",ref => \$debug},
        {name => "Verbose",ref => \$verbose},
	);
#    print "\$\#optionList: $#optionList\n";
#    foreach $opt (@optionList) {
#        print("$opt->{name}:${$opt->{ref}}\n");
#    }
#    print "\n";
	my $index;
    my @checkedOptions;
    my @mixedOptions;
	for $index (0 .. $#optionList) {
        print $OUT ("index: $index, name: $optionList[$index]{name}, ref: ${$optionList[$index]{ref}}\n") if ($debug>2);
        # Push the checked option on the list if it is == 1 (i.e supplied on the command line).
        # If it is == 2, means selected by default and shouldn't be checked here.
		push (@checkedOptions,$index) if(${$optionList[$index]->{ref}} == 1);
		push (@mixedOptions,$index) if(${$optionList[$index]->{ref}} >= 2);
	}
	print $OUT ("Checked Options: ",join("|",@checkedOptions),"\n") if ($debug>2);
	my @optionListText;
	for $index (0 .. $#optionList) {
#        print $OUT ("index: $index, name: $optionList[$index]{name}, ref: ${$optionList[$index]{ref}}\n");
		push (@optionListText,"'".$optionList[$index]->{name}."'");
	}
#    print join("\n",@optionListText);
    print "\n";
	@CDARGS = (
		"checkbox",
		"--title $0",
		"--label Choose options for this session",
#		"--width 600",
		"--button1 OK",
		"--button2 Cancel",
		"--debug",
		"--items @optionListText",
		"--checked @checkedOptions",
        "--mixed @mixedOptions",
		);
	open (CD, "$pathToCD @CDARGS |") or die "$pathToCD failed: $!";
	# open (CD, "$pathToCD checkbox --title $0 --label Choose options for this session --width 600 --button1 OK --button2 Quit --debug --items", @optionListText, "--checked @checkedOptions|") or die "$pathToCD failed: $!";
	$button = <CD>;
	$options = <CD>;
	close CD;
    if (defined $options) {
        (@options) = split /\s/,$options;
        for $opt (0.. $#options) {
            print "Item[$opt] from dialog: $options[$opt]\n" if ($debug>2);
            print $OUT "Before: $optionList[$opt]->{name} is ${$optionList[$opt]->{ref}}\n" if ($debug>2);
            ${$optionList[$opt]->{ref}} = 1 if($options[$opt] == 1);
            ${$optionList[$opt]->{ref}} = 0 if($options[$opt] == 0);
            # Don't change option value if set to mixed (-1)
            print $OUT "After: $optionList[$opt]->{name} is ${$optionList[$opt]->{ref}}\n" if ($debug>2);
        }
    }
	# my $boxnum = 1;
	# Reset selected back to nothing
	return $button;
}

sub message {
	# Write to a message box and/or stdout
	my $cdrv;
	my($promptString,$icon,$informativeText) = @_;
	if($gui) {
		$cdrv = `$pathToCD msgbox --title "nrpod" --text "$promptString" --informative-text "\'$informativeText\'" --button1 OK --icon $icon`;
	}
	print $OUT "$icon: $promptString ($informativeText)\n";
}

sub longMessage {
    # Write many lines in a text box as a message (not editable)
	my $cdrv;
	my($informativeText,$longMessageText) = @_;
	if($gui) {
		$cdrv = `$pathToCD textbox --title "nrpod" --text "$longMessageText" --informative-text "$informativeText" --button1 OK`;
	}
	print $OUT "$informativeText: $longMessageText\n";
}

sub loadConfig {
    # This stuff should all be moved to the config file and made specific to the installation instance

    # Figure out which machine we're on
    chomp(my $hostname = `hostname`);
    print $OUT "hostname: $hostname\n" if $debug > 1;
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
    print $OUT "basedirectory: $baseDirectory\n" if $debug>1;
} # loadConfig

sub dependenciesArePresent {
    # Checks for critical helper tools
    # Prints array of missing tool paths
    my @missingTools;
    @dependencyList = ($pathToCD,
        $pathToSox,
        $pathToFfMpeg,
    #        $pathToAudacity,
        $pathToLame,
        $pathToCdLabelGen,
    );
    foreach (@dependencyList) {
        chomp(my $pathToTool = `which $_`);
        print $pathToTool,"\n" if $debug;
        push @missingTools,$pathToTool unless -e $pathToTool;
    }
    print $OUT "Missing some kit:\n",join("\n",@missingTools),"\n" if @missingTools;
    return $#missingTools < 0;
}

sub setupPaths { # Usage: setupPaths projectDirectory
	# ProjectDirectory contains the .aup file, wav directory, mp3 directory and audacity _data directory
	# Now build the other useful path strings and check that the required ones exist
	
	# Expected path for multimedia PC at NRUC shown in comments
	my $projectDirectory = shift;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/
	#        checkDirectory($projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName");
	checkDirectory($projectDirectory);
	print $OUT "projectDirectory: $projectDirectory\n" if $debug>1;
	#        checkDirectory($projectDataDirectory = "$projectDirectory/$projectName"."_Data");
	#        print "projectDataDirectory: $projectDataDirectory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/wav
	checkDirectory($wavDirectory = "$projectDirectory/$wavOutputDirectoryName");
	print $OUT "wavDirectory: $wavDirectory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/mp3
	checkDirectory($mp3Directory = "$projectDirectory/$mp3OutputDirectoryName");
	print $OUT "mp3Directory: $mp3Directory\n" if $debug>1;
	# D:/users/Helix Multimedia/service_recordings/2009-07-19_service/2009-07-19_audacity_project.aup
	$projectFilePath = "$projectDirectory/$projectName.aup";
	print $OUT "projectFilePath: $projectFilePath\n" if $debug>1;
	
	# Check and create data directory if it doesn't exist
	checkDirectory $projectDataDirectory;
	
	# Prefix for all wav files
	$wavFilenamePrefix = "$projectName";
	
	# Locate template file
	# D:/users/Helix Multimedia/service_recordings/template.aup
	$projectTemplateFilename = "$baseDirectory/$recordingsDirectoryName/template.aup";
	-f $projectTemplateFilename || die "can't find template file: $projectTemplateFilename";
} #setupPaths

sub configureProject {
	# Open the aup project file and get tags or set them from command prompts
	
	my $PROJECT;
	my $tag;
	my $safePreacher;
	my $fileSafeRecordingName;
	my $tagsWereModified;
	
	# Loads the config. file into a hash: Eventually, all config will be in here
	#	Config::Simple->import_from('nrpod.cfg', \%Config);

    # Look for and open Audacity project file into an XML struct if it exists
    # Otherwise, ask t create a new one.
	if(-e $projectFilePath) {
		print $OUT "Reading from existing project file\n" if($verbose);
		$PROJECT = XML::Smart->new($projectFilePath);
	} else {
		if (promptUserYN("$projectFilePath does not exist - create?", "Y") !~ /^Y/i) {
				message("Don't know what project file to use - quitting\n",'caution',"Try again.");
				exit;
			}
		$updatetags = 1; # New project file - tags must be updated
        # Not using $audacity = 1 here because it will get treated as an execute only option and othe rdefault swill be turned off
        $audacity = 3; # Nothing in the default audacity project, therefore no tracks therefore must run audacity
		print $OUT "Creating new project file " . basename($projectFilePath) . " from " . basename($projectTemplateFilename) . "\n" if($verbose);
		$PROJECT = XML::Smart->new($projectTemplateFilename);
	}

    # For each of the key service parameters:
    #   - pull from aup file XML,
    #   - prompt for it or set from default if it doesn't exist
    #   - keep track of if any were modified so we know if we have to write the aup file out again
    # Silently use default (where no prompt is provided)
    #
    $tagsWereModified |= configureID3Tag($PROJECT,\$eventTime,'TIME',$eventTimeDefault,"Enter time of event");
    $tagsWereModified |= configureID3Tag($PROJECT,\$recordingName,'ALBUM',sprintf($recordingNameDefault,$eventTime),"Album (recording) name?");
    # Make a filename-safe version of the string for use, well, in the filename
	($fileSafeRecordingName = lc $recordingName) =~ tr/: /-_/;
    $tagsWereModified |= configureID3Tag($PROJECT,\$projectArtistNameString,'ARTIST',$projectArtistNameStringDefault,);
    $tagsWereModified |= configureID3Tag($PROJECT,\$mp3YearString,'YEAR',$mp3YearStringDefault,);
    $tagsWereModified |= configureID3Tag($PROJECT,\$mp3GenreString,'GENRE',$mp3GenreStringDefault,);
    $tagsWereModified |= configureID3Tag($PROJECT,\$projectTitleString,'TITLE',$projectTitleStringDefault,);
	$tagsWereModified |= configureID3Tag($PROJECT,\$preacher,'PREACHER',$preacherDefault, "Preacher/speaker name");
    # Make a filename-safe version of the string for use, well, in the filename
	($safePreacher = $preacher) =~ tr/ /-/;
    $tagsWereModified |= configureID3Tag($PROJECT,\$sequenceNumber,'SEQUENCE',"",
        "Enter Sermon sequence number without the year or '#' (e.g. 23)\n".
        "Only used for placed minister. Leave blank otherwise");
    $tagsWereModified |= configureID3Tag($PROJECT,\$sermonTitle,'SERMONTITLE',"", "Message title?");
    $tagsWereModified |= configureID3Tag($PROJECT,\$sermonSeries,'SERIES',$sermonSeriesDefault,"Series?");
    $tagsWereModified |= configureID3Tag($PROJECT,\$sermonDescription,'COMMENTS',"", "Sermon description?");
    $tagsWereModified |= configureID3Tag($PROJECT,\$scriptureReadings,'NRSCRIPTURE',$scriptureReadingsDefault, "Scripture readings?");

    # Now make a path for the location of the mp3 sermon podcast file
	$podcastFilePath = "$mp3Directory/$dateString\_$fileSafeRecordingName\_$safePreacher\.mp3";
	
	# Save Audaciy project XML to a new project file if it was created, updated or missing tags were modified
	$PROJECT->save($projectFilePath) if ($updatetags || $tagsWereModified);


} #configureProject

##################################################
# tagsweremodified = configureID3Tag(project,
#                                    reference to global variable,
#                                    name of tag,
#                                    default,
#                                    prompt string)
# Checks for existence of ID3 Tag in audacity project file and conditionally:
#  - prompts for new value
#  - sets global variable
#  - creates and sets value in aup project file
##################################################
sub configureID3Tag {
    my $tagsWereModified = 0;
    my $newtag;
    my ($project, $ref_var, $tagName, $default, $promptString) = @_;
    ${$ref_var} = $project->{project}{tags}{tag}('name','eq',$tagName){'value'};
	if(${$ref_var}) {
		print $OUT "$tagName tag: ${$ref_var}\n" if $debug;
        $promptString = $tagName unless $promptString;
		${$ref_var} = promptUser("$promptString",${$ref_var}) if $updatetags;
		$project->{project}{tags}{tag}('name','eq',$tagName){'value'} = ${$ref_var};
	} else {
		print $OUT "$tagName attribute undefined in project file, creating.\n" if $debug;
        if(defined $promptString){
            ${$ref_var} = promptUser (
            $promptString,$default);
            $newtag = {
                name	=> $tagName ,
                value	=> ${$ref_var}
            };
        } else { # no prompt, silently use provided default
            print "Setting $tagName to default: $default" if $debug;
            $newtag = {
                name	=> $tagName ,
                value	=> $default
            };
        }
		push(@{$project->{project}{tags}{tag}} , $newtag) ;
		$tagsWereModified = 1;
	}
    return $tagsWereModified;
}

sub runAudacity {
	##############################################
	# Launch Audacity
	# Expect user to export to wav files as normal
	##############################################
	message("Starting audacity",'info',"When you click OK, Audacity will start. Export tracks using 'export multiple' to wav directory: $wavDirectory then quit Audacity to continue.\n");
	print $OUT "Waiting for Audacity to exit ...";
        -f $projectFilePath || die "Can't find $projectFilePath\n";
        # convert to backslash paths for windows
        my $runPath = $projectFilePath;
	my @args;
        $runPath =~ s!/!\\!g if $windows;
	print $OUT "Running audacity with $runPath ... " if $debug>1;
	@args = ("open", "-W", "$pathToAudacity", "$runPath");
	dumpCommand("$projectDirectory/runaudacity.bash",@args);
	system(@args) == 0 or die "system @args failed: $?";
	print $OUT "finished\n" if $debug>1;
}

sub convertWav2Mp3 {
    my $trackTitle = shift;
    my $trackNumber = shift;
	my $numberOfTracks = shift;
    my $wav = shift;
    my $mp3 = shift;
	my @args;
	@args = ("$pathToLame", $debug<3?"--quiet":"",
                 "--tl", "$recordingName",
                 "--ty", $mp3YearString,
                 "--tt", "$trackTitle",
                 "--tn", $trackNumber."/".$numberOfTracks,
                 "--ta", "$projectArtistNameString",
		 "--tg", "$mp3GenreString",
		 "$wav",
		 "$mp3");
	print $OUT "Running: @args\n" if $debug > 2;
	dumpCommand("$projectDirectory/track_".$trackNumber."_lame.bash",@args);
	if(system(@args) != 0) {
        my $whatWentBang = $!;
        message ("system call failed:",'stop',"@args: $whatWentBang");
        $globalErrorMessages .= "system @args failed: $whatWentBang\n";
        $globalErrorCount++;
    }
	print $OUT "finished\n" if $debug > 2;
}

sub runFfMpeg {
    my $trackTitle = shift;
    my $trackNumber = shift;
    my $wav = shift;
    my $mp3 = shift;
	my @args;
	@args = ("$pathToFfMpeg","-y",
                 "-i", $wav,
                 "-album", $recordingName,
                 "-year", $mp3YearString,
                 "-title",  $trackTitle,
                 "-track", $trackNumber,
                 "-author", $projectArtistNameString,
                 #"-metadata", "Genre=$mp3GenreString",
                 $mp3);
	print $OUT "Running: @args" if $debug > 1;
	dumpCommand("$projectDirectory/ffmpeg.bash",@args);
    if(system(@args) != 0) {
        my $whatWentBang = $!;
        message ("system call failed:",'stop',"@args: $whatWentBang");
        $globalErrorMessages .= "system @args failed: $whatWentBang\n";
        $globalErrorCount++;
    }
	print $OUT "finished\n" if $debug > 1;
}

sub checkTracks {
	my $errors_found = 0;
	my $projectFilePath = shift;
	##############################################
	# check labels - times, illegal characters
	# check all wav files exist
	##############################################
	#my $wavsDirectory = fileparse($projectFilename, ".aup");
	print $OUT "Checking labels and wav files ..." if $verbose;
	
	# Open today's aup file
	print $OUT "checking project file: $projectFilePath\n" if $debug>1;
	message("Failed to open Audacity project file: \n",'stop',"$projectFilePath") && exit unless -r $projectFilePath;

	$AUP = XML::Smart->new($projectFilePath);
	
	# Save to a backup project file unless one already exists
	$AUP->save($projectFilePath . ".bak") unless (-f $projectFilePath . ".bak");
	
	print $OUT "Looking in $wavDirectory for wav files\n" if $debug>2;
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
    $numlabels = 0 unless $numlabels;
	print $OUT "found $numlabels track labels\n" if $debug>1;
	$errors_found++ unless $numlabels;
	my @llist = @{$AUP->{project}{labeltrack}{label}};
    if (!(@llist && $#llist == 0 && $llist[0]->{title} eq "")) { # Check for empty list 
    #	if(@llist && $#llist > 0 && $llist[0]->{title}) {
		foreach my $track (@llist) {
	#need to add check for zero count tracks
			my $title = $track->{title};
			my $ti = $track->i()+1;
			print $OUT "checking track ",$track->i()+1,": $track->{title} ($track->{t}:$track->{t1})\n" if $debug>1;
			if ($track->{t1} != $track->{t}) {
				print $OUT "label not zero length: $track->{title} : $track->{t} : $track->{t1}\n" if $verbose;
				# Fix it
				print $OUT "fixing...\n" if ($verbose && $fixLabels);
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
			print $OUT "checking for $wavfile: $tr\n" if $debug>2;
		}
	} else {
		message ("No tracks saved - nothing to check",'caution',"Did you forget to create labels?");
		return 1; # Error found
	}
	# Save to a new project file
	$AUP->save($projectFilePath);
        my $msgtext = "$errors_found errors: " if($errors_found);
	if($errors_found) {
		if($fixLabels) {
			message($msgtext."fixed",'info',"specify --nofixlabels option if you don't want this")}
		else {
			message($msgtext."NOT fixed",'caution',"specify --fixlabels option if you want this")}
	}
#	print "Errors " . $fixLabels?"fixed\n":"NOT fixed\n" if ($errors_found);
	message("Finished Checking Tracks with $errors_found errors\n",'info',"Processing won't continue until errors are fixed.") if ($debug>1 and $errors_found>0);
#	print $OUT "OK\n" unless ($errors_found);
    $errors_found;
} #checkTracks

sub makeMp3s {
	##############################################
	# Create MP3 files from the wavs.
	##############################################
	# Open today's aup file
    print $OUT "Making MP3s\n" if($verbose);
	print $OUT "looking in $wavDirectory for wav files\n" if $debug>2;
	my $numlabels = $AUP->{project}{labeltrack}{numlabels};
	my @llist = @{$AUP->{project}{labeltrack}{label}};

	# Start progressbar
	### Open a pipe to the program
	my $fh = IO::File->new("|$pathToCD progressbar --title 'nrpod - Creating MP3 files'") if $gui;
	$fh->autoflush(1) if defined $fh;

	my $percent = 0;
	my $trackPercent = 100.0/$#llist;
	print $OUT "$trackPercent% each track\n" if $debug;
	foreach my $track (@llist) {
		my $title = $track->{title};
		my $ti = $track->i()+1;
		print $OUT "Creating MP3 of track $ti: $title\n" if $verbose;
		print $fh "$percent Creating MP3 of track $ti: $title\n" if defined $fh;
		# $fh->flush() if defined $fh;

		# Check the wav file exists
		my $tiString = sprintf("%02d", $ti);
		my $wavfile = "$wavDirectory/".$tiString."-$title.wav";
		#print $OUT "$title\n" if($verbose);
		if(-r $wavfile){
                        convertWav2Mp3($title, $ti, $numlabels, $wavfile, "$mp3Directory/".$tiString."-$title.mp3");
		}
		$percent += $trackPercent;
		print $OUT "$percent%\r" if $debug;
#		print $fh "$percent\n" if defined $fh;
		}
    print $OUT "Finished Making $numlabels MP3 files from wav files\n" if($verbose);
	### Close the filehandle to send an EOF
	$fh->close() if defined $fh;
}

sub checkBlankMedia {
    # returns number of blank media found and stored in %blanks
    print $OUT "Checking for drives to use\n" if $debug >1;
	print $OUT "Looking for CD-R(W) drives and blank disks: running \"drutil list\"\n" if $debug > 2;
    open (DRUTIL, "drutil list |") || die "can't fork drutil: $!\n";
    while (<DRUTIL>) 
    {
        print if $debug > 2;
        # scan lines for "CD-Write: -R"
        if (/^(\d)\s?(.*)/) {$drives{$1} = $2}
    }
    close DRUTIL || die "can't close drutil pipe after list command: $!\n";
	my $foundCdr;
	my $isBlank;
	my $noMedia;
	foreach my $drive (keys %drives) {
		$foundCdr = 0;
		$isBlank = 0;
		$noMedia = 0;
		print $OUT "found{$drive: $drives{$drive}}\n" if $debug > 2;
		print $OUT "running \"drutil -drive $drive status\"\n" if $debug > 2;
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
			print $OUT "drive $drive has a writable CD-R in it\n" if $debug > 2;
			push @blanks,$drive;
		}
		$anyMedia |= $blanks{$drive};
	}
	@blanks;
}

sub BurnCD {
	##############################################
	# Burn CD using the wav files and drutil
	##############################################
	my $drive = shift;
	my @selectedTracks = @_;
	print $OUT "Burning drive $drive from $wavDirectory/burn\n" if $verbose;
	
	# Remove burn directory if it already exists
	rmdir "$wavDirectory/burn" if -d "$wavDirectory/burn";
	# Create burn directory for symlinks
	checkDirectory("$wavDirectory/burn");
	my $bn;
	my @args;
	# Create symlink in subdir for each selected track
	foreach my $track (@selectedTracks) {
		$bn = basename($track->{'filename'});
		print $OUT "Creating $wavDirectory/burn/$bn -> ../$bn\n" if($debug > 1);
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
        print $OUT "Running: @args" if $debug >2 ;
		dumpCommand("$projectDirectory/burncd.bash",@args);
        if(system(@args) != 0) {
            my $whatWentBang = $!;
            message ("system call failed:",'stop',"@args: $whatWentBang");
            $globalErrorMessages .= "system @args failed: $whatWentBang\n";
            $globalErrorCount++;
        }
        print "Finished Burning CD\n"  if $verbose;
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
	# Usage:
    # ($button,@selected) = selectTracks (<prompt message>,regex for default track selection)
	# Returns button and array of hashes %result{'filename' => <full path to track wav file>,'length' => <track length in seconds>}
	my $message = shift;
    my $selectRE = shift;
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
	print $OUT ("Selecting tracks ($message)\n") if($verbose);

	# Grab a file glob from the wav directory
	chomp (@filelist = glob("$wavDirectory/[0-9][0-9]-*.wav"));

    # Select tracks based on regex provided
    $index = 1;
    print "Starting to look for matching filenames\n" if($debug);
    foreach my $file (@filelist) {
        if($file =~ m/$selectRE/i){
            print "Matched $file\n";
    #        print "Comparing $file with $regex\n" if($debug>1);
            push (@selectedArray,$index);
        }
        $index++;
    }
    print "Selected Array: @selectedArray\n" if($debug);
	# Define a default list of selected tracks (all of them)
#	$initialSelectionString = "1";
#	if($#filelist > 0) {
#		$initialSelectionString .= "-".eval($#filelist+1);
#	}
#	@selectedArray = expandSelection($initialSelectionString,1,$#filelist+1);

    # Choose a path based on if gui is avaiable or not
    # For GUI, present list of checkboxes and return actual button pressed plus selected array
    # for terminal ($gui == 0), return button == 1 always plus selected array.
    my $button;
	if($gui)
	{
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
                # Add duration to string
				$checkBoxStrings{$file} .= sprintf("\t\t%s", sec2Hms($track_lengths{$file}));
                # Close quoted string
				$checkBoxStrings{$file} .= "\"";
				push(@checkBoxStrings,$checkBoxStrings{$file});
			}

			$selected_total = 0;
			foreach $selection (@selectedArray) {
				$selected_total += $track_lengths{$filelist[$selection-1]};
			}
			print "Before:",join(" ",@selectedArray),"\n" if $debug>2;

			$button = promptUserForTracks (
				"Select tracks for $message",
				sprintf ("Total selected: %s, Total all tracks: %s", sec2Hms($selected_total), sec2Hms($total_length)),
				\@selectedArray,
				\@checkBoxStrings);
            print "Got button = $button back from promptUserForTracks\n" if ($debug > 2);
			print "After:",join(" ",@selectedArray),"\n" if $debug>2;
			return $button,() if ($button == 3); # Cancel
			my $selection;
			$selected_total = 0;
            @result = ();
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
        # Always return button == 1
        $button = 1;
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
	return $button,@result;
}

# Create PostScript files with CD labels, one each for Library and Master
sub createCdInserts {
	# Create a file with the track labels contained in @selectedTracks
	my @tracks = @_;
	my @items;
	my $totalLength;
	my @args;
    # Start with sermon title and series as the first line,
    # include a nothing entry to create a blank line between the title and the first track
    push(@items,"$sermonTitle ($sermonSeries)","");
	print "Creating CD inserts\n";
	foreach my $item (@tracks) {
		my $timeString = sec2Hms $item -> {'length'};
		$totalLength += $item -> {'length'};
        # Add each track in mono-spaced font {#M}
		my $entry = sprintf("{#M}%-38s %12s",basename($item -> {'filename'},".wav"),$timeString);
		push @items,$entry;
	}
    # Add tracks total line in mono-spaced bold {#MB}
	push @items, sprintf("{#MB}%51s", "Total:". sec2Hms($totalLength));
	my $yr = $tm->year % 100;

    # Substitute an non-empty sequenceNumber for the full thing and place result into sequenceString
	(my $sequenceString = $sequenceNumber) =~ s/\d+/\#$yr\-$sequenceNumber/;
    print "Sequence number: $sequenceNumber\n" if $debug>1;
    print "Sequence string: $sequenceString\n" if $debug>1;
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
        if(system(@args) != 0) {
            my $whatWentBang = $!;
            message ("system call failed:",'stop',"@args: $whatWentBang");
            $globalErrorMessages .= "system @args failed: $whatWentBang\n";
            $globalErrorCount++;
        }
	}
	print "Done creating CD labels\n";
	print "finished \n" if $debug > 1;
}

sub printCdInserts {
	print $OUT "printing CD inserts\n" if $verbose;
	my @args;
	push @args, "lp";
	push @args, @CdInsertFileNames;
	dumpCommand("$projectDirectory/printcdinserts.bash",@args);
    if(system(@args) != 0) {
        my $whatWentBang = $!;
        message ("system call failed:",'stop',"@args: $whatWentBang");
        $globalErrorMessages .= "system @args failed: $whatWentBang\n";
        $globalErrorCount++;
    }
	print "done printing CD Inserts\n" if $verbose;
}

sub createPodcast {
	print "Creating podcast\n" if $verbose;
	my @tracks = @_;
	my @args;
	push @args, "$pathToSox";
	push @args, "--no-show-progress" if($debug<2);
	foreach my $item (@tracks) {
		push @args,$item -> {'filename'};
		print $OUT "Adding " . $item -> {'filename'} . " to \@args\n" if($debug>2);
	}
	push @args, $podcastFilePath;
	print $OUT "Running ", join (":",@args), "\n" if $debug;
    # Save a copy of our command
	dumpCommand("$projectDirectory/createpodcast.bash",@args);
    # Run the sox command
	if(system(@args) != 0) {
        my $whatWentBang = $!;
        message ("system call failed:",'stop',"@args: $whatWentBang");
        $globalErrorMessages .= "system @args failed: $whatWentBang\n";
        $globalErrorCount++;
        $podcastid3 = 0; #inhibit applying ID3 tags - probably no file
    }
	# Now apply ID3 tags to resulting file
	$sermonGenre = "speech";
	if($podcastid3) {
		print $OUT "Applying ID3 Tags to MP3 file\n" if $debug;
	#	`mp3info2 -t title -a artist -l album -y year -g genre -c comment -n tracknumber`;
		@args = ("mp3info2",
			 "-u", "-2",
			 "-t", "$sermonTitle",
			 "-a", "$preacher",
			 "-l", "$sermonSeries",
			 "-y", "$mp3YearString",
			 "-g", "$sermonGenre",
			 "-c", "$sermonDescription",
			 "-n", "1",
			 "$podcastFilePath");
		print "Running ", join (":",@args), "\n" if $debug;
		dumpCommand("$projectDirectory/applyid3tags.bash",@args);
        if(system(@args) != 0) {
            my $whatWentBang = $!;
            message ("system call failed:",'stop',"@args: $whatWentBang");
            $globalErrorMessages .= "system @args failed: $whatWentBang\n";
            $globalErrorCount++;
        }
	} else {
		print "Not applying ID3 tags\n" if $verbose;
	}
	print $OUT "Done creating podcast\n" if ($verbose);
}

sub uploadPodcast {
	my $srcFilePath = shift;
	my $ftpHost = "nruc.org.au";
	my $ftpPath = "/httpdocs/podcast/";
	my $ftpLogin = "nruc";
	my $ftpPassword = "church123";
	
	my $srcFileName = basename($srcFilePath);
	
	print $OUT "Uploading podcast ",$srcFileName,"\n";

	my @args = ("ftp", "-v", "-u");
	push @args, "ftp://" . $ftpLogin . ":" . $ftpPassword . "\@" . $ftpHost . $ftpPath . $srcFileName, $srcFilePath;
	
	print $OUT "Running ", join (":",@args), "\n";
	dumpCommand("$projectDirectory/upload.bash",@args);
    if(system(@args) != 0) {
        my $whatWentBang = $!;
        message ("File upload failed \($whatWentBang\) - skipping\n",'caution',"Re-run with --upload option to try again");
        $globalErrorMessages .= "File upload failed \($whatWentBang\)";
        $globalErrorCount++;
        return;
    }
#
#	system(@args) == 0 or (message("File upload failed \($!\) - skipping\n",'caution',"Re-run with --upload option to try again") && return);
	
	message("Done uploading podcast\n",'network',"You will have to manually create sermon through wp-admin") if($verbose);
}

# Do the magic to figure out where the project will be and what it is called based on provided name and/or path
sub processProjectArg {
    my $given = shift;
	$given =~ s/\/$//; # Get parameter and remove trailing slashes (/) if any
	if ($given =~ /\.aup$/i) {
		# It's an aup file, extract the directory it's in and use that as the $projectDirectory
		$projectFilePath = $given;
		($projectName,$projectDirectory,) = fileparse($projectFilePath,".aup");
		$projectDirectory =~ s!/$!!;
		print $OUT "projectDirectory: $projectDirectory\n" if($debug>1);
		$projectFilename = fileparse($projectName);
		print $OUT "full path to project file given: $projectFilename\n" if($debug);
	} else { # no .aup extension, must be a directory
		if($given =~ m!^\.*/!) { # if given starts with / or ./ then leave path as-is otherwise prepend base dir.
			$projectDirectory = $given;
        } else {
			$projectDirectory = "$baseDirectory/$recordingsDirectoryName/$given";
		}
		$projectFilename = basename($projectDirectory) . ".aup";
		print $OUT "got project base name from directory: $projectFilename\n" if ($debug);
	}
	# Find a date in the file/path name if available and override $dateString if it is
	if($projectFilename =~ /((\d{4})-(\d{2})-(\d{2}))/) {
		print $OUT "Matched date in $projectFilename\n" if($debug>1);
		$dateString = $1;
	}
    $projectName = fileparse($projectFilename, ".aup");
}
##############################
# main Program Start
##############################

# Save options starting with '-' in @ARGV for possible later exec call
my @NEW_ARGV;
foreach (@ARGV){
	push @NEW_ARGV,$_ if m/^-/;
}

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
	'print-cd-inserts!' => \$printCdInserts,
	'podcastid3!' => \$podcastid3,
	'updatetags!' => \$updatetags,
	'upload!' => \$upload,
	'gui!' => \$gui,
	'verbose!' => \$verbose,
	'options-prompt!' => \$optionsPrompt,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Load any config from ini file
loadConfig;

# Check we have the full kit
#exit unless dependenciesArePresent;

# Now confirm user selected options via the gui
exit unless promptUserForOptions == 1;

# Use projectDate if provided on command line
$dateString = $projectDate if(defined $projectDate);

# Grab remaining project file name if provided
# path information is used from this to set base directory for other files for this project
# Expect full path of directory aup file is in or aup file itself
if ($#ARGV >= 0) {
    processProjectArg(shift);
} else { # Nothing given on command line - create project and directory names
    $projectName = "$dateString" . "$audacityProjectSuffix";
    $projectFilename = "$projectName\.aup";
	$projectDirectory = "$baseDirectory/$recordingsDirectoryName/$projectName";
	print $OUT ("projectDirectory: $projectDirectory\n") if($debug>1);
	($button,$selection) = promptUserRadio("Choose option:","OK","Quit","\"Use $projectFilename\"","\"Browse for another project\"","\"Enter project name\"");
	exit if($button == 2);
	if($selection){
		my $rv = promptUserAup("Browse for an existing project file","$baseDirectory/$recordingsDirectoryName") if($selection == 1);
		$rv = promptUser("Enter a project name","$projectName") if($selection == 2);
		chomp($rv);
#		print $OUT "going to exec with $0 @NEW_ARGV $rv\n" if($debug);
#		exec "$0",@NEW_ARGV,"$rv";
#		exit;
        processProjectArg($rv);
	}
}
$projectFilePath = "$projectDirectory/$projectFilename";
$projectDataDirectory = "$projectDirectory/$projectName$audacityProjectDataDirectorySuffix";

# Setup directories constructed from projectName
setupPaths $projectDirectory;

print "projectDate: $projectDate\n" if ($debug and defined $projectDate);
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
if(($audacity == 1) ||
   ($mp3 == 1) ||
   ($burn == 1) ||
   ($podcast == 1) ||
   ($cdInserts == 1) ||
   ($fixLabels == 1) ||
   ($upload == 1) ||
   ($printCdInserts == 1) ||
   ($podcastid3 == 1) )
{
	print $OUT "Found execute-only option, turning off on-by-default options\n" if $debug;
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

#######################
# Begin the real work #
#######################

# Run Audacity to capture recording
runAudacity if $audacity;

## Open today's aup file
while(checkTracks($projectFilePath)) {
   print "Missing wav files or incorrect label lengths.\n";
   my $r = promptUserOKCan ("Re-run Audacity to re-export wav files?","Re-run", "Skip");
   if($r == 1) {runAudacity;}
   if($r == 2) {message("Nothing to process - exiting\n",'stop',"I need audio tracks to do something with..."); exit;}
}

# Get user's selection for tracks to burn to CD
if ($cdInserts || $burn){
    my $button;
    ($button,@burnSelectedTracks) = selectTracks(($burn?"burning to CD":"") . (($cdInserts and $burn)?" and ":"") . ($cdInserts?"jewelcase inserts.":"."),".*");
    print("button returned from selectTracks: $button\n") if($debug >1);
    # Pike out if user wasn't sure.
    exit if($button ne 1);
}

# Get user's selection for tracks to include in podcast
my $sermonRegex = $sermonRegexDefault;
if ($podcast) {
    my $button;
	($button,@podcastSelectedTracks) = selectTracks("sermon podcast.",$sermonRegex);
    (print $OUT "Quitting from select podcast tracks\n" && exit) if($button ne 1);
}

# Everything is now known and the remainder runs unattended.
# Prompt user to turn printer on (if print selected) and insert writable CDs (if burn selected)
my $messageText;
$messageText .= "Insert one or more writable CDs in the drive(s)\n" if $burn;
$messageText .= "Check the printer is turned on\n" if $printCdInserts;
$messageText .= "When ready, click 'OK' and go get a cup of coffee.\n";
longMessage ("Ready to go","$messageText");

# Create individual mp3 files from wav files
makeMp3s if($mp3);

# Burn CDs
# First get selected tracks to burn
if ($cdInserts || $burn){
#    my $button;
#    ($button,@selectedTracks) = selectTracks(($burn?"burning to CD":"") . (($cdInserts and $burn)?" and ":"") . ($cdInserts?"jewelcase inserts.":"."),".*");
#    print("button returned from selectTracks: $button\n") if($debug >1);
#    # Pike out if user wasn't sure.
#    exit if($button ne 1);
    # Now we have tracks selected for burning to CD, look for media and try to burn.
    if($burn) {
        my @blanks = checkBlankMedia;
        while($#blanks < 0 &&
            # No burnable disks found ask what to do
           promptUserOKCan ("No blank, writable CDs found\nTry again or Skip burning?","Try Again","Skip") == 1) {
            @blanks = checkBlankMedia;
        }
        if ($debug) {
            my $plural = $#blanks > 0?'s ':' ';
            print "Available blank, writable CD".$plural."in drive".$plural;
            print join(' and ',@blanks)."\n";
        }
        # Burn tracks to each available writable media
        foreach my $drive (@blanks) {
            BurnCD($drive, @burnSelectedTracks);
        }
    } else {
        print "Not burning CDs\n" if($verbose);
    }
}
# Assume CD labels are only wanted when CDs are burned
createCdInserts(@burnSelectedTracks) if $cdInserts;
printCdInserts() if ($printCdInserts and $cdInserts);

# Create podcast file and FTP to web server.
#my $sermonRegex = $sermonRegexDefault;
if ($podcast) {
#    my $button;
#	($button,@selectedTracks) = selectTracks("sermon podcast.",$sermonRegex);
#    (print $OUT "Quitting from select podcast tracks\n" && exit) if($button ne 1);
	createPodcast(@podcastSelectedTracks);
} else { 
	print $OUT "Not creating podcast\n" if($verbose);
}

# Upload podcast unless noupload or podcastFilePath doesn't exist
if($upload) { # same as --ftp option
	if(-r $podcastFilePath) {
		uploadPodcast($podcastFilePath);
	} else {
		message("Can't upload: podcast MP3 file not found",'stop',"$podcastFilePath");
	}
} else {
	print "Not uploading podcast\n" if($verbose);
}

longMessage("Finished with $globalErrorCount errors\n","$globalErrorMessages");
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
   --[no]cd-inserts     [don't] create CD label files (for printing later)
   --[no]upload         [don't] FTP mp3 podcast to webserver
   --[no]ftp            [don't] Same as --upload
   --[no]podcast        [don't] create podcast file
   --[no]print-cd-inserts  [don't] send CD Inserts to the printer
   --[no]podcastid3     [don't] apply ID3 tags to podcast file

   --debug 				Turns on debugging. Can be specified mutiple times
                        to increase verbosity.
   --[no]verbose		Turns on commenting on what's going on.
   --fix-labels        Repair labels in aup file so that no non-zero time labels 
   						are present (prevents incomplete tracks from being created)
   --interactive       Asks all option questions interactively (not yet operational)
   --updatetags        Requests confirmation of all tags in aup project file.
                       This is also what happens when a new file is created.
   --options-prompt		Prompt for options in gui
	
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
