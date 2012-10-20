#!/usr/bin/perl -Tw
#-----------------------------------------------------------------------------
# cdinsert.pl
#
# Web interface to "cdlabelgen"
# Creates CD Jewel Case Inserts, files output in PostScript and PDF formats.
# This script is similar to the script used for the Online Interface at:
# http://www.aczoom.com/tools/cdinsert/
# and is provided as an example. There is no documention for this script,
# other than program comments in this file itself.
# See the "INSTALL.WEB" file for HTML fragments of files used by the
# script (wait_t, done_t, and the main form itself), and crontab entries.
# -----------------------------------------------------------------------
my $VERSION = "3.21";
# Last Major Modification: October 21, 2004
# Changed aczone to aczoom
# Updates by Avinash Chopde <avinash@acm.org> http://www.aczoom.com/
# Updated: Aug 2007: added support for barcodegen using --tray-overlay
# Updated: Oct 2008: added support for double width DVDs --double-case
# Updated: Dec 2008: add -sPAPERSIZE to ps2pdf also, for correct A4 size
# Updated: Nov 2009: add nocoverheading option
# -----------------------------------------------------------------------
# Created: March 2001, by Avinash Chopde <avinash@acm.org>  www.aczoom.com
# -----------------------------------------------------------------------
# Copyright (C) 2002 Avinash Chopde <avinash@acm.org> http://www.aczoom.com/
#
# All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, and/or sell copies of the Software, and to permit persons
# to whom the Software is furnished to do so, provided that the above
# copyright notice(s) and this permission notice appear in all copies of
# the Software and that both the above copyright notice(s) and this
# permission notice appear in supporting documentation.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
# OF THIRD PARTY RIGHTS. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# HOLDERS INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL
# INDIRECT OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING
# FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
# NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
# WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# Except as contained in this notice, the name of a copyright holder
# shall not be used in advertising or otherwise to promote the sale, use
# or other dealings in this Software without prior written authorization
# of the copyright holder.
# ========================================================================
# March 2001, Avinash Chopde <avinash@acm.org> http://www.aczoom.com/
#------------------------------
# Rough outline of things needed to make this work at your site:
# Programs needed, on Linux:
# sudo apt-get install netpbm
# GhostScript - use version 5.10 - it is twice as fast as version 6.5
# cdlabelgen - install (default goes in /usr/local/bin and /usr/local/lib)
# netpbm - using version 9.22 (Dec 2001)
# jpeg2ps - using version 1.8, from http://www.pdflib.com/jpeg2ps/
# CGI.pm - latest one - 2.752 or newer
# jpegtran: sudo apt-get install libjpeg-progs 
# sudo cpan -i HTML::FillInForm
# ----
# barcodegen - on Ubuntu 9.04, this works:
# sudo apt-get install imagemagick
# sudo apt-get install libgd-tools
# sudo apt-get install libgd2-xpm-dev
# sudo apt-get install perlmagick
# sudo cpan -i GD::Barcode::Image
# Note that there is bug https://rt.cpan.org/Ticket/Display.html?id=20297
# that has not been fixed in long time. It will cause QRCode generation to
# be unable to auto-select version, so a lot of input will fail.
# Fix it locally by changing to this in QRCode.pm init, make it 0 not 1:
# $oSelf->{Version} = $rhPrm->{Version} || 0;  # now auto-select works
# Use "locate QRcode.pm" to find it on your machine.
# ----
# Make this folder non-writeable:
# $ROOTDIR 
# Safest is to make all files and directories non-writeable,
# and all directories below $ROOTDIR should be additionally non-readable
# by group and others (ROOTDIR itself needs to be readable, Apache reads
# it to find index.html, index.shtml, etc).
# commands: chmod -R a-w $ROOTDIR; chmod go-r <all subdirectories>
#
# Files/folders in $ROOTDIR:
#   cdinsert.html [entry point, INSTALL.WEB has examples]
#   $INITIAL_TEMPLATE, $FORM_TEMPLATE, $WORKING_TEMPLATE, $DONE_TEMPLATE
#   cdinsert.pl (copy to http:/cgi-bin)
# Files/folders in any PATH dir:
#   cdlabelgen
# ----
#   $WORKDIR --> Make the PARENT of this folder writeable by everybody
#   (but not readable).  This is where the temp files are created.
# ---
#   $LOGFILE - make this chmod 662 - writeable, but not readable by others
#   so casual web hackers can't read this directly using a browser.
#   But if the file has to be owned by nobody.nobody (for web server),
#   then make it chmod 226 instead
# ---
# Finally, edit the top section of this CGI script to point to files at
# your site.
# To test, run with the -t option, using the example webtest.txt or similar
# files:
# cdinsert.pl -t /tmp/webtest.txt
# -t <filename> should use full path for filename.
#-----------------------------------------------------------------------------
use 5.005; # perl newer than 5.005 required
#-----------------------------------------------------------------------------
use CGI 3.21 qw(escapeHTML); # 2.47 for upload, 2.50 for Vars, 3.21 for POST_MAX fix
$CGI::POST_MAX=1024 * 800;  # max size posts accepted, bytes
#-----------------------------------------------------------------------------

