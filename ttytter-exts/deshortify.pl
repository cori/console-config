﻿
#  ----------------------------------------------------------------------------
#  "THE BEER-WARE LICENSE":
#  <ivan@sanchezortega.es> wrote this file. As long as you retain this notice you
#  can do whatever you want with this stuff. If we meet some day, and you think
#  this stuff is worth it, you can buy me a beer in return.
#  ----------------------------------------------------------------------------
#
# De-shortification of URLs in tweets.
#
# This extension will go through each of the received tweets and try to unshorten 'em all. Not all urls shorteners and redirects are known, so some URLs will not be the final ones.
#
# Requirements: URI::Find and URI::Split and LWP::UserAgent. Please run "apt-get install liburi-find-perl libwww-perl" or "cpan URI::Find" and "cpan URI::Split" and "cpan LWP::UserAgent" if this extension fails to load.
#
# Features:
#  * A non-comprehensive list of known URL shorteners
#  * Fancy ANSI underlining of URLs that will break if the URL contains a search term
#  * Lightweight, HEAD-only requests.
#  * Fancy custom user agent (Unlike main TTYtter), friendlier to website sysadmins.
#  * De-shortened URLs cache, in order to not request anything when you see the same URL time and time again (useful for mass RTs or TTs)
#  * The de-shortened URLs cache will empty from time to time (currently every 2000 URLs) in order to prevent taking up too much memory.
#  * Web stats tracking queries de-crapifier. No more useless ?utm_medium=twitter littering your stream. And a tiny bit of better privacy for you.
#  * Replaces URL-encoded UTF-8 in the URL body for the corresponding character (i.e. "%C4%99" turns into "ę"). Hopefully this won't mess up non-UTF-8 systems.
#  * Proxy support. Deshortify will try to fetch proxy config from environment variables. Tor users will be interested in adding the following to their .ttytterrc file:
#       extpref_deshortifyproxy=socks://localhost:9050
#
# Bugs and gotchas:
#  * Might fail to resolve a URL you just posted in stream mode: the t.co shortener needs a couple of seconds after the tweet was posted in order to be able to resolve the URLs.
#  * Might fail to maintain the integrity of a URL with lots of URL-encoded = and & and / and whatnot. Apply the trick commented in the code and report back to me, will you?
#  * Proxy configuration is deshortify-specific. Deshortify uses perl's LWP::UserAgent instead of lynx or curl. If you use a proxy, you'll have to configure ttytter and deshortify separately.
#  * Verbose mode is verbose. Very.
#
# Be advised: this extension will send HTTP HEAD requests to all the URLs to be resolved. Be warned of this if you're concerned about privacy.
#
# TODO: Add a redirect config value, so users can set "I don't care about making more useless requests that will take my precious time, just resolve the URL for good!"
# TODO: Allow a screen width to be specified, and then don't de-shortify links if the width of the tweet would exceed that. Or get the screen width from the environment somehow.
# TODO: Add a carriage return (but no line feed) ANSI control char, after the links have been deshortified. If you're writing something while URLs are being resolved, the display will be messed up. Hopefully a CR will help hide the problem. Update: ANSI control chars to move the cursor or clear the current line will fail miserably; all I managed is to add a blank line between tweets. It seems that it has something to do with ReadLine::TTYtter.
# TODO: Fix TTYtter so that search and tracked keywords are shown with the "Bold on" and "bold off" ANSI sequences instead of "bold on" and "reset". Right now URL underlining will be messed up if the full URL contains the keyword. Hopefully this can be done in 2.1.0 or 2.2.0.




# Show when extension is being loaded
print "-- Don't like to see short URLs, do you?\n";


