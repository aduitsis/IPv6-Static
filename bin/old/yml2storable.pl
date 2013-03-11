#!/usr/bin/perl -w

use v5.14;

use warnings;
use strict;
use Net::LDAP;
use Data::Printer;
use Data::Dump qw(pp);
use Getopt::Long;
use YAML qw(LoadFile);
use Storable qw(nstore retrieve);

my $filename = shift // die 'missing source filename';
my $target = shift // die 'missing target filename';

my $data = LoadFile($filename);

nstore $data,$target;