use CGI::Carp qw(fatalsToBrowser);
use Getopt::Std;
use POSIX qw(floor);
use File::Copy;
use Socket qw(:DEFAULT :crlf);
use HTML::Template;
use HTML::FillInForm;

$start_time = time();
$datestr = localtime($start_time);
#-----------------------------------------------------------------------------
$LOGFILE = "/home/cgi/tmp/weblog.txt";
# log file - global script issues, not related to any one invocation
# make sure this file exists, and is chmod 662 - writeable, but not readable
# by others so casual web hackers can't read this directly using a browser.
# Note that the PDF file generated is around 4 times image sizes!

open(LOGFILE, ">> $LOGFILE")  
  or myexit("Could not open log file ($LOGFILE): $!");
select((select(LOGFILE), $| = 1)[0]); # autoflush

# all STDERR output is caught in local log file, so any perl errors
# or uncaught STDERR from commands goes here, instead of the global
# apache log file
open (STDERR, '>>& LOGFILE')
  or myexit("Could not redirect STDERR to log file ($LOGFILE): $!");

print LOGFILE "cdinsert [$datestr] $ENV{REMOTE_ADDR} - before new CGI - $ENV{REQUEST_METHOD}\n";

$ENV{'PATH'}="/bin:/usr/bin:/usr/local/bin:/usr/local/netpbm/bin:/home/cgi/bin"; # security blanket (make sure all folders/files are non-writeable by others!)

# Following vars need to be set specifically for each site 
$ROOTDIR = "/home/cgi/cdinsert"; # where all web files are kept

# "/usr/local/apache/htdocs/cgi" is symlink to "/home/cgi", so
# the HTTP address is:
# $ROOTHTTP = "/cgi/cdinsert"; # relative URL, absolute path

# for each invocation - semi-random name for files - gets some privacy, since
# these folders and files are readable by the world.
$WORKID = floor(rand(1e4)); 
$WORKFILE = "cd" . $WORKID; # 'cd' followed by upto 4 digits
$MSGFILENAME = "log$WORKID.txt";
$SAVINPUT="inp$WORKID.txt"; # exact copy of form input string, saved for user
$WEBDONE_HTML = "done$WORKID.html"; # complete HTML file (created in $WORKDIR)
$SAVEFORM = "form" . $WORKID; # save form data here

# .tmpl files are HTML::Template files - all in $ROOTDIR
$INITIAL_TEMPLATE="initial.tmpl"; # first page, diplayed with form

$FORM_TEMPLATE="form.tmpl"; # just the form
$FORM_ACTION="/cgi-bin/cdinsert.pl"; # FORM ACTION="..." filled in with this

$WORKING_TEMPLATE="working.tmpl"; # "working..." display template - this is
# the HTML output of this script  to stdout, while it is doing the processing

$DONE_TEMPLATE="done.tmpl"; # Template page with form (includes form.tmpl)

# --- MRKR_* strings found in input HTML template files,
# to be replaced with job-specific values. See sub replace_markers()
# for list of all the marker tags - only non-HTML::Template tags is
# SHOWSTATUS_HERE
$SHOWSTATUS_HERE = "SHOWSTATUS_HERE\n"; # split WORKING_TEMPLATE on this line

#--- tag printed in the HTML file, denotes start and end of user entered text
# --------------
$DEBUG = 0; # 0 no debug messages, 1 some messages, 2 more.
# Debug messages may go to Apache error_log at the beginning, but
# once the LOGFILE/MSGFILE is created, they will go there.

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};   # Make %ENV safer

$sent_working_header = 0;

#-----------------------------------------------------------------------------
# initialize 

$status_count = -2;
$dontredirect = 0; # change to 1 to prevent auto redirect in WORKING_TEMPLATE
$time_taken = 0;
$time_taken_units = $time_taken;
$errflag = 0;
$errcmd = "";
$hostname = "";
$hostaddr = "";
$form_html = ""; # filled in form, displayed on results page

select((select(STDOUT), $| = 1)[0]); # autoflush

$query = new CGI;
# above line prints warning: Use of uninitialized value in substitution (s///) at (eval 8) line 23. But webitrans.pl does not get this error... strange
# started after updated perl with yum, and CGI.pm with CPAN to 3.35

# output HTML page headers, rest of HTML is output by copying WORKING_TEMPLATE
print CGI::header(-charset => "ISO-8859-1");

getopts('t:'); # -t <filename> is test mode. Filename is used as $incontents

# --------------------------------
# check if we need to do any work
$cgierror = $query->cgi_error(); # post too big, or user hit STOP, etc...

$form_tmpl = HTML::Template->new(filename => $FORM_TEMPLATE,
                                 path => [$ROOTDIR]);
$form_tmpl->param(MRKR_FORM_ACTION => $FORM_ACTION);
$form_html = $form_tmpl->output();


# if called without any form data (or -t test option), then just display
# a page with the form and exit
unless ($cgierror || $opt_t || $query->param()) {
  my $tmpl = HTML::Template->new(filename => $INITIAL_TEMPLATE, path => [$ROOTDIR]);
  $tmpl->param(MRKR_FORM_HTML => $form_html);
  print $tmpl->output();
  exit(0);
}

