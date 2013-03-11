package Heuristics;

use v5.14; #implies use feature 'unicode_strings'

use utf8;
use locale;
use open qw(:std :utf8);    
use charnames qw(:full :short);  
use warnings qw(FATAL utf8);
use strict;

use Data::Dump qw(pp);

binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";

sub classify {
	my $unit = shift // die 'unit is undefined';
	
	#say $_;
	#$_ = decode('utf8',$_);
	#printf "%v04X\n",$_ for unpack("C0A*", $_);
	#return 1 if utf8::is_utf8( $_ );
	#$_ =~ /\xce\xa0/iux

	#legend:
	# 1: πρωτοβάθμια εκπαιδευτική μονάδα
	# 2: δευτεροβάθμια εκπαιδευτική
	# 3: διοικητική μονάδα 
	# 4: τριτοβάθμια (sic) μονάδα
	# 5: εκπαιδευτική μονάδα ανεξ βαθμίδας
	# 7: unknown

	return 3 if ( grep { /Διοικητικές/i } @{ $unit->{attributes}->{'businesscategory;category'} } ); # διοικητική μονάδα κατευθείαν 
	return 3 if ( grep { /ΔΙΕΥΘ-ΓΡΑΦΕΙΟ|ΥΠΕΠΘ|ΤΕΧΝΙΚΗ ΣΤΗΡΙΞΗ|ΔΙΟΙΚΗΤΙΚΗ ΜΟΝΑΔΑ/i } @{ $unit->{attributes}->{'businesscategory'} } ); #  διευθυντικό γραφείο

	return 4 if ( grep { /ΤΡΙΤΟΒΑΘΜΙΑ/i } @{ $unit->{attributes}->{businesscategory} } ); # τριτοβάθμια

	return 1 if ( grep { /ΣΧΟΛΕΙΟ ΠΕ/i } @{ $unit->{attributes}->{businesscategory} } ); # σχολείο πρωτοβάθμιας κατευθείαν
	return 2 if ( grep { /ΣΧΟΛΕΙΟ ΔΕ/i } @{ $unit->{attributes}->{businesscategory} } ); # σχολείο δευτεροβάθμιας κατευθείαν

			
	if( 
		( grep { /ΕΚΠΑΙΔΕΥΤΙΚΗ ΜΟΝΑΔΑ|Εκπαιδ. Δημόσιες|Εκπαιδ. Ιδιωτικές|ΥΠΟΣΤΗΡΙΚΤΙΚΗ ΜΟΝΑΔΑ/i } @{ $unit->{attributes}->{'businesscategory;category'} } ) 
		|| 
		( grep { /ΕΚΠΑΙΔΕΥΤΙΚΗ ΜΟΝΑΔΑ|Εκπαιδ. Δημόσιες|Εκπαιδ. Ιδιωτικές|ΥΠΟΣΤΗΡΙΚΤΙΚΗ ΜΟΝΑΔΑ/i } @{ $unit->{attributes}->{businesscategory} } ) 
	) { 
		return 1 if ( grep { /ΠΡΩΤΟΒΑΘΜΙΑ|Πρωτοβάθμια/i } @{ $unit->{attributes}->{businesscategory} } );
		return 2 if ( grep { /ΔΕΥΤΕΡΟΒΑΘΜΙΑ|Δευτεροβάθμια/i } @{ $unit->{attributes}->{businesscategory} } );
		return 7; #unknown
	} 

	#last ditch attempt
	return 2 if ( grep { /ΔΕΥΤΕΡΟΒΑΘΜΙΑ|Δευτεροβάθμια/i } @{ $unit->{attributes}->{businesscategory} } );	
	return 1 if ( grep { /ΠΡΩΤΟΒΑΘΜΙΑ|Πρωτοβάθμια/i } @{ $unit->{attributes}->{businesscategory} } );	
	return 7 if ( grep { /ΑΛΛΟΣ/i } @{ $unit->{attributes}->{title} } );	
	return 5 if ( grep { /ΑΝΕΞ ΒΑΘΜΙΔΑΣ/i } @{ $unit->{attributes}->{businesscategory} } );  #δηλώνεται ρητά ότι δεν υπάρχει βαθμίδα

	die 'Cannot classify unit: ' . pp( $unit ); 
		
}

1;
