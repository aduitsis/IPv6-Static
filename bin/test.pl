#!/usr/bin/perl -w

use v5.14; #implies use feature 'unicode_strings'

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use warnings qw(FATAL utf8);
use strict;


if ( 'whatever-,897437249' =~ /\P{ASCII}/ ) {
	say 'contains non-latin characters';
}