#-----------------------------------------------------------------------------
# start work, create work directory, etc

$SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{PIPE} = $SIG{TERM} = \&sighandler;

# for each invocation - semi-random name - gets some privacy, since
# these folders are readable by the world.
# $WORKDIRNAME = "cd" . floor(rand(100)) . "$$"; # keep it max 4 chars + $$
# $TDATE = sprintf("%02d%02d%02d", (localtime($start_time))[3], (localtime($start_time))[2], (localtime($start_time))[1]); # current date hour minute
$TDATE = sprintf("%02d%02d", (localtime($start_time))[3], (localtime($start_time))[2]); # current date hour
$WORKDIRNAME = "cd" . $TDATE;
$WORKDIRNAME = &mktempdir("/home/cgi/tmp", $WORKDIRNAME, floor(rand(1e3))); # 1e3 -> max 3 digits
$WORKDIR = "/home/cgi/tmp/$WORKDIRNAME"; 
# "/usr/local/apache/htdocs/cgi" is symlink to "/home/cgi", so
$WORKHTTP = "/cgi/tmp/$WORKDIRNAME"; 
$MSGFILE = "$WORKDIR/$MSGFILENAME";
# STDOUT/STDERR messages collected here, different file for each invocation

# following may be left alone, in most cases
$ENV{'SHELL'} = "/bin/sh";
$ENV{'TMPDIR'} = $WORKDIR;
$ENV{'TEMP'} = $WORKDIR;
$ENV{'TZ'} = "EST5EDT";

#--- executables - since am setting PATH, no need to give full path for each

$REDIRECT="< /dev/null 2>&1";

# -- cmd 1:
$CDLBL_E = "cdlabelgen $REDIRECT";
# -- cmd 2:
$PS2PDF_E = "ps2pdf -sPAPERSIZE=letter $WORKFILE.ps $REDIRECT";
# -- cmd 3:
$PS2PGM_E = "gs -q -dNOPAUSE -dBATCH -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -r72 -sDEVICE=pgmraw -sPAPERSIZE=letter -sOutputFile=$WORKFILE.pgm -f $WORKFILE.ps $REDIRECT";
# gs options:
#   - made it anti-alias text and graphics (TextAlphaBits and Graphics...)
#   - pgm (gray scale) is faster and 66% smaller file than ppm (full color)
#     pgmraw is even more smaller, and is 10 times faster too, for large files!
# -- cmd 4:
$PGM2GIF_E = "(pnmcrop $WORKFILE.pgm | ppmtogif -interlace) 2>&1 > $WORKFILE.gif";
#color gif? (do jpeg instead?): $PGM2GIF_E = "(pnmcrop $WORKFILE.ppm | ppmquant 256 | ppmtogif -interlace) 2>&1 > $WORKFILE.gif";
# -- cmd 5:
$CIMAGEFILE = "cvr$WORKID";
$TIMAGEFILE = "tra$WORKID";
$C_JPG2EPS_E = "jpeg2ps -r 72 -o $CIMAGEFILE.eps $CIMAGEFILE.jpg 2>&1";
$T_JPG2EPS_E = "jpeg2ps -r 72 -o $TIMAGEFILE.eps $TIMAGEFILE.jpg 2>&1";
# -- cmd 6:
# PostScript cannot handle Progressive JPEG's, so have to run
# jpegtran on every input JPG file to convert it to baseline JPEG
$C_JPGTRAN_E = "jpegtran $CIMAGEFILE.jpg 2>&1 > $CIMAGEFILE.tmp && mv $CIMAGEFILE.tmp $CIMAGEFILE.jpg ";
$T_JPGTRAN_E = "jpegtran $TIMAGEFILE.jpg 2>&1 > $TIMAGEFILE.tmp && mv $TIMAGEFILE.tmp $TIMAGEFILE.jpg ";
# optional: if barcode generation has to be performed - requires
# barcodegen - from GD::Barcode::Image to be available
$BCODEFILE = "bcode$WORKID";
$BCODE_E = "barcodegen --format=EPS --border=7 --write=$BCODEFILE.eps $REDIRECT";
$CDL_BCODE_ARGS="--tray-overlay $BCODEFILE.eps --tray-overlay-scaleratio=1,-0.1,0.1";

#-----------------------------------------------------------------------------
umask(0);
chdir $WORKDIR or myexit("cd ($WORKDIR) failed: $!");
open(MSGFILE, ">> $MSGFILE")  
  or myexit("Could not open message file ($MSGFILE): $!");
select((select(MSGFILE), $| = 1)[0]); # autoflush
open(WEBDONE_HTML, "> $WORKDIR/$WEBDONE_HTML")
  or myexit("Could not open WEBDONE_HTML file ($ROOTDIR/$WEBDONE_HTML): $!");

open(SAVEFORM, ">> $SAVEFORM")  
  or myexit("Could not open SAVEFORM file ($SAVEFORM): $!");

