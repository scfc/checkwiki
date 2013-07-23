#!/usr/bin/env perl

###########################################################################
##
##         FILE: translation.pl
##
##        USAGE: ./translation.pl -c checkwiki.cfg
##
##  DESCRIPTION: Updates translations and errors in the database
##
##       AUTHOR: Stefan Kühn, Bryan White 
##      LICENCE: GPLv3 
##      VERSION: 07/22/2013 10:06:16 PM
##
###########################################################################     

use strict;
use warnings;
use utf8;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use LWP::UserAgent;
use URI::Escape;

binmode( STDOUT, ":encoding(UTF-8)" );

our @Projects;
our $project;
our $Output_Directory = "translations";
our @error_description;
our $number_of_error_description;

our $top_priority_script     = 'Top priority';
our $top_priority_project    = q{};
our $middle_priority_script  = 'Middle priority';
our $middle_priority_project = q{};
our $lowest_priority_script  = 'Lowest priority';
our $lowest_priority_project = q{};

our $translation_file = 'translation.txt';
our $start_text;
our $description_text;
our $category_text;

#Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;
our $dbh;

my @Options = (
    'database|d=s' => \$DbName,
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
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    }
);

##########################################################################
## MAIN PROGRAM
##########################################################################

print '-' x 80;
print "\n";

open_db();
get_projects();

foreach (@Projects) {
    $project = $_;

    if ( $project ne 'enwiki' ) {
        two_column_display( 'Working on:', $project);
        get_error_description();
        load_text_translation();
        output_errors_desc_in_db();
        output_text_translation_wiki();
    }
}

close_db();

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError => 1,
            AutoCommit => 1
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

###########################################################################
## GET ERROR DESCRIPTION
###########################################################################

sub get_error_description {

    two_column_display( 'load:', 'all error description from script' );

    my $sql_text =
      "SELECT COUNT(*) FROM cw_error_desc WHERE project = 'enwiki';";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $number_of_error_description = $sth->fetchrow();

    $sql_text =
      "SELECT prio, name, text FROM cw_error_desc WHERE project = 'enwiki';";
    $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my @output;

    foreach my $i ( 1 .. $number_of_error_description ) {
        @output                   = $sth->fetchrow();
        $error_description[$i][0] = $output[0];
        $error_description[$i][1] = $output[1];
        $error_description[$i][2] = $output[2];
    }

    # set all known error description to a basic level
    foreach my $i ( 1 .. $number_of_error_description ) {
        $error_description[$i][3]  = 0;
        $error_description[$i][4]  = -1;
        $error_description[$i][5]  = '';
        $error_description[$i][6]  = '';
        $error_description[$i][7]  = 0;
        $error_description[$i][8]  = 0;
        $error_description[$i][9]  = '';
        $error_description[$i][10] = '';
    }

    two_column_display( '# of error descriptions:',
        $number_of_error_description . ' in script' );

    return ();
}

###########################################################################
### GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
############################################################################

