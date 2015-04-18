#!/usr/bin/perl

use warnings;
use strict;
use utf8;

while (<>) {
	my $line = $_;
	my $line_converted = $line;
	utf8::encode($line_converted);
	# Ç, é, è, ï, â, ê, ç
	if ($line =~ /[\x{c7}\x{e9}\x{e0}\x{ef}\x{e2}\x{e8}\x{e7}]/ && $line !~ /\x{e2}\x{80}/) {
		print $line_converted;
	} else {
		print $line;
	}
}