open(WORKING_TEMPLATE, "< $ROOTDIR/$WORKING_TEMPLATE")
  or myexit("Could not open WORKING_TEMPLATE file ($WORKING_TEMPLATE): $!");

print MSGFILE "[$datestr] [pid $$]: Starting job in directory $WORKDIRNAME\n";

# ----------------
# send WORKING_TEMPLATE header before reading any input...
# start_html etc is not used - instead, a template HTML file is read
# in and output to STDOUT
read(WORKING_TEMPLATE, $working_all_lines, $CGI::POST_MAX)
	    or myexit("Could not read WORKING_TEMPLATE file ($WORKING_TEMPLATE): $!");
($working_header, $working_trailer) = split(/$SHOWSTATUS_HERE/, $working_all_lines, 2);

$working_header_tmpl = HTML::Template->new(scalarref => \$working_header,
             path => [$ROOTDIR], die_on_bad_params => 0);

&replace_markers($working_header_tmpl);

# sent to client browser - half - the HTML page - after this, we will
# print one line at a time, using show_status, for each command as it is
# executed
$working_header_tmpl->output(print_to => *STDOUT);
$sent_working_header = 1;

print &show_status("");

# ----------------
# allocate WORKING_TEMPLATE trailer after the header, as soon as possible,
# in case of any calls to myexit(), so that trailer can be displayed
if (!defined $working_trailer) {
  myexit("Internal error - $WORKING_TEMPLATE missing SHOWSTATUS_HERE marker.");
}
$working_trailer_tmpl = HTML::Template->new(scalarref => \$working_trailer,
             path => [$ROOTDIR], die_on_bad_params => 0);

#----------------------------------------------------------------
# collect user input

if (! $opt_t ) {
    # in some cases, I've seen these variables come in as "undefined",
    # so to suppress perl -w warnings, using the || '' construct below
    $hostname = $query->remote_host() || '';
    $hostaddr = $query->remote_addr() || '';
    $useragent = $query->user_agent() || 'CGI query - no useragent';
    $referer = $query->referer() || '';
    $intitle = $query->param('title') || '';
    $insubtitle = $query->param('subtitle') || '';
    $inclogo = $query->param('clogo') || '';
    $intlogo = $query->param('tlogo') || '';
    $incimage = $query->param('cimage') || '';
    $intimage = $query->param('timage') || '';
    $incimagefile = $query->upload('cimagefile') || ''; # get file handle
    $intimagefile = $query->upload('timagefile') || ''; # get file handle
    $incontents = $query->param('contents') || '';
    $incontents =~ s/$CR?$LF/\n/g; # fix all CR/LF chars
    $incdcase = $query->param('cdcase') || 'normal';
    $innotrayhd = $query->param('notrayheading') || '';
    $innocoverhd = $query->param('nocoverheading') || '';
    $inscaleitems = $query->param('scaleitems') || '';
    $inmakegif = $query->param('makegif') || '';
    $ina4paper = $query->param('a4paper') || '';
    $insplititems = $query->param('splititems') || '';
    $infilename = $query->param('filename') || '';
    $infile= $query->upload('filename') || ''; # get file handle
    $inbcodetype = $query->param('bcodetype') || '';
    $inbcodetext = $query->param('bcodetext') || '';
} else {
    $hostname = qq(testing mode "-t $opt_t");
    $hostaddr = '';
    $useragent = 'testing -t, no useragent';
    $referer = '';
    $infilename = '';
    $infile = undef;
    $intitle = "Testing Title";
    $insubtitle = "Testing Subtitle";
    $incimage = 'mp3.eps';
    $intimage = 'cdda.eps';
    $incimagefile = '';
    $intimagefile = '';
    $incdcase = 'normal';
    $innotrayhd = 0;
    $innocoverhd = 0;
    $inscaleitems = 0;
    $inmakegif = 1;
    $insplititems = 0;
    $ina4paper = 0;
    $inclogo = 1;
    $intlogo = 0;
    $inbcodetype = '';
    $inbcodetext = '';
    open(INPUT, "$opt_t")
      or myexit("Could not open input file (-t $opt_t) [Make sure full path given -t /tmp/x.txt etc]: $!");
    print MSGFILE "opened input file $opt_t\n" if ($DEBUG >= 1);
    while (<INPUT>) {
	# read each line to get correct EOLN value for this platform (works?)
	s/$CR?$LF/\n/; # variables from Socket package
        $incontents .= $_; 
    }
    close INPUT;
}

$datestr = localtime($start_time);
print LOGFILE "$WORKDIRNAME cdinsert [$datestr] $hostname - started\n";

#----------------------------------------------------------------

print MSGFILE "[$datestr] checking cgi_error...\n";

if ($cgierror) {
    if ($cgierror =~ /413/) {
	myexit("Uploaded image files too large?<br/> Received too much data - got <b>" . int($ENV{'CONTENT_LENGTH'}/1024) . "</b> KBytes, can only receive maximum of <b>" . int($CGI::POST_MAX/1024) . "</b> KBytes.");
    } else {
	myexit($cgierror);
    }
}

# have now read in all files user may have uploaded, beginning processing
$start_processing_time = time();

