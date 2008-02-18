#!/usr/bin/perl
while (<STDIN>) {
  chomp;
  last if ($_ eq 'eval $finish; exit $res');
}
while (read STDIN, $buf, 4096) {
  print STDOUT $buf;
}