# If a proxy is set due to environment variables or .ttytterrc, tell so during load. Not really needed, but for as long as I cannot test it, this might be useful.
if ($extpref_deshortifyproxy)
{
	print "-- Deshortify will use $extpref_deshortifyproxy as a proxy for both HTTP and HTTPS requests\n";
}
elsif ( $ENV{http_proxy} or $ENV{https_proxy} )
{
	if ( $ENV{http_proxy} ){
		print "-- Deshortify will use $ENV{http_proxy} as a proxy for HTTP requests\n";
	} else {
		print "-- Deshortify will not use a proxy for HTTP requests\n";
	}

	if ( $ENV{https_proxy} ){
		print "-- Deshortify will use $ENV{https_proxy} as a proxy for HTTPS requests\n";
	} else {
		print "-- Deshortify will not use a proxy for HTTPS requests\n";
	}
}



require URI::Find;

use URI::Split qw(uri_split uri_join);

use LWP::UserAgent;

use Data::Dumper qw{Dumper};



# Define UNDEROFF, to turn off just the underlining
$ESC = pack("C", 27);
$UNDEROFF = ($ansi) ? "${ESC}[24m" : '';


our %deshortify_cache = ();

# our $deshortify_cache_empty_counter = 0;
# our $deshortify_cache_limit = 2000;
# our $deshortify_cache_flushes = 0;
# our $deshortify_cache_hit_count = 0;

our %store = ( "cache_misses", 0, "cache_limit", 2000, "cache_flushes", 0, "cache_hit_count", 0);


# For some strange reason initial values up there are ignored. FIXME: Why?
$store->{cache_limit} = 2000;
$store->{cache_misses} = 0;
$store->{cache_hit_count} = 0;
$store->{cache_flushes} = 0;