$datestr = localtime(time());
print MSGFILE "----------------------------------------------------\n";
print MSGFILE "[$datestr] Got these values from the form:\n";
my %params = $query->Vars;
while (($key, $value) = each %params) {
    # assuming value is single string - if multi-valued, need
    # to split on \0 to get array of values...
    $value = "<see file $SAVINPUT>" if ( $key =~ /^contents$/ );
    print MSGFILE "  $key = '$value'\n";
}
print MSGFILE "Some environment vars:\n";
# print MSGFILE "  remote_host = '$hostname'\n";
print MSGFILE "  user_agent = '$useragent'\n";
print MSGFILE "  referer = '$referer'\n";
print MSGFILE "----------------------------------------------------\n";

$gotstring = ($incontents =~ /\S+/);
$gotfile = ($infilename =~ /\S+/);
$null_in_contents = -1;

if ($gotfile) { # ignore $gotstring, file takes precedence
    if ($gotstring) {
	print MSGFILE "** Warning: user entered text as well as filename, will append file to entered text.\n";
    }
    # even when user types in non-existent file name, there is
    # no error here, get an empty file. Should warn that
    # file typed in upload field is empty
    if (eof($infile)) {
        myexit("Invalid upload file '$infilename' - no such file?");
    }
    while (<$infile>) {
	s/$CR?$LF/\n/; # correct end-of-line (variables from Socket package)
        $incontents .= $_; 
    }
    print MSGFILE "... read in uploaded file: $infilename\n";

    # if the file is not text, but binary, reject it, stop script later..
    # (stop later because file is saved before exiting, so we can debug)
    # simple binary check - look for NULL character. Note that Unicode
    # input text will have this null character in it - even if text is
    # all just ASCII and user saves as Unicode....
    $null_in_contents = index($incontents, "\000") + 1;

    if (length($incontents) <= 0) {
        myexit("Empty uploaded file '$infilename' - no data.");
    }
}

# save users string before possible processing/changing, for debug.
open(OUTPUT, "> raw$SAVINPUT")
  or myexit("Could not open output file to save form input (raw$SAVINPUT): $!");
print OUTPUT  $incontents;
close OUTPUT;

# some people post binary files here, and ghostscript gs hangs on
# such text, so have to remove invalid characters
# don't really know a sure-fire way of detecting binary files or
# deleting all non-printable chars (ISO-Latin1, ASCII, etc??)
# so, doing something that is probably good enough in most cases
# this is just more protection - there may be code above to return
# errors if a non-text file is uploaded for the list of items.

@items = split(/\n/, $incontents);
$num_items = $#items + 1;
$incontents = "";
for (@items) {

    # remove all control chars, and all nulls
    s/[[:cntrl:]\000]//g;
    # restrict each line to max 256 characters
    # no - don't mangle input, even if long lines
    # $_ = substr($_, 0, 256);

    $incontents .= $_; 
    $incontents .= "\n";  # add back the end-of-line char
}
@items = (); # not needed anymore

$datestr = localtime(time());

print MSGFILE "[$datestr]: writing input to $SAVINPUT\n";

# save users string, to pass to exe, and in case users need to use it again
open(OUTPUT, "> $SAVINPUT")
  or myexit("Could not open output file to save form input ($SAVINPUT): $!");
print OUTPUT  $incontents;
close OUTPUT;

print MSGFILE "--> input text copied to $SAVINPUT.\n" if ($DEBUG >= 1);

# save form data
$query->save(\*SAVEFORM);

# now exit if file was bad - NULLs in it, etc.
if ($null_in_contents > 0) {
	myexit("'$infilename' - not ASCII or Latin1 text. Found null character in input ($null_in_contents).");
}
# ----------------------------------------------------------------------

# untaint variables...
$incimage =~ /([\d\w\-\.]*)/; # no / allowed in name
$incimage = $1;
$intimage =~ /([\d\w\-\.]*)/; # no / allowed in name
$intimage = $1;
$insplititems =~ /([\d\w\-\.]*)/; # no / allowed in name
$insplititems = $1;
$ina4paper =~ /([\d\w\-\.]*)/; # no / allowed in name
$ina4paper = $1;
$inbcodetype =~ /([\d\w\-\.]*)/; # no / allowed in name
$inbcodetype = $1;

# not really passing these as args, but perl -T complains, so clean them...
$incdcase =~ /([\d\w\-\.]*)/; # no / allowed in name
$incdcase = $1;
$innotrayhd =~ /([\d\w\-\.]*)/; # no / allowed in name
$innotrayhd = $1;
$innocoverhd =~ /([\d\w\-\.]*)/; # no / allowed in name
$innocoverhd = $1;
$inscaleitems =~ /([\d\w\-\.]*)/; # no / allowed in name

