#  ----------------------------------------------------------------------------
#  "THE BEER-WARE LICENSE":
#  <ivan@sanchezortega.es> wrote this file. As long as you retain this notice you
#  can do whatever you want with this stuff. If we meet some day, and you think
#  this stuff is worth it, you can buy me a beer in return.
#  ----------------------------------------------------------------------------
# 
# Reverse geolocation extension for TTYtter - just issue "/where a1" to know where the tweet was sent from, in a user-friendly text mode.
#
# This makes use of the OpenStreetMap geocoding service, Nominatim. Please do have a look at http://wiki.openstreetmap.org/wiki/Nominatim (just be nice and don't send thousands of requests at once)



print "-- This extension makes use of the OpenStreetMap geocoding service, Nominatim. Geolocation data is CC-by-sa OpenStreetMap contributors. Have a look at http://wiki.openstreetmap.org/wiki/Nominatim\n";



$handle = sub {
	my $tweet = shift;

	&defaulthandle($tweet);

	if ($tweet->{'user'}->{'geo_enabled'} ne 'true' ||
		($tweet->{'geo'}->{'coordinates'}->[0] eq 'undef')) {
# 		print $stdout "-- sorry, no geoinformation in that tweet.\n";
		return 1;
	}
	
	my $r = &grabjson("http://nominatim.openstreetmap.org/reverse".
		"?lat=" . $tweet->{'geo'}->{'coordinates'}->[0] .
		"&lon=" . $tweet->{'geo'}->{'coordinates'}->[1] .
		"&format=json&user-agent=ttytter",0,1);
	
	my $location = $r->{'display_name'};
	
	&$utf8_decode($location);
	

	# Basically copied from ttytter.pl's defaulthandle
	my $menu_select = $tweet->{'menu_select'};
	
	$menu_select = (length($menu_select) && !$script)
		? (($menu_select =~ /^z/) ?
			"${EM}${menu_select}+${OFF} " :
			"${menu_select}+ ")
		: '';



	print $streamout ($menu_select . " " . $location . "\n" );
	
	return 1;
};



