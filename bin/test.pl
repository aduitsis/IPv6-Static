#!/usr/bin/perl -w

use utf8;
use Encode qw(decode);

use v5.14;

use warnings;
use strict;
use Data::Printer;
use FindBin qw($Bin);
use lib $Bin.'/../lib/';
use LDAPHelper;
use Storable;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $ldap = LDAPHelper->new;

my $units = $ldap->get_combination ;
for my $unit (keys %{ $units } ) {
	say p $units->{ $unit } ;
}