# Title and Subtitle should use entire string as entered by user
# but - do escape any non-alphanumeric character, this should take
# care of shell metacharacters such as " $ etc
# Don't quote the title or subtitle:
# single quotes are a problem since another \' inside the string gets ignored.
# double quotes are a problem since most \ 's are preserved \) remains \)
# s/([`"\$\\])/\\$1/g;   # use this if enclosing title in double quotes "
# s/(\W)/\\$1/g;   # use this if NOT enclosing title in any quotes " or ',
#     is safest since every non-alpha-numeric character is escaped.
$intitle =~ /(.*)/; # yes, really need this.
$intitle = $1;
$intitle =~ s/(\W)/\\$1/g;
$insubtitle =~ /(.*)/; # yes, really need this.
$insubtitle = $1;
$insubtitle =~ s/(\W)/\\$1/g;
$inbcodetext =~ /(.*)/; # yes, really need this.
$inbcodetext = $1;
$inbcodetext =~ s/(\W)/\\$1/g;

print MSGFILE "after untaint: title($intitle) subtitle($insubtitle) clogo($inclogo) tlogo($intlogo)\n"
  if ($DEBUG >= 1);

# read in any uploaded images - cover image

$datestr = localtime(time());
print MSGFILE "[$datestr]: reading in any uploaded JPG files\n";

if ($incimagefile) {
    if ($incimage) {
	print MSGFILE "** Warning: user selected built-in Cover Image and uploaded Image, ignoring built-in.\n";
    }
    $incimage = "";

    copy($incimagefile, "$CIMAGEFILE.jpg")
      or myexit("Could not copy uploaded file ($incimagefile) ($CIMAGEFILE.jpg): $!");
    close($incimagefile);

    &do_cmd($C_JPGTRAN_E) || &do_cmd($C_JPG2EPS_E);
    $dontredirect = "1" if ($errflag); # above command failed
    $incimage = $errflag ? "": "$CIMAGEFILE.eps";
}
# read in any uploaded images - tray image
if ($intimagefile) {
    if ($intimage) {
	print MSGFILE "** Warning: user selected built-in Tray Image and uploaded Image, ignoring built-in.\n";
    }
    $intimage = "";

    copy($intimagefile, "$TIMAGEFILE.jpg")
      or myexit("Could not copy uploaded file ($intimagefile) ($TIMAGEFILE.jpg): $!");
    close($intimagefile);

    &do_cmd($T_JPGTRAN_E) || &do_cmd($T_JPG2EPS_E);
    $dontredirect = "1" if ($errflag); # above command failed
    $intimage = $errflag ? "" : "$TIMAGEFILE.eps" ;
}

# compute -S and -T scale factors.
# use the special value "0.0" if image is to be printed as background,
# otherwise use no scaling (1.0 scale factor).
$clogoscale = ($inclogo) ? "1.0" : "0.0";
# $tlogoscale = ($intlogo) ? "1.0" : "0.0"; # 0.0 == fill1 - interior only
if ($incdcase =~ /^normal/) {
  $tlogoscale = ($intlogo) ? "1.0" : "fill2"; # fill2: fill endcaps too
} else {
  $tlogoscale = ($intlogo) ? "1.0" : "fill1"; # fill1: just fill tray
}

# ---- compute page offset for A4 and gs command modifications
if ($ina4paper) {
  $PS2PGM_E =~ s/PAPERSIZE=letter/PAPERSIZE=a4/;
  $PS2PDF_E =~ s/PAPERSIZE=letter/PAPERSIZE=a4/;
  $ina4paper = "-y 1.5"; # default
  $ina4paper = "-y 0.8" if ($incdcase =~ /^(dvd)|(envelope)|(double)/);
}
#-----------------------------------------------------------------------------
# check if barcode generation has to be performed - this requires
# barcodegen - from GD::Barcode::Image to be available
if ($inbcodetype && $inbcodetext && !$errflag) {
    $datestr = localtime(time());
    print MSGFILE "[$datestr]: create barcode\n";
    $BCODE_E .= " --type '$inbcodetype' $inbcodetext";
    &do_cmd($BCODE_E);
    if ($errflag) {
	$dontredirect = "1"; # barcodegen failed, don't redirect

	# this command is not important so reset error state,
	# to allow other commands to proceed
	$errflag--;
    }
}
#-----------------------------------------------------------------------------

$datestr = localtime(time());
print MSGFILE "[$datestr] $hostname :: Starting programs...\n";
print MSGFILE "----------------------------------------------------\n";

# Jan02: accept empty input, most common error, so better to accept it
# ($gotstring || $gotfile || $intitle || $insubtitle || $incimage || $intimage)
#     or myexit("Nothing to do - empty input - no fields entered!");

# 1: run cdlabelgen to create .ps file
$cmd = $CDLBL_E;

