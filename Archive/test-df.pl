#!/usr/bin/perl -w
  use Filesys::DfPortable;

print "for C:\\:\n";
  my $ref = dfportable("C:\\"); # Default block size is 1, which outputs bytes
  if(defined($ref)) {
     print"Total bytes: $ref->{blocks}\n";
     print"Total bytes free: $ref->{bfree}\n";
     print"Total bytes avail to me: $ref->{bavail}\n";
     print"Total bytes used: $ref->{bused}\n";
     print"Percent full: $ref->{per}\n"
  }
print "for E:\\:\n";
$ref = dfportable("E:\\"); # Default block size is 1, which outputs bytes
  if(defined($ref)) {
     print"Total bytes: $ref->{blocks}\n";
     print"Total bytes free: $ref->{bfree}\n";
     print"Total bytes avail to me: $ref->{bavail}\n";
     print"Total bytes used: $ref->{bused}\n";
     print"Percent full: $ref->{per}\n"
  }