sub get_projects {

    print "Load projects from db\n";
    my $result = q();
    my $sth = $dbh->prepare('SELECT project FROM cw_project ORDER BY project;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $project_counter = 0;
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {

        foreach (@$arrayref) {
            $result = $_;
        }

        push( @Projects, $result );
        $project_counter++;
    }

    return ();
}

##########################################################################
## LOAD TEXT TRANSLATION
##########################################################################

sub load_text_translation {

    my $translation_page;

    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'afwiki' );
    $translation_page = 'ﻮﻴﻜﻴﺒﻳﺪﻳﺍ:ﻒﺤﺻ_ﻮﻴﻜﻴﺒﻳﺪﻳﺍ/ﺕﺮﺠﻣﺓ'
      if ( $project eq 'arwiki' );
    $translation_page = 'Viquipèdia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'cawiki' );
    $translation_page = 'Wikipedie:WikiProjekt Check Wikipedia/Translation'
      if ( $project eq 'cswiki' );
    $translation_page = 'Commons:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'commonswiki' );
    $translation_page = 'Wicipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'cywiki' );
    $translation_page = 'Wikipedia:WikiProjekt Check Wikipedia/Oversættelse'
      if ( $project eq 'dawiki' );
    $translation_page = 'Wikipedia:WikiProjekt Syntaxkorrektur/Übersetzung'
      if ( $project eq 'dewiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'enwiki' );
    $translation_page = 'Projekto:Kontrolu Vikipedion/Tradukado'
      if ( $project eq 'eowiki' );
    $translation_page = 'Wikiproyecto:Check Wikipedia/Translation'
      if ( $project eq 'eswiki' );
    $translation_page = 'Wikipedia:Wikiprojekti Check Wikipedia/Translation'
      if ( $project eq 'fiwiki' );
    $translation_page = 'Projet:Correction syntaxique/Traduction'
      if ( $project eq 'frwiki' );
    $translation_page =
      'Meidogger:Stefan Kühn/WikiProject Check Wikipedia/Translation'
      if ( $project eq 'fywiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'hewiki' );
    $translation_page = 'Wikipédia:Ellenőrzőműhely/Fordítás'
      if ( $project eq 'huwiki' );
    $translation_page = 'Wikipedia:ProyekWiki Cek Wikipedia/Terjemahan'
      if ( $project eq 'idwiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'iswiki' );
    $translation_page = 'Wikipedia:WikiProjekt Check Wikipedia/Translation'
      if ( $project eq 'itwiki' );
    $translation_page =
      'プロジェクト:ウィキ文法のチェック/Translation'
      if ( $project eq 'jawiki' );
    $translation_page = 'Vicipaedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'lawiki' );
    $translation_page = 'Wikipedia:Wikiproject Check Wikipedia/Translation'
      if ( $project eq 'ndswiki' );
    $translation_page = 'Wikipedie:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'nds_nlwiki' );
    $translation_page = 'Wikipedia:Wikiproject/Check Wikipedia/Vertaling'
      if ( $project eq 'nlwiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'nowiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'pdcwiki' );
    $translation_page = 'Wikiprojekt:Check Wikipedia/Tłumaczenie'
      if ( $project eq 'plwiki' );
    $translation_page = 'Wikipedia:Projetos/Check Wikipedia/Tradução'
      if ( $project eq 'ptwiki' );
    $translation_page =
'Википедия:Страницы с ошибками в викитексте/Перевод'
      if ( $project eq 'ruwiki' );
    $translation_page = 'Wikipedia:WikiProject Check Wikipedia/Translation'
      if ( $project eq 'rowiki' );
    $translation_page = 'Wikipédia:WikiProjekt Check Wikipedia/Translation'
      if ( $project eq 'skwiki' );
    $translation_page = 'Wikipedia:Projekt wikifiering/Syntaxfel/Translation'
      if ( $project eq 'svwiki' );
    $translation_page = 'Vikipedi:Vikipedi proje kontrolü/Çeviri'
      if ( $project eq 'trwiki' );
    $translation_page =
      'Вікіпедія:Проект:Check Wikipedia/Translation'
      if ( $project eq 'ukwiki' );
    $translation_page =
      'װיקיפּעדיע:קאנטראלירן_בלעטער/Translation'
      if ( $project eq 'yiwiki' );
    $translation_page = '维基百科:错误检查专题/翻译'
      if ( $project eq 'zhwiki' );

    two_column_display( 'Translation input:', $translation_page);

    my $translation_input = raw_text($translation_page);
    $translation_input = replace_special_letters($translation_input);

    my $input_text = '';

    # start_text
    $input_text =
      get_translation_text( $translation_input, 'start_text_' . $project . '=',
        'END' );
    $start_text = $input_text if ( $input_text ne '' );

    # description_text
    $input_text = get_translation_text( $translation_input,
        'description_text_' . $project . '=', 'END' );
    $description_text = $input_text if ( $input_text ne '' );

    # category_text
    $input_text =
      get_translation_text( $translation_input, 'category_001=', 'END' );
    $category_text = $input_text if ( $input_text ne '' );

    # priority
    $input_text = get_translation_text( $translation_input,
        'top_priority_' . $project . '=', 'END' );
    $top_priority_project = $input_text if ( $input_text ne '' );
    $input_text = get_translation_text( $translation_input,
        'middle_priority_' . $project . '=', 'END' );
    $middle_priority_project = $input_text if ( $input_text ne '' );
    $input_text = get_translation_text( $translation_input,
        'lowest_priority_' . $project . '=', 'END' );
    $lowest_priority_project = $input_text if ( $input_text ne '' );

    # find error description
    foreach my $i ( 1 .. $number_of_error_description ) {
        my $current_error_number = 'error_';
        $current_error_number = $current_error_number . '0' if ( $i < 10 );
        $current_error_number = $current_error_number . '0' if ( $i < 100 );
        $current_error_number = $current_error_number . $i;

        # Priority
        $error_description[$i][4] = get_translation_text( $translation_input,
            $current_error_number . '_prio_' . $project . '=', 'END' );

        if ( $error_description[$i][4] ne '' ) {

            # if a translation was found
            $error_description[$i][4] = int( $error_description[$i][4] );
        }
        else {
            # if no translation was found
            $error_description[$i][4] = $error_description[$i][0];
        }

        if ( $error_description[$i][4] == -1 ) {

            # in project unkown then use prio from script
            $error_description[$i][4] = $error_description[$i][0];
        }

        $error_description[$i][5] = get_translation_text( $translation_input,
            $current_error_number . '_head_' . $project . '=', 'END' );
        $error_description[$i][6] = get_translation_text( $translation_input,
            $current_error_number . '_desc_' . $project . '=', 'END' );

    }

    return ();
}

###########################################################################
## OUTPUT ERROR DESCRIPTION TO DATABASE
###########################################################################

sub output_errors_desc_in_db {

    foreach my $i ( 1 .. $number_of_error_description ) {
        my $sql_headline = $error_description[$i][1];
        $sql_headline =~ s/'/\\'/g;
        my $sql_desc = $error_description[$i][2];
        $sql_desc =~ s/'/\\'/g;
        $sql_desc = substr( $sql_desc, 0, 3999 );
        my $sql_headline_trans = $error_description[$i][5];
        $sql_headline_trans =~ s/'/\\'/g;
        my $sql_desc_trans = $error_description[$i][6];
        $sql_desc_trans =~ s/'/\\'/g;
        $sql_desc = substr( $sql_desc_trans, 0, 3999 );

        # insert or update error
        my $sql_text = "UPDATE cw_error_desc
        SET prio=" . $error_description[$i][4] . ",
        name='" . $sql_headline . "' ,
        text='" . $sql_desc . "',
        name_trans='" . $sql_headline_trans . "' ,
        text_trans='" . $sql_desc_trans . "'
        WHERE id = " . $i . "
        AND project = '" . $project . "'
        ;";

        my $sth = $dbh->prepare($sql_text)
          || die "Can not prepare statement: $DBI::errstr\n";
        my $x = $sth->execute;

        if ( $x ne '1' ) {
            two_column_display( 'new error:', 'description insert into db' );
            $sql_text =
"INSERT INTO cw_error_desc (project, id, prio, name, text, name_trans, text_trans) VALUES ('"
              . $project . "', "
              . $i . ", "
              . $error_description[$i][4] . ", '"
              . $sql_headline . "' ,'"
              . $sql_desc . "','"
              . $sql_headline_trans . "' ,'"
              . $sql_desc_trans . "' );";
            $sth = $dbh->prepare($sql_text)
              || die "Can not prepare statement: $DBI::errstr\n";
            $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";
        }
    }

    return ();
}

###########################################################################
## GET TRANSLATION
###########################################################################

sub get_translation_text {
    my ( $translation_text, $start_tag, $end_tag ) = @_;

    my $pos_1 = index( $translation_text, $start_tag );
    my $pos_2 = index( $translation_text, $end_tag, $pos_1 );
    my $result = q{};

    if ( $pos_1 > -1 and $pos_2 > 0 ) {
        $result = substr( $translation_text, $pos_1, $pos_2 - $pos_1 );
        $result = substr( $result, index( $result, '=' ) + 1 );
        $result =~ s/^ //g;
        $result =~ s/ $//g;
    }

    return ($result);
}

###########################################################################
## OUTPUT TEXT TRANSLATION
###########################################################################

sub output_text_translation_wiki {

    my $filename = $Output_Directory . '/' . $project . '_' . $translation_file;
    two_column_display( 'Output translation text to:',
        $project . '_' . $translation_file );
    open( TRANSLATION, ">", $filename ) or die "unable to open: $!\n";

    print TRANSLATION '<pre>' . "\n";
    print TRANSLATION
      ' new translation text under http://toolserver.org/~sk/checkwiki/'
      . $project . '/'
      . " (updated daily) \n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# metadata' . "\n";
    print TRANSLATION '#########################' . "\n";

    print TRANSLATION ' project=' . $project . " END\n";
    print TRANSLATION ' category_001='
      . $category_text
      . " END  #for example: [[Category:Wikipedia]] \n";
    print TRANSLATION "\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# start text' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";
    print TRANSLATION ' start_text_' . $project . '=' . $start_text . " END\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# description' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";
    print TRANSLATION ' description_text_'
      . $project . '='
      . $description_text
      . " END\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# priority' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";

    print TRANSLATION ' top_priority_script=' . $top_priority_script . " END\n";
    print TRANSLATION ' top_priority_'
      . $project . '='
      . $top_priority_project
      . " END\n";
    print TRANSLATION ' middle_priority_script='
      . $middle_priority_script
      . " END\n";
    print TRANSLATION ' middle_priority_'
      . $project . '='
      . $middle_priority_project
      . " END\n";
    print TRANSLATION ' lowest_priority_script='
      . $lowest_priority_script
      . " END\n";
    print TRANSLATION ' lowest_priority_'
      . $project . '='
      . $lowest_priority_project
      . " END\n";
    print TRANSLATION "\n";
    print TRANSLATION " Please only translate the variables with …_"
      . $project
      . " at the end of the name. Not …_script= .\n";

    ################

    my $number_of_error_description_output = $number_of_error_description;
    two_column_display( 'error description:',
        $number_of_error_description_output . ' error description total' );

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# error description' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# prio = -1 (unknown)' . "\n";
    print TRANSLATION '# prio = 0  (deactivated) ' . "\n";
    print TRANSLATION '# prio = 1  (top priority)' . "\n";
    print TRANSLATION '# prio = 2  (middle priority)' . "\n";
    print TRANSLATION '# prio = 3  (lowest priority)' . "\n";
    print TRANSLATION "\n";

    foreach my $i ( 1 .. $number_of_error_description ) {

        my $current_error_number = 'error_';
        $current_error_number = $current_error_number . '0' if ( $i < 10 );
        $current_error_number = $current_error_number . '0' . $i
          if ( $i < 100 );
        print TRANSLATION ' '
          . $current_error_number
          . '_prio_script='
          . $error_description[$i][0]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_head_script='
          . $error_description[$i][1]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_desc_script='
          . $error_description[$i][2]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_prio_'
          . $project . '='
          . $error_description[$i][4]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_head_'
          . $project . '='
          . $error_description[$i][5]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_desc_'
          . $project . '='
          . $error_description[$i][6]
          . " END\n";
        print TRANSLATION "\n";
        print TRANSLATION
'###########################################################################'
          . "\n";
        print TRANSLATION "\n";
    }

    print TRANSLATION '</pre>' . "\n";
    close(TRANSLATION);

    return ();
}

###########################################################################
## REPLACE SPECIAL LETTERS
###########################################################################

sub replace_special_letters {
    my ($content) = @_;

    $content =~ s/&lt;/</g;
    $content =~ s/&gt;/>/g;
    $content =~ s/&quot;/"/g;
    $content =~ s/&#039;/'/g;
    $content =~ s/&amp;/&/g;

    return ($content);
}

##########################################################################
## TWO COLUMN DISPLAY
##########################################################################

sub two_column_display {
    my ( $text1, $text2 ) = @_;

    printf "%-30s %-30s\n", $text1, $text2;

    return ();
}

##########################################################################
## RAW TEXT
##########################################################################

sub raw_text {
    my ($title) = @_;

    $title =~ s/&amp;/%26/g;    # Problem with & in title
    $title =~ s/&#039;/'/g;     # Problem with apostroph in title
    $title =~ s/&lt;/</g;
    $title =~ s/&gt;/>/g;
    $title =~ s/&quot;/"/g;
    my $servername = $project;
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
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    my $url = $servername;

    $url =
        'http://'
      . $servername
      . '/w/api.php?action=query&prop=revisions&titles='
      . $title
      . '&rvprop=timestamp|content&format=xml';

    my $response2;
    uri_escape_utf8($url);

    my $ua2 = LWP::UserAgent->new;
    $response2 = $ua2->get($url);

    my $content2 = $response2->content;
    my $result2  = q{};
    if ($content2) {
       $result2 = $content2
    }

    return ($result2);
}
