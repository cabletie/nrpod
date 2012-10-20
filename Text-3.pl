#!/usr/bin/perl -w
use Tk;
print $^O,"\n";
my $ti = 2;
my $tiString = sprintf("%02d", $ti);
print "foobar".$tiString."-something\n";
$mw = tkinit;
$b = Button::new($mw, -text => 'Hello World');
$b->configure(-method => sub {exit});
tkpack($b);
tkmainloop;