# preparing a push, in case I need to use system()
@cmdargs = ();
push(@cmdargs, "-c $intitle") if ($intitle); # no quotes around title...
# don't use single quotes, embedded \' causes problems in title/subtitle
push(@cmdargs, "-s $insubtitle") if ($insubtitle); # no quotes around title...
push(@cmdargs, "-e '$incimage'") if ($incimage);
push(@cmdargs, "-S '$clogoscale'") if ($incimage);
push(@cmdargs, "-E '$intimage'") if ($intimage);
push(@cmdargs, "-T '$tlogoscale'") if ($intimage);
push(@cmdargs, "-f $SAVINPUT");
push(@cmdargs, "-D");
push(@cmdargs, "-m") if ($incdcase =~ /^slimcase/); 
push(@cmdargs, "-M") if ($incdcase =~ /^envelope/);
push(@cmdargs, "--create-dvd-inside") if ($incdcase =~ /^dvdinside/);
push(@cmdargs, "--create-dvd-outside") if ($incdcase =~ /^dvdoutside/);
push(@cmdargs, "--double-case") if ($incdcase =~ /^doublecase/);
push(@cmdargs, "-p") if (! $inscaleitems); 
push(@cmdargs, "-b") if ($innotrayhd);
push(@cmdargs, "-C") if ($innocoverhd);
push(@cmdargs, $ina4paper) if ($ina4paper);
push(@cmdargs, $CDL_BCODE_ARGS) if (-s "$BCODEFILE.eps");

# if number of items is very large, print some items on the cover also
push(@cmdargs, "-v " . int($num_items/2)) if ($num_items > 250 || $insplititems);

push(@cmdargs, "-o $WORKFILE.ps");

# cdlabelgen arguments:
# -c <category>    Set the category (title) for the CD
# -s <subtitle> 
# -d <date>    default: YYCC-MM-YY
# -D don't print date
# -f <filename>    input filename
# -e <cover_epsfile>
# -E <tray_epsfile>
# -m   for slim cd cases
# --create-dvd-inside   for inside inserts for DVD cases
# -M   for CD envelope
# -p   clip text - don't scale down item (if required to fit to a column)
# -b   don't print the plaque (title/subtile) on tray_card
# -y 1.5 or -y 0.8 for A4 paper

# system($cmd, @cmdargs); $returncode = ($? >> 8); 
# could not make the above work, anyway, need to call do_cmd, so using ` `
$cmd = join(' ', $CDLBL_E, @cmdargs);
&do_cmd($cmd) if (!$errflag);
$dontredirect = "1" if ($errflag); # main command failed, don't redirect

# 2: run PDF conversion
&do_cmd($PS2PDF_E) if (!$errflag);

if ($inmakegif) {
    # 3: run GIF conversion - intermediate - create .pgm file
    &do_cmd($PS2PGM_E) if (!$errflag);

    # 4: run GIF conversion - final - convert pgm to gif
    &do_cmd($PGM2GIF_E) if (!$errflag);
} # if $inmakegif

print " Done!\n<P>\n"; # status messages to web...

print MSGFILE "commands executed. \$errflag='$errflag' \$errcmd='$errcmd'\n";

# remove intermediate log files
unlink("$WORKFILE.pgm") unless ($opt_t || $DEBUG >= 2);

$end_time = time();
#NOTUSED $processing_time_taken = $end_time - $start_processing_time;
$receive_time_taken = $start_processing_time - $start_time;
$time_taken = $end_time - $start_time;
$time_taken_units = ($time_taken <= 1) ? "1 second" : "$time_taken seconds";
$datestr = localtime($end_time);
$datestr = "$WORKDIRNAME cdinsert [$datestr] took $time_taken secs ";
$datestr .= "(download $receive_time_taken) " if ($gotfile || $incimagefile || $intimagefile);
$datestr .= "[error]"  if ($errflag);
$datestr .= "\n";
print LOGFILE $datestr;
print MSGFILE $datestr;
print MSGFILE "----------------------------------------------------\n";

# copy output HTML page show output or error, as appropriate

# add the form to the done file, with filled in values
$form_fillin = HTML::FillInForm->new();
$form_html = $form_fillin->fill(scalarref => \$form_html, fobject => $query);

# complete rest of HTML from this CGI script, will redirect to WEBDONE
# copy output HTML page - show output or error, as appropriate
$done_tmpl = HTML::Template->new(filename => $DONE_TEMPLATE,
             path => [$ROOTDIR], die_on_bad_params => 0);
&replace_markers($done_tmpl);
$done_tmpl->output(print_to => *WEBDONE_HTML);
close(WEBDONE_HTML);

# complete rest of HTML from this CGI script, will redirect to WEBDONE
&send_working_trailer();

close(LOGFILE);
close(MSGFILE);

exit($errflag);

#-----------------------------------------------------------------------------
# Subroutines

