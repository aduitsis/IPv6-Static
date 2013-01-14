#!/usr/bin/perl -w

use v5.14; #implies use feature 'unicode_strings'

use utf8;
use locale;
use open qw(:std :utf8);
use charnames qw(:full :short);
use warnings qw(FATAL utf8);
use strict;

use Net::LDAP;
use Data::Printer;
use Data::Dump qw(pp);
use Getopt::Long;
use Storable qw(nstore retrieve);
use Term::ReadKey;
use Term::ReadLine;
use Pod::Usage;

use FindBin qw( $Bin ) ;

use lib $Bin.'/../lib';
use lib $Bin.'/../../ip6prefix/lib';
use IPv6::Static;
use IPv6::Address;
use Pools;

use Heuristics;

use DBHelper;

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

my $DEBUG = 0;

my $help;

db_getoptions('help|?'=> \$help, 'd' => \$DEBUG);

pod2usage(-verbose => 2) if $help;

my $username = shift // die 'missing username';
        
my $dbh = db_connect;

my $r =  Pools::get_prefixes( $dbh , $username ) ;

say $r->{framed};
say $r->{delegated};


__END__

=head1 NAME

get_ipv6_prefixes -- get the assigned IPv6 prefixes for a specific username

=head1 SYNOPSIS

 get_ipv6_prefixes.pl [ options ] user_identifier

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exit.

=item B<-d>

Enable more verbose output

=item B<-host|-h> 

Connect to mysql on this hostname.

=item B<-user|-u>

Use this mysql username when connecting.

=item B<-p|-password>

Use this mysql password when connecting.

=item B<-db> 

Use this database when connecting.

=back

=head1 DESCRIPTION 

The purpose of this program is to return the assigned IPv6 prefixes for
a specific user identifier which is supplied as the argument. If the
user identifier does not exist, the program will emit an error message
and exit. Otherwise, one would expect a couple of prefixes to be
printed, one line each.

=cut