# Given a URL, will unshort it.
$unshort = sub{
	our $verbose;
	our $superverbose;
	our $TTYtter_VERSION;
# 	our $deshortify_cache;
	our $store;
	my $url = shift;

	my $original_url = $url;

	# parse and break the url into components
	($scheme, $auth, $path, $query, $frag) = uri_split($url);

# 	print "scheme $scheme auth $auth path $path query $query frag $frag\n" if ($verbose);


	# Gathered a few shorteners. Should not be considered as a comprehensive list, but it'll do.
	if (($auth eq "g.co")	or	# Google
	    ($auth eq "j.mp")	or
	    ($auth eq "q.gs")	or
	    ($auth eq "t.co")	or	# twitter
	    ($auth eq "cl.ly")	or
	    ($auth eq "db.tt")	or
	    ($auth eq "ds.io")	or
	    ($auth eq "ed.lc")	or
	    ($auth eq "es.pn")	or
	    ($auth eq "fb.me")	or
	    ($auth eq "ht.ly")	or
	    ($auth eq "is.gd")	or
	    ($auth eq "kl.am")	or
	    ($auth eq "me.lt")	or
	    ($auth eq "om.ly")	or
	    ($auth eq "ow.ly")	or
	    ($auth eq "po.st")	or
	    ($auth eq "su.pr")	or
	    ($auth eq "ti.me")	or
	    ($auth eq "to.ly")	or
	    ($auth eq "tl.gd")	or	# Twitlonger
	    ($auth eq "tr.im")	or
	    ($auth eq "wp.me")	or	# Wordpress
	    ($auth eq "adf.ly")	or
	    ($auth eq "awe.sm")	or
	    ($auth eq "bbc.in")	or	# bbc.co.uk
	    ($auth eq "bit.ly")	or
	    ($auth eq "cdb.io")	or
	    ($auth eq "cgd.to")	or
	    ($auth eq "cli.gs")	or
	    ($auth eq "cor.to")	or
	    ($auth eq "cos.as")	or
	    ($auth eq "cot.ag")	or
	    ($auth eq "cur.lv")	or
	    ($auth eq "dld.bz")	or
	    ($auth eq "ebz.by")	or
	    ($auth eq "fdl.me")	or
	    ($auth eq "git.io")	or	# GitHub
	    ($auth eq "gkl.st")	or	# GeekList
	    ($auth eq "goo.gl")	or	# Google
	    ($auth eq "glo.bo")	or	# Brazilian Globo
	    ($auth eq "grn.bz")	or
	    ($auth eq "gu.com")	or	# The Guardian
	    ($auth eq "htl.li")	or
	    ($auth eq "htn.to")	or
	    ($auth eq "hub.am")	or
	    ($auth eq "ind.pn")	or	# The Independent.co.uk
	    ($auth eq "kcy.me")	or	# Karmacracy
	    ($auth eq "mbl.mx")	or
	    ($auth eq "mun.do")	or	# El Mundo
	    ($auth eq "muo.fm")	or	# MakeUseOf
	    ($auth eq "mzl.la")	or	# Mozilla
	    ($auth eq "owl.li")	or
	    ($auth eq "pco.lt")	or
	    ($auth eq "prn.to")	or	# PR News Wire
	    ($auth eq "red.ht")	or
	    ($auth eq "reg.cx")	or
	    ($auth eq "rww.to")	or
	    ($auth eq "sbn.to")	or
	    ($auth eq "sco.lt")	or
	    ($auth eq "see.sc")	or
	    ($auth eq "smf.is")	or	# Summify
	    ($auth eq "soc.li")	or
	    ($auth eq "sta.mn")	or	# Stamen - Gotta love these guys' maps!
	    ($auth eq "tgn.me")	or
	    ($auth eq "tgr.ph")	or	# The Telegraph
	    ($auth eq "tnw.to")	or	# TheNextWeb
	    ($auth eq "tny.gs") or
	    ($auth eq "tpm.ly")	or
	    ($auth eq "tpt.to")	or
	    ($auth eq "ur1.ca")	or
	    ($auth eq "vsb.li")	or
	    ($auth eq "vsb.ly")	or
	    ($auth eq "6sen.se")	or
	    ($auth eq "amzn.to")	or	# Amazon.com
	    ($auth eq "amba.to")	or	# Ameba.jp
	    ($auth eq "buff.ly")	or
	    ($auth eq "cnet.co")	or	# C-Net
	    ($auth eq "cort.as")	or
	    ($auth eq "dell.to")	or	# Dell
	    ($auth eq "dlvr.it")	or
	    ($auth eq "econ.st")	or	# The Economist
	    ($auth eq "engt.co")	or	# Engadget
# 	    ($auth eq "flic.kr")	or	# Hhhmm, dunno is there's much use in de-shortening to flickr.com anyway.
	    ($auth eq "hint.fm")	or
	    ($auth eq "huff.to")	or	# The Huffington Post
	    ($auth eq "lnkd.in")	or	# Linkedin
	    ($auth eq "monk.ly")	or
	    ($auth eq "nblo.gs")	or	# Networked Blogs
	    ($auth eq "neow.in")	or	# NeoWin
	    ($auth eq "noti.ca")	or
	    ($auth eq "nyti.ms")	or	# New York Times
	    ($auth eq "pear.ly")	or
	    ($auth eq "post.ly")	or	# Posterous
	    ($auth eq "ppfr.it")	or
	    ($auth eq "prsm.tc")	or
	    ($auth eq "qkme.me")	or	# QuickMeme
	    ($auth eq "read.bi")	or	# Business Insider
	    ($auth eq "reut.rs")	or	# Reuters
	    ($auth eq "seen.li")	or	($auth eq "seenthis.net" and $path eq "/index.php")	or # SeenThis, AKA http://seenthis.net/index.php?action=seenli&me=1ing
	    ($auth eq "seod.co")	or
	    ($auth eq "shar.es")	or
	    ($auth eq "tcrn.ch")	or	# Techcrunch
	    ($auth eq "tiny.cc")	or
	    ($auth eq "trib.al")	or	($auth =~ m/\.trib\.al$/ )	or	# whatever.trib.al is done by SocialFlow
	    ($auth eq "vrge.co")	or	# The Verge
	    ($auth eq "yhoo.it")	or	# Yahoo
	    ($auth eq "xfru.it")	or
	    ($auth eq "zite.to")	or
	    ($auth eq "a.eoi.co")	or	# Escuela de Organización Industrial
	    ($auth eq "amzn.com")	or	# Amazon.com
	    ($auth eq "buswk.co")	or	# Business Week
	    ($auth eq "cultm.ac")	or	# Cult of Mac
	    ($auth eq "egent.me")	or
# 	    ($auth eq "enwp.org")	or	# English Wikipedia. Not really worth deshortening.
	    ($auth eq "flpbd.it")	or	# Flipboard
	    ($auth eq "mcmgz.in")	or	# Mac Magazine
	    ($auth eq "menea.me")	or	# Menéame
	    ($auth eq "mhoff.me")	or
	    ($auth eq "migre.me")	or
	    ($auth eq "mslnk.bz")	or
	    ($auth eq "nokia.ly")	or
	    ($auth eq "on.fb.me")	or
	    ($auth eq "oreil.ly")	or
	    ($auth eq "p.ost.im")	or
	    ($auth eq "pulse.me")	or	($auth eq "www.pulse.me")	or
	    ($auth eq "qwapo.es")	or
	    ($auth eq "rafam.co")	or
	    ($auth eq "refer.ly")	or
	    ($auth eq "short.ie")	or
	    ($auth eq "short.to")	or
	    ($auth eq "slate.me")	or	# The Slate
	    ($auth eq "s.vfs.ro")	or
	    ($auth eq "tmblr.co")	or
	    ($auth eq "twurl.nl")	or
	    ($auth eq "ymlp.com")	or
#	    ($auth eq "youtu.be")	or	# This one is actually useful: no information is gained by de-shortening.
	    ($auth eq "w.abc.es")	or
	    ($auth eq "bitly.com")	or
	    ($auth eq "keruff.it")	or
	    ($auth eq "m.safe.mn")	or
	    ($auth eq "onforb.es")	or	# Forbes
	    ($auth eq "thebea.st")	or	# The Daily Beast
	    ($auth eq "on.rt.com")	or	# RT
	    ($auth eq "feedly.com")	or
	    ($auth eq "on.mash.to")	or	# Mashable
	    ($auth eq "on.wsj.com")	or	# Wall Street Journal
	    ($auth eq "theatln.tc")	or	# The Atlantic
	    ($auth eq "to.pbs.org")	or	# PBS
	    ($auth eq "tinyurl.com")	or
	    ($auth eq "www.tumblr.com")	or
	    ($auth eq "feeds.gawker.com")	or
	    ($auth eq "feeds.feedburner.com")	or
	    ($auth eq "feedproxy.google.com")	or
	    ($auth eq "www.pheedcontent.com")	or	# Oh, look, Imma l337 h4xx0r. Geez.
	    ($auth =~ m/^news\.google\.[a-z]{2,3}$/)	or	# Hah! You thought you were going to pollute my links, did you, google news?
	    ($auth eq "www.linkedin.com" and $path eq "/slink")	or	# A tricky one. lnkd.in redirects to www.linkedin.com/slink?foo, which redirects again.
	    ($auth =~ m/^feeds\./)	or	# OK, I've had enough of you, feeds.whatever.whatever!
	    ($auth =~ m/feedsportal\.com$/)	or	# Gaaaaaaaaaaaaaaaah!
	    ($auth =~ m/^rss\./)	or	# Will this never end?
	    ($auth =~ m/^rd\.yahoo\./)	or	# Yahoo feeds... *sigh*
	    ($auth =~ m/^redirect\./)	or	# redirect.viglink.com and others
	    ($auth eq "www.google.com" and $path eq "/url")	or	# I hate it when people paste URLs from the stupid google url tracker.
	    ($auth eq "traffic.shareaholic.com")	# Yet another traffic counter
	    )
	{
		print $stdout "-- Yo, deshortening $url ($auth)\n" if ($superverbose);

		# Check the cache first.
		if ($deshortify_cache{$original_url})
		{
# 			our $deshortify_cache_hit_count;
			$store->{cache_hit_count} += 1;
			print $stdout "-- Deshortify cache hit: $url -> " . $deshortify_cache{$original_url} . " ($store->{cache_hit_count} hits)\n" if ($verbose);
			return &$unshort($deshortify_cache{$original_url});
		}

# 		our $deshortify_cache_empty_counter;
		$store->{cache_misses} += 1;

# 		our $deshortify_cache_limit;
		if ($store->{cache_misses} >= $store->{cache_limit})
		{
# 			our $deshortify_cache_flushes;
			$store->{cache_flushes} += 1;
			$deshortify_cache = ();
			$store->{cache_misses} = 0;
			print $stdout "-- Deshortify cache flushed\n" if ($verbose)
		}



		# Visit the link with a HEAD request, see if there's a redirect header. If redirected -> that's the URL we want.
		my $ua = LWP::UserAgent->new;
		$ua->max_redirect( 0 );	# Don't redirect, just return the headers and look for a "Location:" one manually.
		$ua->agent( "TTYtter $TTYtter_VERSION URL de-shortifier (" . $ua->agent() . ") (+http://www.floodgap.com/software/ttytter/) (+http://ivan.sanchezortega.es/ttytter/)" ); # Be good net citizens and say how nerdy we are and that we're a bot

		if ($extpref_deshortifyproxy) {	# If there's a proxy configured in .ttytterrc, use it no matter what.
			$ua->proxy([qw/ http https /] => $extpref_deshortifyproxy);
		}
		else # If no proxy configured, try to get the one set up in the environment variables
		{
			if ( $ENV{http_proxy} ){
				$ua->proxy([qw/ http /] => $ENV{http_proxy} );
			}
			if ( $ENV{https_proxy} ){
				$ua->proxy([qw/ https /] => $ENV{https_proxy} );
			}
		}

		$ua->cookie_jar({});

		my $request  = HTTP::Request->new( HEAD => "$url" );
		my $response = $ua->request($request);

# 		if ( $response->previous ) {
# 		if ( $response->is_success and $response->previous ) {
		if ($response->header( "Location" )) {
# 			$url = $response->request->uri;
			$url = $response->header( "Location" );
			print "-- Deshortened: $original_url -> $url\n" if ($verbose);

			# Add to cache
			$deshortify_cache{$original_url} = $url;


			# Let's run the URL again - maybe this is another short link!
			return &$unshort($url);
		}
	}
	# TODO: treat adf.ly links. Pull off the entire page, then run a regexp searching for var url = 'http://adf.ly/go/whatever';
	else
	{
		print $stdout "-- That URL doesn't seem like it's a URL shortener, it must be the real one.\n" if ($superverbose);

		# Do some heuristics and try to stave off stupid, spurious crap out of URLs. Like "?utm_source=twitterfeed&utm_medium=twitter
		# This crap is used for advertisers to track link visits. Screw that!

		# Stuff to cut out: utm_source utm_medium utm_term utm_content utm_campaign (from google's ad campaigns)
		# Stuff to cut out: spref=tw (from blogger)
		# Stuff to cut out: ref=tw (from huff post and others)
		# Stuff to cut out: youtube.com

# 		print "-- scheme $scheme auth $auth path $path query $query frag $frag\n" if ($verbose);
		if ($query)
		{
			@pairs = split(/&/, $query);
			foreach $pair (@pairs){
				($name, $value) = split(/=/, $pair);

				if ($name eq "utm_source" or $name eq "utm_medium" or $name eq "utm_term" or $name eq "utm_content" or $name eq "utm_campaign"
					or ( $name eq "tag" and $value eq "as.rss" )
					or ( $name eq "ref" and $value eq "rss" )
					or ( $name eq "ref" and $value eq "tw" )
					or ( $name eq "newsfeed" and $value eq "true" )
					or ( $name eq "spref" and $value eq "tw" )
					or ( $name eq "spref" and $value eq "fb" )
					or ( $name eq "spref" and $value eq "gr" )
					or ( $auth eq "www.youtube.com" and $name eq "feature")
					 )
				{
					my $expr = quotemeta("$name=$value");	# This prevents strings with "+" to be interpreted as part of the regexp
					$query =~ s/($expr)&//;
					$query =~ s/&($expr)//;
					$query =~ s/($expr)//;
					print $stdout "---- Trimming spammy URL parameters: $name = $value - now $query\n" if ($superverbose);
				}
			}
			$url = uri_join($scheme, $auth, $path, $query, $frag);
		}

# 		# Dirty trick to prevent escaped = and & and # to be unescaped (and mess up the query string part) - escape them again!
# 		$url =~ s/%24/%2524/i;	# $
# 		$url =~ s/%26/%2526/i;	# &
# 		$url =~ s/%2B/%252B/i;	# +
# 		$url =~ s/%2C/%252C/i;	# ,
# 		$url =~ s/%2F/%252F/i;	# /
# 		$url =~ s/%3A/%253A/i;	# :
# 		$url =~ s/%3B/%253B/i;	# ;
# 		$url =~ s/%3D/%252B/i;	# =
# 		$url =~ s/%3F/%252B/i;	# ?
# 		$url =~ s/%40/%252B/i;	# @

		# Replace %XX for the corresponding character - makes URLs more compact and legible. Hopefully won't mess anything up.
		$url =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		# Waaaait a second, did we just replace "%20" for " "? That'll just mess up things...
		$url =~ s/ /+/g;
	}

# 	print $stdout "-- $original_url de-shortened into $url\n" if ($verbose && $url != $original_url) ;

	# Hey, let's underline URLs!
	return ${UNDER} . $url . ${UNDEROFF};
};