sub show_status {
    my($cmd) = @_;

    $status_count++;
    if ($status_count < 0) { return ("Working . .<BR>\n"); }

    # if cmd contains | char, look for last | and the command after that
    # otherwise, use the first word as the command
    ($cmd =~ /\|\s+(\w+)[^|]*$/) || ($cmd =~ /\s*(\w+)/); # $1 is last command.
    return "&nbsp;&nbsp; ($1) . .<BR>\n" if ($1);

    return "&nbsp;&nbsp; $status_count . .<BR>\n";
}
#-----------------------------------
sub replace_markers {
    my($tmpl) = @_;
    # apply to only WORKING_TEMPLATE
    $tmpl->param(MRKR_DONTREDIRECT => $dontredirect);
    $tmpl->param(MRKR_WEBDONEHTML => "$WORKHTTP/$WEBDONE_HTML");

    # apply to both WORKING_TEMPLATE and DONE_TEMPLATE
    $tmpl->param(MRKR_HOSTNAME => "$hostname ( $hostaddr )");
    $tmpl->param(MRKR_ANYERROR => $errflag);
    $tmpl->param(MRKR_MSGFILE => "$WORKHTTP/$MSGFILENAME");

    # apply to only DONE_TEMPLATE
    $tmpl->param(MRKR_INPUT => "$WORKHTTP/$SAVINPUT");
    $tmpl->param(MRKR_PDF => "$WORKHTTP/$WORKFILE.pdf") if (-s "$WORKFILE.pdf");
    $tmpl->param(MRKR_MAKEGIF => $inmakegif);
    $tmpl->param(MRKR_GIF => "$WORKHTTP/$WORKFILE.gif") if (-s "$WORKFILE.gif");
    $tmpl->param(MRKR_POSTSCRIPT => "$WORKHTTP/$WORKFILE.ps") if (-s "$WORKFILE.ps");
    $tmpl->param(MRKR_TIMETAKEN => $time_taken_units);
    $tmpl->param(MRKR_FORM_HTML => $form_html);
    $tmpl->param(MRKR_BCODE_EPS => "$WORKHTTP/$BCODEFILE.eps") if ($inbcodetext && -s "$BCODEFILE.eps");

    if ($errflag) {
      if ($errcmd =~ /$CDLBL_E/) {
        $tmpl->param(MRKR_CDLERROR => 1);
      } elsif ($errcmd =~ /$PGM2GIF_E/) {
        $tmpl->param(MRKR_GIFERROR=> 1);
      } else {
        $tmpl->param(MRKR_SYSERROR=> 1);
      }
    }
}

#----------------------------------------
sub send_working_trailer {
    if (defined $working_trailer_tmpl) {
	&replace_markers($working_trailer_tmpl);
	$working_trailer_tmpl->output(print_to => *STDOUT);
    }
    # this completes the output HTML file displayed while processing job
}
#----------------------------------------

sub do_cmd {
    my($cmd) = @_;
    my ($t1, $td);

    $datestr = localtime(time());
    print MSGFILE "[$datestr]: do_cmd\n";

    print &show_status($cmd);
    $t1 = time();
    $out = `$cmd`;
    $returncode = ($? >> 8); 
    $td = time() - $t1;
    print MSGFILE qq("$cmd" executed\n -- Took $td seconds, returns $returncode\n);
    if ($returncode != 0) {
	print "<P>\n";
	print "Session ID# <B>$WORKDIRNAME</B> - an error occured running a command.\n<BR>\n";
	print "Command: ", escapeHTML($cmd), ", \$? is $?\n<BR>";
	$out = escapeHTML($out);
	$out =~ s/\n/\n<BR>/;
	print qq($out\n<BR><hr><BR>\n);
	$errflag++;
	$errcmd = $cmd;
	print MSGFILE "Error occurred:\n";
    }
    print MSGFILE "$out\n---------------------\n";
    $returncode;
}
#-----------------------------------

sub sighandler {

    unlink("$WORKFILE.pgm"); # this file can get big, so making sure it is gone

    $datestr = localtime(time());
    $str = "$WORKDIRNAME cdinsert [$datestr] user terminated --\n";
    print LOGFILE $str;
    print MSGFILE $str;

    close(WEBDONE_HTML);
    close(LOGFILE);
    close(MSGFILE);

    exit($errflag);
}

#-----------------------------------

sub myexit {
    # if myexit() is called after WORKING_TEMPLATE copied to STDOUT, 
    # the automatic redirect in that file needs to be suppressed
    $dontredirect = "1";
    $errflag++;

    my($mesg) = @_;
    print "<html><head><title>Error</title></head><body>\n" unless ($sent_working_header);
    print "<P>\nSession ID# <B>$WORKDIRNAME</B> - Error - $mesg\n<HR><P>";
    # displayed in middle of WORKING_TEMPLATE

    $datestr = localtime(time());
    $str = "$WORKDIRNAME [$datestr] Error - $mesg\n";

    print STDERR $str; # goes to Apache error_log or LOGFILE
    print MSGFILE $str;

    # complete rest of HTML from this CGI script
    if ($sent_working_header) { &send_working_trailer(); }
    else { print "</body></html>\n"; }

    close(LOGFILE);
    close(MSGFILE);

    exit($errflag);
}
#----------------------------------------
# Try a few times to make unique temp directory by appending chars if needed

sub mktempdir {
    my $dir = shift; # directory to create tmp dir in
    my $try = shift; # prefix to use for directory name
    my $n = shift; # a numeric suffix to use - is incremented until unique
    my $done = 0;
    my $i;
    my $dirname;

    umask(0);
    foreach $i (0..9) {
	$dirname = "$try-$n";
	$done = mkdir("$dir/$dirname", 0777);
	last if ($done);
	$n++;
    }
    $done || myexit("<p>mktempdir: mkdir in ($dir) with prefix ($try-$n) failed: $!\n<p>Try the job again, it may work next time.<p>");
    $done ? $dirname : "";
}
#-----------------------------------------------------------------------------
