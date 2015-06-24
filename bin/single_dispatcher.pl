#! /usr/bin/env perl

###########################################################################
##
##          FILE: single_dispatcher.pl 
##
##         USAGE: ./single_dispatch.pl
##
##   DESCRIPTION: Sends a checkwiki.pl job to the WMFLabs queue 
##
##        AUTHOR: Bryan White
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;
use utf8;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

##########################################################################
## MAIN PROGRAM
##########################################################################

my $language = 'enwiki';
my $dumpdate = '20150515';
my $filename = '/data/project/checkwiki/dumps/' . $language . '-' . $dumpdate . '-pages-articles.xml.bz2';

queueUp( $language, $dumpdate, $filename );

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $lang, $date, $file ) = @_;

    system(
        'jsub',
        '-j', 'y',
        '-mem', '512m',
        '-N', 'dumpmuncher-' . $lang,
        '-o', '/data/project/checkwiki/var/log',
        '-once',
        '/data/project/checkwiki/bin/checkwiki.pl',
        '-c', '/data/project/checkwiki/checkwiki.cfg',
        '-p', $lang,
        '--tt',
        '--dumpfile', $file,
    );

    print "jsub\n";
    print "-j, y\n";
    print "-mem, 512m\n";
    print '-N, dumpmuncher-' . $lang . "\n";
    print "-o, /data/project/checkwiki/var/log\n";
    print "-once\n";
    print "/data/project/checkwiki/bin/checkwiki.pl\n";
    print "-c, /data/project/checkwiki/checkwiki.cfg\n";
    print '-p,' . $lang . "\n";
    print "--tt\n";
    print '--dumpfile,' . $file . "\n";
}
