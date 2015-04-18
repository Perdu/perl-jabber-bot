#!/usr/bin/perl

use warnings;
use strict;
use utf8;

while (<>) {
	my $line = $_;
	my $line_converted = $line;
	utf8::encode($line_converted);
	if ($line =~ /[\x{c7}\x{e9}\x{e0}]/) {
		print $line_converted;
	} else {
		print $line;
	}
}