# Deshortify URLs in both standard tweets and DMs
$dmhandle = $handle = sub {
	our $verbose;
	our $ansi;
	my $tweet = shift;

	my $text = $tweet->{'text'};

	# Why the hell are there backslashes messing up the forward slashes in the URLs?
	# Will this break something???
	$text =~ s/\\\//\//g;

	# Yeah, a \n just before a http:// will mess things up.
	$text =~ s/\\nhttp:\/\//\\n http:\/\//g;

	# Any URIs you find, run them through unshort()...
	my $finder = URI::Find->new(sub { &$unshort($_[0]) });

	$how_many_found = $finder->find(\$text);

	print $stdout "-- $how_many_found URLs de-shortened\n" if ($superverbose);

	$tweet->{'text'} = $text;

	&defaulthandle($tweet);
	return 1;

# 	return $text;
};







# Show cache statistics. Not really useful, but hey.
$addaction = $shutdown = $heartbeat = sub {
	our $verbose;
	our $is_background;

	if ($is_background)
	{
		our $store;
		$cache_hits  = $store->{'cache_hit_count'};
		$cache_miss  = $store->{'cache_misses'} + ($store->{'cache_limit'} * $store->{'cache_flushes'} );
		$cache_flush = $store->{'cache_flushes'};
		$context = "background";
	}
	else
	{
		print "-- Fetching deshortify cache stats from background process\n" if $verbose;
		$cache_hits  = getbackgroundkey('cache_hit_count');
		$cache_miss  = getbackgroundkey('cache_misses') + (getbackgroundkey('cache_limit') * getbackgroundkey('cache_flushes') );
		$cache_flush = getbackgroundkey('cache_flushes');
		$context = "foreground";
		print "-- Fetched deshortify cache stats from background process\n" if $verbose;
	}

# 	$store->{deshortify_cache_misses} += ($store->{deshortify_cache_limit} * $store->{deshortify_cache_flushes});
# 	print $stdout "-- Deshortify cache stats (misses/hits/flushes): $store->{deshortify_cache_misses}/$store->{deshortify_cache_hit_count}/$store->{deshortify_cache_flushes}\n" if $verbose;
# 	sendbackgroundkey('deshortify_cache_misses', getbackgroundkey('deshortify_cache_misses') + (getbackgroundkey('deshortify_cache_limit') * getbackgroundkey('deshortify_cache_flushes'))  );

	print $stdout "-- Deshortify cache stats (misses/hits/flushes/context): $cache_hits/$cache_miss/$cache_flush/$context\n" if $verbose;

	return 0;
}










