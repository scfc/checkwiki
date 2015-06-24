#! /usr/bin/env perl
#
############################################################################
###
### FILE:   live_scan.pl
### USAGE:  live_scan.pl -c database.cfg
###
### DESCRIPTION: Retrieves new revised articles from Wikipedia and stores
###              the articles in a database.  Checkwiki.pl can retrieve
###              the articles for processing.
###
### AUTHOR:  Bryan White
### Licence: GPL3
###
############################################################################

use strict;
use warnings;
use utf8;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

our $dbh->{'mysql_enable_utf8'} = 1;

our %Limit = ();
our @ProjectList;
our $Project = q{};
our @Titles;

open_db();
setVariables();

foreach (@ProjectList) {
    $Project = $_;
    retrieveArticles();
    insert_db();
    undef(@Titles);
}

close_db();

###########################################################################
###
############################################################################

sub setVariables {

    @ProjectList = qw(enwiki dewiki eswiki frwiki arwiki cswiki);

    %Limit = (
        enwiki => 500,
        dewiki => 300,
        eswiki => 300,
        frwiki => 300,
        arwiki => 200,
        cswiki => 200,
    );

    return ();
}

###########################################################################
##  RETRIVE ARTICLES FROM WIKIPEDIA
###########################################################################

sub retrieveArticles {
    my $page_namespace = 0;

    # Calculate server name.
    my $servername = $Project;
    if (
        !(
               $servername =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $servername =~ s/^commonswiki$/commons.wikimedia.org/
            || $servername =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $servername =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $servername =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $servername =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $Project . "\n" );
    }

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'http',
            host     => $servername,
        }
    );

    my @rc = $bot->recentchanges(
        { ns => $page_namespace, limit => $Limit{$Project} } );
    foreach my $hashref (@rc) {
        push( @Titles, $hashref->{title} );
    }

    return ();
}

###########################################################################
## INSERT THE ARTICLE'S TITLES INTO DATABASE
###########################################################################

sub insert_db {
    my $title = q{};
    my $null  = undef;

    foreach (@Titles) {
        $title = $_;

        #problem: sql-command insert, apostrophe ' or backslash \ in text
        $title =~ s/\\/\\\\/g;
        $title =~ s/'/\\'/g;

        my $sql_text =
            "INSERT IGNORE INTO cw_new (Project, Title) VALUES ('"
          . $Project . "', '"
          . $title . "');";

        my $sth = $dbh->prepare($sql_text)
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";
    }

    return ();
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {
    my $DbName     = q{};
    my $DbServer   = q{};
    my $DbUsername = q{};
    my $DbPassword = q{};

    my @Options = (
        'database|D=s' => \$DbName,
        'host|h=s'     => \$DbServer,
        'password=s'   => \$DbPassword,
        'user|u=s'     => \$DbUsername,
    );

    GetOptions(
        'c=s' => sub {
            my $f = IO::File->new( $_[1], '<:encoding(UTF-8)' )
              or die( "Can't open " . $_[1] . "\n" );
            local ($/);
            my $s = <$f>;
            $f->close();
            my ( $Success, $RemainingArgs ) =
              GetOptionsFromString( $s, @Options );
            die unless ( $Success && !@$RemainingArgs );
        },
        @Options
    );

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError => 1,
            AutoCommit => 1,
            mysql_enable_utf8 => 1,
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}
