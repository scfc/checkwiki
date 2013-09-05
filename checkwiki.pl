#! /usr/bin/env perl

###########################################################################
##
##          FILE: checkwiki.pl
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg --project=<enwiki>
##                --load <live, dump, delay> --dumpfile --tt-file
##
##   DESCRIPTION: Scan Wikipedia articles for errors.
##
##        AUTHOR: Stefan Kühn, Bryan White
##       LICENCE: GPLv3
##       VERSION: 07/23/2013
##
###########################################################################

use strict;
use warnings;

use lib '/data/project/checkwiki/share/perl';
use MediaWiki::DumpFile;
use DBI;
use File::Temp;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use LWP::UserAgent;
use MediaWiki::DumpFile::Compat;
use POSIX qw(strftime);
use URI::Escape;

use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

our $dump_or_live = q{};    # Scan modus (dump, live, delay)

our $CheckOnlyOne = 0;      # Check only one error or all errors

our $ServerName  = q{};     # Address where api can be found
our $project     = q{};     # Name of the project 'dewiki'
our $language    = q{};     # Language of dump 'de', 'en';
our $home        = q{};     # Base of article, 'http://de.wikipedia.org/wiki/'
our $end_of_dump = q{};     # When last article from dump reached
our $artcount    = 0;       # Number of articles processed
our $file_size   = 0;       # How many MB of the dump has been processed.

# Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;

our $dbh;

# MediaWiki::DumpFile variables
our $pmwd  = Parse::MediaWikiDump->new;
our $pages = q{};

# Time program starts
our $time_start = time();    # Start timer in secound
our $time_end   = time();    # End time in secound
our $time_found = time();    # For column "Found" in cw_error

# File name
our $TTFile;

##############################
##  Wiki-special variables
##############################

our @namespace;              # Namespace values
                             # 0 number
                             # 1 namespace in project language
                             # 2 namespace in english language

our @namespacealiases;       # Namespacealiases values
                             # 0 number
                             # 1 namespacealias

our @namespace_cat;          # All namespaces for categorys
our @namespace_image;        # All namespaces for images
our @namespace_templates;    # All namespaces for templates
our $image_regex = q{};      # Regex used in get_images()
our $cat_regex   = q{};      # Regex used in get_categories()

our $magicword_defaultsort;

our @magicword_img_thumbnail;
our @magicword_img_manualthumb;
our @magicword_img_right;
our @magicword_img_left;
our @magicword_img_none;
our @magicword_img_center;
our @magicword_img_framed;
our @magicword_img_frameless;
our @magicword_img_page;
our @magicword_img_upright;
our @magicword_img_border;
our @magicword_img_sub;
our @magicword_img_super;
our @magicword_img_link;
our @magicword_img_alt;
our @magicword_img_width;
our @magicword_img_baseline;
our @magicword_img_top;
our @magicword_img_text_top;
our @magicword_img_middle;
our @magicword_img_bottom;
our @magicword_img_text_bottom;

our $error_counter = -1;    # Number of found errors in all article
our @ErrorPriorityValue;    # Priority value each error has

our @Error_number_counter = (0) x 150;    # Error counter for individual errors

our $number_of_all_errors_in_all_articles = 0;

our @inter_list = qw( af  als an  ar  bg  bs  ca  cs  cy  da  de
  el  en  eo  es  et  eu  fa  fi  fr  fy  fl  gv
  he  hi  hr  hu  id  is  it  ja  jv  ka  ko
  la  lb  lt  ms  nds nl  nn  no  pl  pt  ro  ru
  sh  sk  sl  sr  sv  sw  ta  th  tr  uk  ur  vi
  simple  nds_nl );

our @foundation_projects = qw( b  n  s  v  m  q  w  meta  mw  nost  wikt  wmf
  bugzilla   commons     foundation incubator
  meta-wiki  quality     speciesi   testwiki
  wikibooks  wikidata    wikimedia  wikinews
  wikiquote  wikipedia   wikisource wikispecies
  wiktionary wikiversity wikivoyage );

###############################
## Variables for one article
###############################

our $title                 = q{};    # Title of the current article
our $text                  = q{};    # Text of the current article
our $text_without_comments = q{};

# Text of article with comments only removed

our $page_namespace;                 # Namespace of page
our $page_is_redirect       = 'no';
our $page_is_disambiguation = 'no';

our $category_counter = -1;
our $category_all     = q{};         # All categries

our @category;                       # 0 pos_start
                                     # 1 pos_end
                                     # 2 category	Test
                                     # 3 linkname	Linkname
                                     # 4 original	[[Category:Test|Linkname]]

our @interwiki;                      # 0 pos_start
                                     # 1 pos_end
                                     # 2 interwiki	Test
                                     # 3 linkname	Linkname
                                     # 4 original	[[de:Test|Linkname]]
                                     # 5 language

our $interwiki_counter = -1;

our @templates_all;                  # All templates
our @template;                       # Templates with values
                                     # 0 number of template
                                     # 1 templatename
                                     # 2 template_row
                                     # 3 attribut
                                     # 4 value

our $number_of_template_parts = -1;  # Number of all template parts

our @links_all;                      # All links
our @images_all;                     # All images
our @isbn;                           # All ibsn of books
our @ref;                            # All ref
our @headlines;                      # All headlines
our @section;                        # Text between headlines
our @lines;                          # Text seperated in lines

###########################################################################
###########################################################################

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
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

###########################################################################
## DELETE OLD LIST OF ARTICLES FROM LAST DUMP SCAN IN TABLE cw_dumpscan
###########################################################################

sub clearDumpscanTable {

    my $sth = $dbh->prepare('DELETE FROM cw_dumpscan WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
## UPDATE DATE OF LAST DUMP IN DATABASE FOR PROJECT GIVEN
###########################################################################

sub updateDumpDate {
    my ($date) = @_;

    my $sql_text =
        "UPDATE cw_project SET Last_Dump = '"
      . $date
      . "' WHERE Project = '"
      . $project . "';";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
##
###########################################################################

sub scan_pages {

    print_line();

    $end_of_dump = 'no';
    my $page = q{};

    if ( $dump_or_live eq 'dump' ) {
        while ( defined( $page = $pages->next ) && $end_of_dump eq 'no' ) {
            next unless $page->namespace eq '';
            update_ui() if ++$artcount % 500 == 0;
            set_variables_for_article();
            $page_namespace = 0;
            $title          = $page->title;
            $title          = case_fixer($title);
            $text           = ${ $page->text };
            check_article();

            #$end_of_dump = 'yes' if ( $artcount > 10000 );
            #$end_of_dump = 'yes' if ( $error_counter > 40000 )
        }
    }
    elsif ( $dump_or_live eq 'live' ) {
        live_scan();
    }
    elsif ( $dump_or_live eq 'delay' ) {
        delay_scan();
    }
    else {
        die("Wrong Load_mode entered \n");
    }

    return ();
}

###########################################################################
##
###########################################################################

sub update_ui {
    my $bytes   = $pages->current_byte;
    my $percent = int( $bytes / $file_size * 100 );

    printf( "   %7d articles;%10s processed;%3d%% completed\n",
        ( $artcount, pretty_bytes($bytes), $percent ) );

    return ();
}

###########################################################################
###
###########################################################################

sub pretty_number {
    my $number = reverse(shift);
    $number =~ s/(...)/$1,/g;
    $number = reverse($number);
    $number =~ s/^,//;

    return $number;

}

###########################################################################
###
##########################################################################

sub pretty_bytes {
    my ($bytes) = @_;
    my $pretty = int($bytes) . ' bytes';

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = int($bytes) . ' KB';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( "%7.2f", $bytes ) . ' MB';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( "%0.3f", $bytes ) . ' GB';
    }

    return ($pretty);
}

###########################################################################
###
###########################################################################

sub case_fixer {
    my ($my_title) = @_;

    #check for namespace
    if ( $my_title =~ /^(.+?):(.+)/ ) {
        $my_title = $1 . ':' . ucfirst($2);
    }
    else {
        $my_title = ucfirst($title);
    }

    return ($my_title);
}

###########################################################################
## RESET VARIABLES BEFORE SCANNING A NEW ARTICLE
###########################################################################

sub set_variables_for_article {
    $title = q{};    # title of the current article
    $text  = q{};    # text of the current article  (for work)

    $page_is_redirect       = 'no';
    $page_is_disambiguation = 'no';

    undef(@category);    # 0 pos_start
                         # 1 pos_end
                         # 2 category	Test
                         # 3 linkname	Linkname
                         # 4 original	[[Category:Test|Linkname]]

    $category_counter = -1;
    $category_all     = q{};    # All categries

    undef(@interwiki);          # 0 pos_start
                                # 1 pos_end
                                # 2 interwiki	Test
                                # 3 linkname	Linkname
                                # 4 original	[[de:Test|Linkname]]
                                # 5 language

    $interwiki_counter = -1;

    undef(@lines);              # Text seperated in lines
    undef(@headlines);          # Headlines
    undef(@section);            # Text between headlines

    undef(@templates_all);      # All templates
    undef(@template);           # Templates with values
                                # 0 number of template
                                # 1 templatename
                                # 2 template_row
                                # 3 attribut
                                # 4 value
    $number_of_template_parts = -1;    # Number of all template parts

    undef(@links_all);                 # All links
    undef(@images_all);                # All images
    undef(@isbn);                      # All ibsn of books
    undef(@ref);                       # All ref

    return ();
}

###########################################################################
## MOVE ARTICLES FROM cw_dumpscan INTO cw_error
###########################################################################

sub update_table_cw_error_from_dump {

    if ( $dump_or_live eq 'dump' ) {

        my $sth = $dbh->prepare('DELETE FROM cw_error WHERE Project = ?;')
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

        $sth = $dbh->prepare(
'INSERT INTO cw_error (SELECT * FROM cw_dumpscan WHERE Project = ?);'
        ) || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    }

    return ();
}

###########################################################################
## DELETE "DONE" ARTICLES FROM DB
###########################################################################

sub delete_done_article_from_db {

    my $sth =
      $dbh->prepare('DELETE FROM cw_error WHERE ok = 1 and project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

###########################################################################
## GET @ErrorPriorityValue
###########################################################################

sub getErrors {
    my $error_count                 = 0;
    my $number_of_error_description = 0;

    my $sth =
      $dbh->prepare('SELECT COUNT(*) FROM cw_error_desc WHERE project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    $number_of_error_description = $sth->fetchrow();

    $sth = $dbh->prepare('SELECT prio FROM cw_error_desc WHERE project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    foreach my $i ( 1 .. $number_of_error_description ) {
        $ErrorPriorityValue[$i] = $sth->fetchrow();
        if ( $ErrorPriorityValue[$i] > 0 ) {
            $error_count++;
        }
    }

    two_column_display( 'Total # of errors possible:',
        $number_of_error_description );
    two_column_display( 'Number of errors to process:', $error_count );

    return ();
}

###########################################################################
##  Read Metadata from API
###########################################################################

sub readMetadata {

    $ServerName = $project;
    if (
        !(
               $ServerName =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $ServerName =~ s/^commonswiki$/commons.wikimedia.org/
            || $ServerName =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $ServerName =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $ServerName =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $ServerName =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    my $url = 'http://' . $ServerName . '/w/api.php';

    print_line();
    two_column_display( 'Load metadata from:', $url );

    # Setup MediaWiki::API
    my $mw = MediaWiki::API->new();
    $mw->{config}->{api_url} = $url;

    # See https://www.mediawiki.org/wiki/API:Meta#siteinfo_/_si
    my $res = $mw->api(
        {
            action => 'query',
            meta   => 'siteinfo',
            siprop =>
              'general|namespaces|namespacealiases|statistics|magicwords',
        }
    ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details} . "\n";

    two_column_display( 'Sitename:', $res->{query}->{general}->{sitename} );

    $home = $res->{query}->{general}->{base};
    two_column_display( 'Base:', $home );
    $home =~ s/[^\/]+$//;

    two_column_display( 'Pages online:', $res->{query}->{statistics}->{pages} );
    two_column_display( 'Images online:',
        $res->{query}->{statistics}->{images} );

    foreach my $id ( keys %{ $res->{query}->{namespaces} } ) {
        my $name      = $res->{query}->{namespaces}->{$id}->{'*'};
        my $canonical = $res->{query}->{namespaces}->{$id}->{'canonical'};
        push( @namespace, [ $id, $name, $canonical ] );

        # Store special namespaces in convenient variables.
        if ( $id == 6 ) {
            @namespace_image = ( $name, $canonical );
            $image_regex = $name;
        }
        elsif ( $id == 10 ) {
            @namespace_templates = ($name);
            push( @namespace_templates, $canonical ) if ( $name ne $canonical );
        }
        elsif ( $id == 14 ) {
            @namespace_cat = ($name);
            $cat_regex     = $name;
            push( @namespace_cat, $canonical ) if ( $name ne $canonical );
            $cat_regex = $name . "|" . $canonical if ( $name ne $canonical );
        }
    }

    foreach my $entry ( @{ $res->{query}->{namespacealiases} } ) {
        my $name = $entry->{'*'};
        if ( $entry->{id} == 6 ) {
            push( @namespace_image, $name );
            $image_regex = $image_regex . "|" . $name;
        }
        elsif ( $entry->{id} == 10 ) {
            push( @namespace_templates, $name );
        }
        elsif ( $entry->{id} == 14 ) {
            push( @namespace_cat, $name );
            $cat_regex = $cat_regex . "|" . $name;
        }

        # Store all aliases.
        push( @namespacealiases, [ $entry->{id}, $name ] );
    }

    foreach my $id ( @{ $res->{query}->{magicwords} } ) {
        my $aliases = $id->{aliases};
        my $name    = $id->{name};
        $magicword_defaultsort     = $aliases if ( $name eq 'defaultsort' );
        @magicword_img_thumbnail   = $aliases if ( $name eq 'img_thumbnail' );
        @magicword_img_manualthumb = $aliases if ( $name eq 'img_manualthumb' );
        @magicword_img_right       = $aliases if ( $name eq 'img_right' );
        @magicword_img_left        = $aliases if ( $name eq 'img_left' );
        @magicword_img_none        = $aliases if ( $name eq 'img_none' );
        @magicword_img_center      = $aliases if ( $name eq 'img_center' );
        @magicword_img_framed      = $aliases if ( $name eq 'img_framed' );
        @magicword_img_frameless   = $aliases if ( $name eq 'img_frameless' );
        @magicword_img_page        = $aliases if ( $name eq 'img_page' );
        @magicword_img_upright     = $aliases if ( $name eq 'img_upright' );
        @magicword_img_border      = $aliases if ( $name eq 'img_border' );
        @magicword_img_sub         = $aliases if ( $name eq 'img_sub' );
        @magicword_img_super       = $aliases if ( $name eq 'img_super' );
        @magicword_img_link        = $aliases if ( $name eq 'img_link' );
        @magicword_img_alt         = $aliases if ( $name eq 'img_alt' );
        @magicword_img_width       = $aliases if ( $name eq 'img_width' );
        @magicword_img_baseline    = $aliases if ( $name eq 'img_baseline' );
        @magicword_img_top         = $aliases if ( $name eq 'img_top' );
        @magicword_img_text_top    = $aliases if ( $name eq 'img_text_top' );
        @magicword_img_middle      = $aliases if ( $name eq 'img_middle' );
        @magicword_img_bottom      = $aliases if ( $name eq 'img_bottom' );
        @magicword_img_text_bottom = $aliases if ( $name eq 'img_text_bottom' );
    }

    return ();
}

###########################################################################
## CHECK ARTICLES VIA A LIVE SCAN
###########################################################################

sub live_scan {

    my @live_titles;
    my $limit = 500;    # 500 is the max mediawiki allows
    $page_namespace = 0;

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'http',
            host     => $ServerName,
        }
    );

    my @rc = $bot->recentchanges( { ns => $page_namespace, limit => $limit } );
    foreach my $hashref (@rc) {
        push( @live_titles, $hashref->{title} );
    }

    foreach (@live_titles) {
        set_variables_for_article();
        $title = $_;
        $text  = $bot->get_text($title);
        if ( defined($text) ) {
            check_article();
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub delay_scan {

    my @title_array;
    my $title_sql;
    $page_namespace = 0;

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'http',
            host     => $ServerName,
        }
    );

    # Get titles gathered from live_scan.pl
    my $sth = $dbh->prepare('SELECT Title FROM cw_new WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    $sth->bind_col( 1, \$title_sql );
    while ( $sth->fetchrow_arrayref ) {
        push( @title_array, $title_sql );
    }

    # Remove the articles. live_scan.pl is continuously adding new article.
    # So, need to remove before doing anything else.
    $sth = $dbh->prepare('DELETE FROM cw_new WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    foreach (@title_array) {
        set_variables_for_article();
        $title = $_;
        $text  = $bot->get_text($title);
        printf( "  %7d articles done\n", $artcount ) if ++$artcount % 500 == 0;
        if ( defined($text) ) {    # Article may have been deleted
            check_article();
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_article {

    my $text_for_tests = "";

    # $text = $text_for_tests;

    delete_old_errors_in_db();

    #------------------------------------------------------
    # Following alters text and must be run first
    #------------------------------------------------------

    # REMOVES FROM $text ANY CONTENT BETWEEN <!-- --> TAGS.
    # CALLS #05
    get_comments();

    # REMOVES FROM $text ANY CONTENT BETWEEN <nowiki> </nowiki> TAGS.
    # CALLS #23
    get_nowiki();

    # REMOVES FROM $text ANY CONTENT BETWEEN <pre> </pre> TAGS.
    # CALLS #24
    get_pre();

    # REMOVES FROM $text ANY CONTENT BETWEEN <math> </math> TAGS.
    # CALLS #013
    get_math();

    # REMOVES FROM $text ANY CONTENT BETWEEN <source> </sources TAGS.
    # CALLS #014
    get_source();

    # REMOVES FROM $text ANY CONTENT BETWEEN <code> </code> TAGS.
    # CALLS #15
    get_code();

    # REMOVE FROM $text ANY CONTENT BETWEEN <syntaxhighlight> TAGS.
    get_syntaxhighlight();

    # REMOVE FROM $text ANY CONTENT BETWEEN <hiero> TAGS.
    get_hiero();

    #------------------------------------------------------
    # Following calls do not interact with other get_* or error #'s
    #------------------------------------------------------

    # CALLS #29 and #25
    get_gallery();

    # CALLS #28
    get_tables();

    # CALLS #69, #70, #71, #72 ISBN CHECKS
    get_isbn();

    #------------------------------------------------------
    # Following interacts with other get_* or error #'s
    #------------------------------------------------------

    # CREATES @ref - USED IN #81
    #get_ref();

    # CREATES @templates_all - USED IN #12, #31
    # CALLS #43
    get_templates_all();

    # DOES TEMPLATETIGER
    # USES @templates_all
    # CREATES @template - USED IN #59, #60
    get_template();

    # CREATES @links_all & @images_all - USED IN #68, #74, #76, #82
    # CALLS #10
    get_links();

    # USES @images_all - USED IN #65, #66, #67
    # CALLS #30
    get_images();

    # SETS $page_is_redirect
    check_for_redirect();

    # CREATES @category - USED IN #17, #18, #21, #22, #37, #53, #91
    get_categories();

    # CREATES @interwiki - USED IN #45, #51, #53
    get_interwikis();

    # CREATES @lines
    # USED IN #02, #09, #26, #32, #34, #38, #39, #40-#42, #54,  #75
    create_line_array();

    # CREATES @headlines
    # USES @lines
    # USED IN #07, #08, #25, #44, #51, #52, #57, #58, #62, #83, #84, #92
    get_headlines();

    # EXCEPT FOR get_* THAT REMOVES TAGS FROM $text, FOLLOWING DON'T NEED
    # TO BE PROCESSED BY ANY get_* ROUTINES: 3-6, 11, 13-16, 19, 20, 23, 24,
    # 27, 35, 36, 43, 46-50, 54-56, 59-61, 63-74, 76-80, 82, 84-90
    error_check();

    return ();
}

###########################################################################
## DELETE ARTICLE IN DATABASE
###########################################################################

sub delete_old_errors_in_db {
    if ( $dump_or_live eq 'live' && $title ne '' ) {
        my $sth =
          $dbh->prepare('DELETE FROM cw_error WHERE Title = ? AND Project = ?;')
          || die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $title, $project )
          or die "Cannot execute: " . $sth->errstr . "\n";
    }

    return ();
}

###########################################################################
## FIND MISSING COMMENTS TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_comments {
    my $test_text = lc($text);

    if ( $test_text =~ /<!--/ ) {
        my $comments_begin = 0;
        my $comments_end   = 0;

        $comments_begin = () = $test_text =~ /<!--/g;
        $comments_end   = () = $test_text =~ /-->/g;

        if ( $comments_begin > $comments_end ) {
            my $snippet = get_broken_tag( '<!--', '-->' );
            error_005_Comment_no_correct_end($snippet);
        }

        $text =~ s/<!--(.*?)-->//sg;
    }
    $text_without_comments = $text;

    return ();
}

###########################################################################
## FIND MISSING NOWIKI TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_nowiki {
    my $test_text = lc($text);

    if ( $test_text =~ /<nowiki>/ ) {
        my $nowiki_begin = 0;
        my $nowiki_end   = 0;

        $nowiki_begin = () = $test_text =~ /<math/g;
        $nowiki_end   = () = $test_text =~ /<\/math>/g;

        if ( $nowiki_begin > $nowiki_end ) {
            my $snippet = get_broken_tag( '<nowiki>', '</nowiki>' );
            error_023_nowiki_no_correct_end($snippet);
        }

        $text =~ s/<nowiki>(.*?)<\/nowiki>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING PRE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_pre {
    my $test_text = lc($text);

    if ( $test_text =~ /<pre>/ ) {
        my $pre_begin = 0;
        my $pre_end   = 0;

        $pre_begin = () = $test_text =~ /<pre>/g;
        $pre_end   = () = $test_text =~ /<\/pre>/g;

        if ( $pre_begin > $pre_end ) {
            my $snippet = get_broken_tag( '<pre>', '</pre>' );
            error_024_pre_no_correct_end($snippet);
        }

        $text =~ s/<pre>(.*?)<\/pre>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING MATH TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_math {
    my $test_text = lc($text);

    if ( $test_text =~ /<math>|<math style|<math title|<math alt/ ) {
        my $math_begin = 0;
        my $math_end   = 0;

        $math_begin = () = $test_text =~ /<math/g;
        $math_end   = () = $test_text =~ /<\/math>/g;

        if ( $math_begin > $math_end ) {
            my $snippet = get_broken_tag( '<math', '</math>' );
            error_013_Math_no_correct_end($snippet);
        }

        $text =~ s/<math(.*?)<\/math>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING SOURCE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_source {
    my $test_text = lc($text);

    if ( $test_text =~ /<source/ ) {
        my $source_begin = 0;
        my $source_end   = 0;

        $source_begin = () = $test_text =~ /<source/g;
        $source_end   = () = $test_text =~ /<\/source>/g;

        if ( $source_begin > $source_end ) {
            my $snippet = get_broken_tag( '<source', '</source>' );
            error_014_Source_no_correct_end($snippet);
        }

        $text =~ s/<source(.*?)<\/source>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING CODE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_code {
    my $test_text = lc($text);

    if ( $test_text =~ /<code>/ ) {
        my $code_begin = 0;
        my $code_end   = 0;

        $code_begin = () = $test_text =~ /<code>/g;
        $code_end   = () = $test_text =~ /<\/code>/g;

        if ( $code_begin > $code_end ) {
            my $snippet = get_broken_tag( '<code>', '</code>' );
            error_015_Code_no_correct_end($snippet);
        }

        $text =~ s/<code>(.*?)<\/code>//sg;
    }

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE SYNTAXHIGHLIGHT TAGS
###########################################################################

sub get_syntaxhighlight {

    $text =~ s/<syntaxhighlight(.*?)<\/syntaxhighlight>//sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE HIERO TAGS
###########################################################################

sub get_hiero {

    $text =~ s/<hiero>(.*?)<\/hiero>//sg;

    return ();
}

###########################################################################
## FIND MISSING GALLERY TAGS
###########################################################################

sub get_gallery {

    my $test_text = lc($text);

    if ( $test_text =~ /<gallery/ ) {
        my $gallery_begin = 0;
        my $gallery_end   = 0;

        $gallery_begin = () = $test_text =~ /<gallery/g;
        $gallery_end   = () = $test_text =~ /<\/gallery>/g;

        if ( $gallery_begin > $gallery_end ) {
            my $snippet = get_broken_tag( '<gallery', '</gallery>' );
            error_029_gallery_no_correct_end($snippet);
        }
    }

    return ();
}

###########################################################################
## GET TABLES
###########################################################################

sub get_tables {

    my $test_text = $text;

    my $tag_open_num  = () = $test_text =~ /\{\|/g;
    my $tag_close_num = () = $test_text =~ /\|\}/g;

    my $diff = $tag_open_num - $tag_close_num;

    if ( $diff > 0 ) {

        my $pos_start        = 0;
        my $pos_end          = 0;
        my $look_ahead_open  = 0;
        my $look_ahead_close = 0;
        my $look_ahead       = 0;

        my $pos_open  = index( $test_text, '{|' );
        my $pos_open2 = index( $test_text, '{|', $pos_open + 2 );
        my $pos_close = index( $test_text, '|}' );
        while ( $diff > 0 ) {
            if ( $pos_open2 == -1 ) {
                error_028_table_no_correct_end(
                    substr( $text, $pos_open, 40 ) );
                $diff = -1;
            }
            elsif ( $pos_open2 < $pos_close and $look_ahead > 0 ) {
                error_028_table_no_correct_end(
                    substr( $text, $pos_open, 40 ) );
                $diff--;
            }
            else {
                $pos_open  = $pos_open2;
                $pos_open2 = index( $test_text, '{|', $pos_open + 2 );
                $pos_close = index( $test_text, '|}', $pos_close + 2 );
                if ( $pos_open2 > 0 ) {
                    $look_ahead_open =
                      index( $test_text, '{|', $pos_open2 + 2 );
                    $look_ahead_close =
                      index( $test_text, '|}', $pos_close + 2 );
                    $look_ahead = $look_ahead_close - $look_ahead_open;
                }
            }
        }
    }

    return ();
}

###########################################################################
## GET ISBN
###########################################################################

sub get_isbn {

    if (
            index( $text, 'ISBN' ) > 0
        and $title ne 'International Standard Book Number'
        and $title ne 'ISBN'
        and $title ne 'ISBN-10'
        and $title ne 'ISBN-13'
        and $title ne 'Internationaal Standaard Boeknummer'
        and $title ne 'International Standard Book Number'
        and $title ne 'European Article Number'
        and $title ne 'Internationale Standardbuchnummer'
        and $title ne 'Buchland'
        and $title ne 'Codice ISBN'
        and index( $title, 'ISBN' ) == -1

      )
    {
        my $text_test = $text;

        while ( $text_test =~ /ISBN([ ]|[-]|[=])/g ) {
            my $pos_start = pos($text_test) - 5;

            my $current_isbn = substr( $text_test, $pos_start );
            my $output_isbn = substr( $current_isbn, 0, 50 );
            $output_isbn =~ s/\n/ /g;

            my $result_isbn = q{};
            my $i           = -1;
            my $finish      = 'no';

            $current_isbn =~ s/\t/ /;

            if ( $current_isbn =~ /^([ ]+)?ISBN=([ ]+)?/ ) {

                # ISBN = 01234566 in templates
                $current_isbn =~ s/^([ ]+)?ISBN([ ]+)?=([ ]+)?/ /;

                #if ( length($current_isbn ) == 10

                my $pos_open  = index( $current_isbn, '[' );
                my $pos_close = index( $current_isbn, ']' );

                if (
                    ( $pos_open == -1 and $pos_close > -1 )
                    or (    $pos_open > -1
                        and $pos_close > -1
                        and $pos_open > $pos_close )
                  )
                {
                    $current_isbn = 'ISBN';
                }
            }

            if ( $current_isbn =~ /^([ ]+)?ISBN-[^1]/ ) {

                # text "ISBN-number"
                # text "ISBN-bureau"
                $current_isbn = 'ISBN';
            }

            my $pos_next_ISBN = index( $current_isbn, 'ISBN', 4 );
            if ( $pos_next_ISBN > -1 ) {
                $current_isbn = substr( $current_isbn, 0, $pos_next_ISBN );
            }
            $current_isbn =~ s/ISBN//g;

            do {
                $i++;
                if ( $i <= length($current_isbn) ) {
                    my $character = substr( $current_isbn, $i, 1 );
                    if ( $character =~ /[ 0-9Xx\-]/ ) {
                        $result_isbn = $result_isbn . $character;
                    }
                    else {
                        $finish = 'yes';
                    }
                }
                else {
                    $finish = 'yes';
                }

            } until ( $finish eq 'yes' );

            if (    $result_isbn =~ /[^ ]/
                and $result_isbn =~ /[0-9]/ )
            {
                $result_isbn =~ s/^([ ]+)?//g;
                $result_isbn =~ s/([ ]+)?$//g;

                push( @isbn, $result_isbn );
                check_isbn($result_isbn);
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_isbn {
    my ($current_isbn) = @_;

    my $test_isbn = $current_isbn;

    $test_isbn =~ s/^([ ]+)?//g;
    $test_isbn =~ s/([ ]+)?$//g;
    $test_isbn =~ s/[ ]//g;

    my $result = 'yes';

    # Length of isbn
    if ( $result eq 'yes' ) {
        if (   index( $test_isbn, '-10' ) == 0
            or index( $test_isbn, '-13' ) == 0 )
        {
            $result = 'no';
            error_069_isbn_wrong_syntax($current_isbn);
        }
    }

    $test_isbn =~ s/-//g;

    # Wrong position of X
    if ( $result eq 'yes' ) {
        $test_isbn =~ s/x/X/g;
        if ( index( $test_isbn, 'X' ) > -1 ) {

            # ISBN with X
            if ( index( $test_isbn, 'X' ) != 9 ) {

                # ISBN 123456X890
                $result = 'no';
                error_071_isbn_wrong_pos_X($current_isbn);
            }
            if ( index( $test_isbn, 'X' ) == 9
                and ( length($test_isbn) != 10 ) )
            {
                # ISBN 123451678XXXX b
                $test_isbn = substr( $test_isbn, 0, 10 );
            }
        }
    }

    my $check_10      = 'no ok';
    my $check_13      = 'no ok';
    my $found_text_10 = q{};
    my $found_text_13 = q{};

    # Check Checksum 13
    if ( $result eq 'yes' ) {
        if ( length($test_isbn) >= 13
            and $test_isbn =~ /^[0-9]{13}/ )
        {
            my $checksum = 0;
            $checksum = $checksum + 1 * substr( $test_isbn, 0,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 1,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 2,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 3,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 4,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 5,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 6,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 7,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 8,  1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 9,  1 );
            $checksum = $checksum + 1 * substr( $test_isbn, 10, 1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 11, 1 );

            my $checker = 10 - substr( $checksum, length($checksum) - 1, 1 );
            $checker = 0 if ( $checker == 10 );

            if ( $checker eq substr( $test_isbn, 12, 1 ) ) {
                $check_13 = 'ok';
            }
            else {
                $found_text_13 =
                    $current_isbn
                  . substr( $test_isbn, 12, 1 ) . ' vs. '
                  . $checker;
            }
        }
    }

    # Check Checksum 10
    if ( $result eq 'yes' ) {
        if (    length($test_isbn) >= 10
            and $test_isbn =~ /^[0-9X]{10}/
            and $check_13 eq 'no ok' )
        {
            my $checksum = 0;
            $checksum = $checksum + 1 * substr( $test_isbn, 0, 1 );
            $checksum = $checksum + 2 * substr( $test_isbn, 1, 1 );
            $checksum = $checksum + 3 * substr( $test_isbn, 2, 1 );
            $checksum = $checksum + 4 * substr( $test_isbn, 3, 1 );
            $checksum = $checksum + 5 * substr( $test_isbn, 4, 1 );
            $checksum = $checksum + 6 * substr( $test_isbn, 5, 1 );
            $checksum = $checksum + 7 * substr( $test_isbn, 6, 1 );
            $checksum = $checksum + 8 * substr( $test_isbn, 7, 1 );
            $checksum = $checksum + 9 * substr( $test_isbn, 8, 1 );

            my $checker = $checksum % 11;

            if (   ( $checker < 10 and $checker ne substr( $test_isbn, 9, 1 ) )
                or ( $checker == 10 and 'X' ne substr( $test_isbn, 9, 1 ) ) )
            {
                # Check wrong and 10 or more characters
                $found_text_10 =
                    $current_isbn
                  . substr( $test_isbn, 9, 1 ) . ' vs. '
                  . $checker . ' ('
                  . $checksum
                  . ' mod 11)';
            }
            else {
                $check_10 = 'ok';
            }
        }
    }

    # Length of isbn
    if ( $result eq 'yes'
        and not( $check_10 eq 'ok' or $check_13 eq 'ok' ) )
    {

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and length($test_isbn) == 10 )
        {
            $result = 'no';
            error_072_isbn_10_wrong_checksum($found_text_10);
        }

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and length($test_isbn) == 13 )
        {
            $result = 'no';
            error_073_isbn_13_wrong_checksum($found_text_13);
        }

        if (    $check_10 eq 'no ok'
            and $check_13 eq 'no ok'
            and $result eq 'yes'
            and length($test_isbn) != 0 )
        {
            $result = 'no';
            error_070_isbn_wrong_length( $current_isbn . length($test_isbn) );
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_templates_all {

    my $pos_start = 0;
    my $pos_end   = 0;
    my $text_test = $text;

    $text_test =~ s/\n//g;    # Delete all breaks     --> only one line
    $text_test =~ s/\t//g;    # Delete all tabulator  --> better for output

    while ( $text_test =~ /\{\{/g ) {

        $pos_start = pos($text_test) - 2;
        my $temp_text      = substr( $text_test, $pos_start );
        my $temp_text_2    = q{};
        my $brackets_begin = 1;
        my $brackets_end   = 0;
        while ( $temp_text =~ /\}\}/g ) {

            # Find currect end - number of {{ == }}
            $pos_end = pos($temp_text);
            $temp_text_2 = q{ } . substr( $temp_text, 0, $pos_end ) . q{ };

            # Test the number of {{ and  }}
            $brackets_begin = ( $temp_text_2 =~ tr/{{/{{/ );
            $brackets_end   = ( $temp_text_2 =~ tr/}}/}}/ );

            last if ( $brackets_begin == $brackets_end );
        }

        if ( $brackets_begin == $brackets_end ) {

            # Demplate is correct
            $temp_text_2 = substr( $temp_text_2, 1, length($temp_text_2) - 2 );
            push( @templates_all, $temp_text_2 );
        }
        else {
            error_043_template_no_correct_end( substr( $temp_text, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_template {

    # Extract for each template all attributes and values
    my $number_of_templates   = -1;
    my $template_part_counter = -1;
    my $output                = q{};
    foreach (@templates_all) {
        my $current_template = $_;

        $current_template =~ s/^\{\{//;
        $current_template =~ s/\}\}$//;
        $current_template =~ s/^ //g;

        foreach (@namespace_templates) {
            $current_template =~ s/^$_://i;
        }

        $number_of_templates = $number_of_templates++;
        my $template_name = q{};

        my @template_split = split( /\|/, $current_template );
        my $number_of_splits = @template_split;

        if ( index( $current_template, '|' ) == -1 ) {

            # If no pipe; for example {{test}}
            $template_name = $current_template;
            next;
        }

        if ( index( $current_template, '|' ) > -1 ) {

            # Templates with pipe {{test|attribute=value}}

            # Get template name
            $template_split[0] =~ s/^ //g;
            $template_name = $template_split[0];

            if ( index( $template_name, '_' ) > -1 ) {
                $template_name =~ s/_/ /g;
            }
            if ( index( $template_name, '  ' ) > -1 ) {
                $template_name =~ s/  / /g;
            }

            shift(@template_split);

            # Get next part of template
            my $template_part = q{};
            my @template_part_array;
            undef(@template_part_array);

            foreach (@template_split) {
                $template_part = $template_part . $_;

                # Check for []
                my $beginn_brackets = ( $template_part =~ tr/[[/[[/ );
                my $end_brackets    = ( $template_part =~ tr/]]/]]/ );

                # Check for {}
                my $beginn_curly_brackets = ( $template_part =~ tr/{{/{{/ );
                my $end_curly_brackets    = ( $template_part =~ tr/}}/}}/ );

                # Template part complete ?
                if (    $beginn_brackets eq $end_brackets
                    and $beginn_curly_brackets eq $end_curly_brackets )
                {

                    push( @template_part_array, $template_part );
                    $template_part = q{};
                }
                else {
                    $template_part = $template_part . '|';
                }

            }

            # OUTPUT If only templates {{{xy|value}}
            my $template_part_number           = -1;
            my $template_part_without_attribut = -1;

            foreach (@template_part_array) {
                $template_part = $_;

                $template_part_number++;
                $template_part_counter++;

                $template_name =~ s/^[ ]+//g;
                $template_name =~ s/[ ]+$//g;
                $template[$template_part_counter][0] = $number_of_templates;
                $template[$template_part_counter][1] = $template_name;
                $template[$template_part_counter][2] = $template_part_number;

                my $attribut = q{};
                my $value    = q{};
                if ( index( $template_part, '=' ) > -1 ) {

                    #template part with "="   {{test|attribut=value}}

                    my $pos_equal     = index( $template_part, '=' );
                    my $pos_lower     = index( $template_part, '<' );
                    my $pos_next_temp = index( $template_part, '{{' );
                    my $pos_table     = index( $template_part, '{|' );
                    my $pos_bracket   = index( $template_part, '[' );

                    my $equal_ok = 'true';
                    $equal_ok = 'false'
                      if ( $pos_lower > -1 and $pos_lower < $pos_equal );
                    $equal_ok = 'false'
                      if (  $pos_next_temp > -1
                        and $pos_next_temp < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_table > -1 and $pos_table < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_bracket > -1 and $pos_bracket < $pos_equal );

                    if ( $equal_ok eq 'true' ) {

                        # Template part with "="   {{test|attribut=value}}
                        $attribut =
                          substr( $template_part, 0,
                            index( $template_part, '=' ) );
                        $value =
                          substr( $template_part,
                            index( $template_part, '=' ) + 1 );
                    }
                    else {
                     # Problem:  {{test|value<ref name="sdfsdf"> sdfhsdf</ref>}}
                     # Problem   {{test|value{{test2|name=teste}}|sdfsdf}}
                        $template_part_without_attribut =
                          $template_part_without_attribut + 1;
                        $attribut = $template_part_without_attribut;
                        $value    = $template_part;
                    }
                }
                else {
                    # Template part with no "="   {{test|value}}
                    $template_part_without_attribut =
                      $template_part_without_attribut + 1;
                    $attribut = $template_part_without_attribut;
                    $value    = $template_part;
                }

                $attribut =~ s/^[ ]+//g;
                $attribut =~ s/[ ]+$//g;
                $value =~ s/^[ ]+//g;
                $value =~ s/[ ]+$//g;

                $template[$template_part_counter][3] = $attribut;
                $template[$template_part_counter][4] = $value;

                $number_of_template_parts = $number_of_template_parts + 1;

                $output .= $title . "\t";
                $output .= $template[$template_part_counter][0] . "\t";
                $output .= $template[$template_part_counter][1] . "\t";
                $output .= $template[$template_part_counter][2] . "\t";
                $output .= $template[$template_part_counter][3] . "\t";
                $output .= $template[$template_part_counter][4] . "\n";
            }
        }
    }

    # Output for TemplateTiger
    if (
        $dump_or_live eq 'dump'
        and (  $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
      )
    {

        #$TTFile->print($output);

    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_links {

    my $pos_start = 0;
    my $pos_end   = 0;

    my $text_test = $text;

    $text_test =~ s/\n//g;

    while ( $text_test =~ /\[\[/g ) {

        $pos_start = pos($text_test) - 2;
        my $link_text      = substr( $text_test, $pos_start );
        my $link_text_2    = q{};
        my $brackets_begin = 1;
        my $brackets_end   = 0;
        while ( $link_text =~ /\]\]/g ) {

            # Find currect end - number of [[==]]
            $pos_end = pos($link_text);
            $link_text_2 = q{ } . substr( $link_text, 0, $pos_end ) . q{ };

            # Test the number of [[ and ]]
            $brackets_begin = ( $link_text_2 =~ tr/[[/[[/ );
            $brackets_end   = ( $link_text_2 =~ tr/]]/]]/ );

            last if ( $brackets_begin == $brackets_end );
        }

        if ( $brackets_begin == $brackets_end ) {

            $link_text_2 = substr( $link_text_2, 1, length($link_text_2) - 2 );
            push( @links_all, $link_text_2 );

            if ( $link_text_2 =~ /^\[\[\s*(?:$image_regex):/i ) {
                push( @images_all, $link_text_2 );
            }

        }
        else {
            error_010_count_square_breaks( substr( $link_text, 0, 40 ) );

        }
    }
    return ();
}

###########################################################################
##
###########################################################################

sub get_images {

    my $found_error_text = q{};
    foreach (@images_all) {

        my $current_image = $_;

        my $test_image = $current_image;

        foreach (@magicword_img_thumbnail) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_right) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_left) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_none) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_center) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_framed) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_frameless) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_border) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_sub) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_super) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_baseline) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_top) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_text_top) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_middle) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        foreach (@magicword_img_bottom) {
            my $current_magicword = $_;

            $test_image =~ s/\|([ ]?)+$current_magicword([ ]?)+(\||\])/$3/i;
        }

        $test_image =~ s/\|([ ]?)+[0-9]+(x[0-9]+)?px([ ]?)+(\||\])/$4/i;

        if ( $found_error_text eq '' ) {
            if ( index( $test_image, '|' ) == -1 ) {

                $found_error_text = $current_image;
            }
            else {
                my $pos_1 = index( $test_image, '|' );
                my $pos_2 = index( $test_image, '|', $pos_1 + 1 );

                if ( $pos_2 == -1
                    and index( $test_image, '|]' ) > -1 )
                {
                    $found_error_text = $current_image;
                }
            }
        }
    }

    if ( $found_error_text ne '' ) {
        error_030_image_without_description($found_error_text);
    }
    return ();
}

###########################################################################
##
###########################################################################

sub get_ref {

    my $pos_start_old = 0;
    my $pos_end_old   = 0;
    my $end_search    = 0;

    while ( $end_search == 0 ) {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 1;

        $pos_start = index( $text, '<ref>',  $pos_start_old );
        $pos_end   = index( $text, '</ref>', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            $pos_end       = $pos_end + length('</ref>');
            $end_search    = 0;
            $pos_start_old = $pos_end;

            push( @ref, substr( $text, $pos_start, $pos_end - $pos_start ) );
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_for_redirect {

    if ( index( lc($text), '#redirect' ) > -1 ) {
        $page_is_redirect = 'yes';
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_categories {

    foreach (@namespace_cat) {

        my $namespace_cat_word = $_;
        my $pos_start          = 0;
        my $pos_end            = 0;
        my $counter            = 0;
        my $text_test          = $text;
        my $search_word        = $namespace_cat_word;

        while ( $text_test =~ /\[\[([ ]+)?($search_word:)/ig ) {
            my $pos_start = pos($text_test) - length($search_word) - 1;
            $pos_end = index( $text_test, ']]', $pos_start );
            $pos_start = $pos_start - 2;

            if ( $pos_start > -1 and $pos_end > -1 ) {

                $counter               = ++$category_counter;
                $pos_end               = $pos_end + 2;
                $category[$counter][0] = $pos_start;
                $category[$counter][1] = $pos_end;
                $category[$counter][4] =
                  substr( $text_test, $pos_start, $pos_end - $pos_start );
                $category[$counter][2] = $category[$counter][4];
                $category[$counter][3] = $category[$counter][4];

                $category[$counter][2] =~ s/\[\[//g;        # Delete [[
                $category[$counter][2] =~ s/^([ ]+)?//g;    # Delete blank
                $category[$counter][2] =~ s/\]\]//g;        # Delete ]]
                $category[$counter][2] =~ s/^$namespace_cat_word//i;
                $category[$counter][2] =~ s/^://;           # Delete :
                $category[$counter][2] =~ s/\|(.)*//g;      # Delete |xy
                $category[$counter][2] =~ s/^ //g;          # Delete blank
                $category[$counter][2] =~ s/ $//g;          # Delete blank

                # Filter linkname
                $category[$counter][3] = q{}
                  if ( index( $category[$counter][3], '|' ) == -1 );
                $category[$counter][3] =~ s/^(.)*\|//gi; # Delete [[category:xy|
                $category[$counter][3] =~ s/\]\]//g;     # Delete ]]
                $category[$counter][3] =~ s/^ //g;       # Delete blank
                $category[$counter][3] =~ s/ $//g;       # Delete blank

            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_interwikis {

    if ( $text =~ /\[\[([a-z][a-z]|als|nds|nds_nl|simple):/i ) {

        foreach (@inter_list) {

            my $current_lang = $_;
            my $pos_start    = 0;
            my $pos_end      = 0;
            my $counter      = 0;
            my $test_text    = $text;
            my $search_word  = $current_lang;

            while ( $test_text =~ /\[\[$search_word:/ig ) {
                $pos_start = pos($test_text) - length($search_word) - 1;
                $pos_end   = index( $test_text, ']]', $pos_start );
                $pos_start = $pos_start - 2;

                if ( $pos_start > -1 and $pos_end > -1 ) {

                    $counter                = ++$interwiki_counter;
                    $pos_end                = $pos_end + 2;
                    $interwiki[$counter][0] = $pos_start;
                    $interwiki[$counter][1] = $pos_end;
                    $interwiki[$counter][4] =
                      substr( $test_text, $pos_start, $pos_end - $pos_start );
                    $interwiki[$counter][5] = $current_lang;
                    $interwiki[$counter][2] = $interwiki[$counter][4];
                    $interwiki[$counter][3] = $interwiki[$counter][4];

                    $interwiki[$counter][2] =~ s/\]\]//g;       # Delete ]]
                    $interwiki[$counter][2] =~ s/\|(.)*//g;     # Delete |xy
                    $interwiki[$counter][2] =~ s/^(.)*://gi;    # Delete [[xx:
                    $interwiki[$counter][2] =~ s/^ //g;         # Delete blank
                    $interwiki[$counter][2] =~ s/ $//g;         # Delete blank;

                    if ( index( $interwiki[$counter][3], '|' ) == -1 ) {
                        $interwiki[$counter][3] = q{};
                    }

                    $interwiki[$counter][3] =~ s/^(.)*\|//gi;
                    $interwiki[$counter][3] =~ s/\]\]//g;
                    $interwiki[$counter][3] =~ s/^ //g;
                    $interwiki[$counter][3] =~ s/ $//g;
                }
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub create_line_array {
    @lines = split( /\n/, $text );

    return ();
}

###########################################################################
##
###########################################################################

sub get_headlines {

    my $section_text = q{};

    foreach (@lines) {
        my $current_line = $_;

        if ( substr( $current_line, 0, 1 ) eq '=' ) {
            push( @section, $section_text );
            $section_text = q{};
            push( @headlines, $current_line );
        }
        $section_text = $section_text . $_ . "\n";
    }
    push( @section, $section_text );

    return ();
}

###########################################################################
##
##########################################################################

sub error_check {
    if ( $CheckOnlyOne > 0 ) {
        error_084_section_without_text();
    }
    else {
        #error_001_no_bold_title();                        # DEACTIVATED
        error_002_have_br();
        error_003_have_ref();

        #error_004_have_html_and_no_topic();               # DEACTIVATED

        #error_005_Comment_no_correct_end('');             # get_comments()
        error_006_defaultsort_with_special_letters();
        error_007_headline_only_three();
        error_008_headline_start_end();
        error_009_more_then_one_category_in_a_line();

        #error_010_count_square_breaks('');                # get_links()
        error_011_html_names_entities();
        error_012_html_list_elements();

        #error_013_Math_no_correct_end('');                # get_math
        #error_014_Source_no_correct_end('');              # get_source()
        #error_015_Code_no_correct_end('');                # get_code()
        error_016_unicode_control_characters();
        error_017_category_double();
        error_018_category_first_letter_small();
        error_019_headline_only_one();
        error_020_symbol_for_dead();
        error_021_category_is_english();
        error_022_category_with_space();

        #error_023_nowiki_no_correct_end('');              # get_nowiki()
        #error_024_pre_no_correct_end('');                 # get_pre()
        error_025_headline_hierarchy();
        error_026_html_text_style_elements();
        error_027_unicode_syntax();

        #error_028_table_no_correct_end('');               # get_tables()
        #error_029_gallery_no_correct_end('');             # get_gallery()
        #error_030_image_without_description('');          # get_images()
        error_031_html_table_elements();
        error_032_double_pipe_in_link();
        error_033_html_text_style_elements_underline();
        error_034_template_programming_elements();

        #error_035_gallery_without_description('');        # get_gallery()
        error_036_redirect_not_correct();
        error_037_title_with_special_letters_and_no_defaultsort();
        error_038_html_text_style_elements_italic();
        error_039_html_text_style_elements_paragraph();
        error_040_html_text_style_elements_font();
        error_041_html_text_style_elements_big();

        #error_042_html_text_style_elements_small();       # DEACTIVATED

        #error_043_template_no_correct_end('');            # get_templates()
        error_044_headline_with_bold();
        error_045_interwiki_double();
        error_046_count_square_breaks_begin();
        error_047_template_no_correct_begin();
        error_048_title_in_text();
        error_049_headline_with_html();
        error_050_dash();
        error_051_interwiki_before_last_headline();
        error_052_category_before_last_headline();
        error_053_interwiki_before_category();
        error_054_break_in_list();
        error_055_html_text_style_elements_small_double();
        error_056_arrow_as_ASCII_art();
        error_057_headline_end_with_colon();
        error_058_headline_with_capitalization();
        error_059_template_value_end_with_br();
        error_060_template_parameter_with_problem();
        error_061_reference_with_punctuation();
        error_062_headline_alone();
        error_063_html_text_style_elements_small_ref_sub_sup();
        error_064_link_equal_linktext();
        error_065_image_description_with_break();
        error_066_image_description_with_full_small();
        error_067_reference_after_punctuation();    # DEACTIVATED
        error_068_link_to_other_language();

        #error_069_isbn_wrong_syntax('');                  # get_isbn()
        #error_070_isbn_wrong_length('');                  # get_isbn()
        #error_071_isbn_wrong_pos_X('');                   # get_isbn()
        #error_072_isbn_10_wrong_checksum('');             # get_isbn()
        #error_073_isbn_13_wrong_checksum('');             # get_isbn()
        error_074_link_with_no_target();
        error_075_indented_list();
        error_076_link_with_no_space();
        error_077_image_description_with_partial_small();
        error_078_reference_double();
        error_079_external_link_without_description();
        error_080_external_link_with_line_break();
        error_081_ref_double();
        error_082_link_to_other_wikiproject();
        error_083_headline_only_three_and_later_level_two();
        error_084_section_without_text();
        error_085_tag_without_content();
        error_086_link_with_two_brackets_to_external_source();
        error_087_html_names_entities_without_semicolon();
        error_088_defaultsort_with_first_blank();

        # DEACTIVATED - Mediawiki software changed, so no longer a problem.
        #error_089_defaultsort_with_capitalization_in_the_middle_of_the_word();
        #error_090_defaultsort_with_lowercase_letters();
        #error_091_title_with_lowercase_letters_and_no_defaultsort();
        error_092_headline_double();
    }

    return ();
}

###########################################################################
##  ERROR 01
###########################################################################

sub error_001_no_bold_title {

    return ();
}

###########################################################################
## ERROR 02
###########################################################################

sub error_002_have_br {
    my $error_code = 2;

    my $test      = 'no found';
    my $test_line = q{};

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $text;
            if ( $test_text =~
/(<\s*br\/[^ ]>|<\s*br[^ ]\/>|<\s*br[^ \/]>|<[^ ]br\s*>|<\s*br\s*\/[^ ]>)/i
              )
            {

                my $pos = index( $test_text, $1 );
                $test_line = substr( $text, $pos, 40 );
                $test_line =~ s/[\n\r]//mg;

                error_register( $error_code, $test_line );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 03
###########################################################################

sub error_003_have_ref {
    my $error_code = 3;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 104 )
        {

            if (   index( $text, '<ref>' ) > -1
                or index( $text, '<ref name' ) > -1 )
            {

                my $test      = "false";
                my $test_text = lc($text);
                $test = "true"
                  if (  $test_text =~ /<[ ]?+references>/
                    and $test_text =~ /<[ ]?+\/references>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references[ ]?+\/>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references group/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refbegin/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refend/ );
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reflist/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reflink/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reference list/ );    # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references-small/ );  # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references/ );        # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+listaref / );         # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+reference/ );         # in enwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+przypisy/ );          # in plwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+amaga/ );             # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referències/ );      # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+viitteet/ );          # in fiwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+verwysings/ );        # in afwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+references/ );        # in itwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+références/ );      # in frwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+notes/ );             # in frwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+listaref/ );          # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referenties/ );       # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+ref-section/ );       # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referências/ );      # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+refs/ );    # in nlwiki + enwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+noot/ ); # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+unreferenced/ );      # in nlwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+fnb/ );  # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+примечания/ )
                  ;                                                  # in ruwiki
                $test = "true"
                  if ( $test_text =~
                    /\{\{[ ]?+список примечаний/ );  # in ruwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+Примечания/ )
                  ;    # in ruwiki (Problem with big letters)
                $test = "true"
                  if (
                    $test_text =~ /\{\{[ ]?+Список примечаний/ )
                  ;    # in ruwiki (Problem with big letters)
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+kaynakça/ );    # in trwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+ثبت المراجع/ )
                  ;                                             # in arwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+appendix/ );     # in nlwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+примітки/ );  # in ukwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+Примітки/ );  # in ukwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+hide ref/ );          # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+forrás/ );           # in huwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳/ );            # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳h/ );           # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+註腳f/ );           # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+kayan kaynakça/ );   # in trwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+r/ );    # in itwiki
                $test = "true" if ( $test_text =~ /\{\{[ ]?+r/ );    # in itwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+הערות שוליים/ )
                  ;                                                  # in hewiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+הערה/ );          # in hewiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+注脚/ );            # in zhwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+referências/ );      # in ptwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+רעפליסטע/ );  # in yiwiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+apèndix/ );          # in cawiki
                $test = "true"
                  if ( $test_text =~ /\{\{[ ]?+παραπομπές/ )
                  ;                                                  # in elwiki

                if ( $test eq "false" ) {
                    error_register( $error_code, '' );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 04
###########################################################################

sub error_004_have_html_and_no_topic {

    return ();
}

###########################################################################
## ERROR 05
###########################################################################

sub error_005_Comment_no_correct_end {
    my ($comment) = @_;
    my $error_code = 5;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, substr( $comment, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 06
###########################################################################

sub error_006_defaultsort_with_special_letters {
    my $error_code = 6;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
                ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki'

          )
        {
            # Is DEFAULTSORT found in article?
            my $isDefaultsort = -1;
            foreach ( @{$magicword_defaultsort} ) {
                $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
            }

            if ( $isDefaultsort > -1 ) {
                my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
                my $test_text = substr( $text, $isDefaultsort, $pos2 );

                my $test_text2 = $test_text;

                # Remove ok letters
                $test_text =~ s/[-:,\.\/\(\)0-9 A-Za-z!\?']//g;

                # Too many to figure out what is right or not
                $test_text =~ s/#//g;
                $test_text =~ s/\+//g;

                if ( $project eq 'svwiki' ) {
                    $test_text =~ s/[ÅÄÖåäö]//g;
                }
                if ( $project eq 'fiwiki' ) {
                    $test_text =~ s/[ÅÄÖåäö]//g;
                }
                if ( $project eq 'cswiki' ) {
                    $test_text =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g;
                }
                if ( $project eq 'dawiki' ) {
                    $test_text =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'nowiki' ) {
                    $test_text =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'nnwiki' ) {
                    $test_text =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'rowiki' ) {
                    $test_text =~ s/[ăîâşţ]//g;
                }
                if ( $project eq 'ruwiki' ) {
                    $test_text =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g;
                }
                if ( $project eq 'ukwiki' ) {
                    $test_text =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяiїґ]//g;
                }

                if ( $test_text ne '' ) {
                    $test_text2 = "{{" . $test_text2 . "}}";
                    error_register( $error_code, $test_text2 );
                }

            }
        }
    }

    return ();
}

###########################################################################
## ERROR 07
###########################################################################

sub error_007_headline_only_three {
    my $error_code = 7;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'no' ) {
                    error_register( $error_code, $headlines[0] );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 08
###########################################################################

sub error_008_headline_start_end {
    my $error_code = 8;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        foreach (@headlines) {
            my $current_line  = $_;
            my $current_line1 = $current_line;
            my $current_line2 = $current_line;

            $current_line2 =~ s/\t//gi;
            $current_line2 =~ s/[ ]+/ /gi;
            $current_line2 =~ s/ $//gi;

            if (    $current_line1 =~ /^==/
                and not( $current_line2 =~ /==$/ )
                and index( $current_line, '<ref' ) == -1
                and ( $page_namespace == 0 or $page_namespace == 104 ) )
            {
                error_register( $error_code, substr( $current_line, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 09
###########################################################################

sub error_009_more_then_one_category_in_a_line {
    my $error_code = 9;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $cat_number;
            my $error_line = q{};

            foreach (@lines) {

                #my $current_line = $_;

                $cat_number = () = $_ =~ /\[\[($cat_regex):/ig;
                if ( $cat_number > 1 ) {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 10
###########################################################################

sub error_010_count_square_breaks {
    my ($comment) = @_;
    my $error_code = 10;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, substr( $comment, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 11
###########################################################################

sub error_011_html_names_entities {
    my $error_code = 11;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos       = -1;
            my $test_text = lc($text);

            # See http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
            $pos = index( $test_text, '&auml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&ouml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&uuml;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&szlig;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aring;' )  if ( $pos == -1 );    # åÅ
            $pos = index( $test_text, '&hellip;' ) if ( $pos == -1 );    # …
            $pos = index( $test_text, '&quot;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&minus;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&oline;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&cent;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&pound;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&euro;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&sect;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&dagger;' ) if ( $pos == -1 );

            $pos = index( $test_text, '&lsquo;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&rsquo;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&middot;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&bull;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&copy;' )   if ( $pos == -1 );
            $pos = index( $test_text, '&reg;' )    if ( $pos == -1 );
            $pos = index( $test_text, '&trade;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&iquest;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&iexcl;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aelig;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&ccedil;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&ntilde;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&acirc;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&aacute;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&agrave;' ) if ( $pos == -1 );

            #arrows
            $pos = index( $test_text, '&darr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&uarr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&crarr;' ) if ( $pos == -1 );
            $pos = index( $test_text, '&rarr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&larr;' )  if ( $pos == -1 );
            $pos = index( $test_text, '&harr;' )  if ( $pos == -1 );

            if ( $pos > -1 ) {
                my $found_text = substr( $text, $pos, 40 );
                $found_text =~ s/&/&amp;/g;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 12
###########################################################################

sub error_012_html_list_elements {
    my $error_code = 12;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);

            if (   index( $test_text, '<ol>' ) > -1
                or index( $test_text, '<ul>' ) > -1
                or index( $test_text, '<li>' ) > -1 )
            {

                # Only search for <ol>. <ol type an <ol start can be used.
                if (    index( $test_text, '<ol start' ) == -1
                    and index( $test_text, '<ol type' ) == -1
                    and index( $test_text, '<ol reversed' ) == -1 )
                {

                    # <ul> or <li> in templates can be only way to do a list.
                    $test_text = $text;
                    foreach (@templates_all) {
                        $test_text =~ s/\Q$_\E//s;
                    }

                    my $test_text_lc = lc($test_text);
                    my $pos = index( $test_text_lc, '<ol>' );

                    if ( $pos == -1 ) {
                        $pos = index( $test_text_lc, '<ul>' );
                    }
                    if ( $pos == -1 ) {
                        $pos = index( $test_text_lc, '<li>' );
                    }

                    if ( $pos > -1 ) {
                        $test_text = substr( $test_text_lc, $pos, 40 );
                        error_register( $error_code, $test_text );
                    }
                }
            }
        }
    }
    return ();
}

###########################################################################
## ERROR 13
###########################################################################

sub error_013_Math_no_correct_end {
    my ($comment) = @_;
    my $error_code = 13;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $comment ne '' ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 14
###########################################################################

sub error_014_Source_no_correct_end {
    my ($comment) = @_;
    my $error_code = 14;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $comment ne '' ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 15
###########################################################################

sub error_015_Code_no_correct_end {
    my ($comment) = @_;
    my $error_code = 15;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $comment ne '' ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 16
###########################################################################

sub error_016_unicode_control_characters {
    my $error_code = 16;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $search;

            # 200B is a problem with IPA characters in some wikis (czwiki)
            if ( $project eq 'enwiki' ) {
                $search = "\x{200E}|\x{FEFF}\x{200B}";
            }
            else {
                $search = "\x{200E}|\x{FEFF}";
            }

            if ( $text =~ /($search)/ ) {
                my $test_text = $text;
                my $pos = index( $test_text, $1 );
                $test_text = substr( $test_text, $pos, 40 );

                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 17
###########################################################################

sub error_017_category_double {
    my ($comment) = @_;
    my $error_code = 17;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach my $i ( 0 .. $category_counter - 1 ) {
                my $test = $category[$i][2];

                if ( $test ne q{} ) {
                    $test = uc( substr( $test, 0, 1 ) ) . substr( $test, 1 );

                    foreach my $j ( $i + 1 .. $category_counter ) {
                        my $test2 = $category[$j][2];

                        if ( $test2 ne q{} ) {
                            $test2 =
                              uc( substr( $test2, 0, 1 ) )
                              . substr( $test2, 1 );
                        }

                        if ( $test eq $test2 ) {
                            error_register( $error_code, $category[$i][2] );
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 18
###########################################################################

sub error_018_category_first_letter_small {
    my $error_code = 18;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $project ne 'commonswiki' ) {

            foreach my $i ( 0 .. $category_counter ) {
                my $test_letter = substr( $category[$i][2], 0, 1 );
                if ( $test_letter =~ /([a-z]|ä|ö|ü)/ ) {
                    error_register( $error_code, $category[$i][2] );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 19
###########################################################################

sub error_019_headline_only_one {
    my $error_code = 19;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $headlines[0] ) {
                if ( $headlines[0] =~ /^=[^=]/ ) {
                    error_register( $error_code,
                        substr( $headlines[0], 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 20
###########################################################################

sub error_020_symbol_for_dead {
    my $error_code = 20;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $text, '&dagger;' );
            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 21
###########################################################################

sub error_021_category_is_english {
    my $error_code = 21;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if (    $project ne 'enwiki'
                and $project ne 'commonswiki'
                and $namespace_cat[0] ne 'Category' )
            {

                foreach my $i ( 0 .. $category_counter ) {
                    my $current_cat = lc( $category[$i][4] );

                    if ( index( $current_cat, lc( $namespace_cat[1] ) ) > -1 ) {
                        error_register( $error_code, $current_cat );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 22
###########################################################################

sub error_022_category_with_space {
    my $error_code = 22;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach my $i ( 0 .. $category_counter ) {

                if (   $category[$i][4] =~ /\[\[ /
                    or $category[$i][4] =~ /\[\[[^:]+ :/ )
                {
                    error_register( $error_code, $category[$i][4] );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 23
###########################################################################

sub error_023_nowiki_no_correct_end {
    my ($comment) = @_;
    my $error_code = 23;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 24
###########################################################################

sub error_024_pre_no_correct_end {
    my ($comment) = @_;
    my $error_code = 24;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 25
###########################################################################

sub error_025_headline_hierarchy {
    my $error_code = 25;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_headline = -1;
            my $old_headline    = q{};
            my $new_headline    = q{};

            foreach (@headlines) {
                $number_headline = $number_headline + 1;
                $old_headline    = $new_headline;
                $new_headline    = $_;

                if ( $number_headline > 0 ) {
                    my $level_old = $old_headline;
                    my $level_new = $new_headline;

                    $level_old =~ s/^([=]+)//;
                    $level_new =~ s/^([=]+)//;
                    $level_old = length($old_headline) - length($level_old);
                    $level_new = length($new_headline) - length($level_new);

                    if ( $level_new > $level_old
                        and ( $level_new - $level_old ) > 1 )
                    {
                        error_register( $error_code,
                            $old_headline . '<br>' . $new_headline );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 26
###########################################################################

sub error_026_html_text_style_elements {
    my $error_code = 26;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos = index( $test_text, '<b>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 27
###########################################################################

sub error_027_unicode_syntax {
    my $error_code = 27;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos = -1;
            $pos = index( $text, '&#322;' )   if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#x0124;' ) if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#8211;' )  if ( $pos == -1 );  # –

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 28
###########################################################################

sub error_028_table_no_correct_end {
    my ($comment) = @_;
    my $error_code = 28;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    $comment ne ''
            and ( $page_namespace == 0 or $page_namespace == 104 )
            and index( $text, '{{end}}' ) == -1
            and index( $text, '{{End box}}' ) == -1
            and index( $text, '{{end box}}' ) == -1
            and index( $text, '{{Fb cs footer' ) == -1
            and index( $text, '{{Fb cl footer' ) == -1
            and index( $text, '{{Fb disc footer' ) == -1
            and index( $text, '{{Fb footer' ) == -1
            and index( $text, '{{Fb kit footer' ) == -1
            and index( $text, '{{Fb match footer' ) == -1
            and index( $text, '{{Fb oi footer' ) == -1
            and index( $text, '{{Fb r footer' ) == -1
            and index( $text, '{{Fb rbr pos footer' ) == -1
            and index( $text, '{{Ig footer' ) == -1
            and index( $text, '{{Jctbtm' ) == -1
            and index( $text, '{{jctbtm' ) == -1
            and index( $text, '{{LegendRJL' ) == -1
            and index( $text, '{{legendRJL' ) == -1
            and index( $text, '{{PHL sports results footer' ) == -1
            and index( $text, '{{WNBA roster footer' ) == -1
            and index( $text, '{{NBA roster footer' ) == -1 )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 29
###########################################################################

sub error_029_gallery_no_correct_end {
    my ($comment) = @_;
    my $error_code = 29;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 30
###########################################################################

sub error_030_image_without_description {
    my ($comment) = @_;
    my $error_code = 30;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $comment ne '' ) {
            if (   $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
            {
                error_register( $error_code, $comment );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 31
###########################################################################

sub error_031_html_table_elements {
    my $error_code = 31;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $test_text = lc($text);

            if ( index( $test_text, '<table' ) > -1 ) {

                # <table> in templates can be the only way to do a table.
                $test_text = $text;
                foreach (@templates_all) {
                    $test_text =~ s/\Q$_\E//s;
                }

                my $test_text_lc = lc($test_text);
                my $pos = index( $test_text_lc, '<table' );

                if ( $pos > -1 ) {
                    $test_text = substr( $test_text_lc, $pos, 40 );
                    error_register( $error_code, $test_text );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 32
###########################################################################

sub error_032_double_pipe_in_link {
    my $error_code = 32;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach (@lines) {
                my $current_line    = $_;
                my $current_line_lc = lc($current_line);
                if ( $current_line_lc =~ /\[\[[^\]:\{]+\|([^\]\{]+\||\|)/g ) {
                    my $pos              = pos($current_line_lc);
                    my $first_part       = substr( $current_line, 0, $pos );
                    my $second_part      = substr( $current_line, $pos );
                    my @first_part_split = split( /\[\[/, $first_part );
                    foreach (@first_part_split) {
                        $first_part = '[[' . $_;  # Find last link in first_part
                    }
                    $current_line = $first_part . $second_part;
                    error_register( $error_code,
                        substr( $current_line, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 33
###########################################################################

sub error_033_html_text_style_elements_underline {
    my $error_code = 33;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos = index( $test_text, '<u>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 34
###########################################################################

sub error_034_template_programming_elements {
    my $error_code = 34;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $test_line = q{};

            my $test_text = $text;
            if ( $test_text =~
/({{{|#if:|#ifeq:|#switch:|#ifexist:|{{fullpagename}}|{{sitename}}|{{namespace}})/i
              )
            {
                my $pos = index( $test_text, $1 );
                $test_line = substr( $text, $pos, 40 );
                $test_line =~ s/[\n\r]//mg;

                error_register( $error_code, $test_line );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 35
###########################################################################

sub error_035_gallery_without_description {
    my ($text_gallery) = @_;
    my $error_code = 35;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        my $test = q{};
        if (
            $text_gallery ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            my @split_gallery = split( /\n/, $text_gallery );
            my $test_line = q{};
            foreach (@split_gallery) {
                my $current_line = $_;

                foreach (@namespace_image) {
                    my $namespace_image_word = $_;

                    if ( $current_line =~ /^$namespace_image_word:[^\|]+$/ ) {
                        $test = 'found';
                        $test_line = $current_line if ( $test_line eq '' );
                    }
                }
            }
            if ( $test eq 'found' ) {
                error_register( $error_code, $test_line );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 36
###########################################################################

sub error_036_redirect_not_correct {
    my $error_code = 36;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $page_is_redirect eq 'yes' ) {
            if ( lc($text) =~ /#redirect[ ]?+[^ :\[][ ]?+\[/ ) {
                error_register( $error_code, substr( $text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 37
###########################################################################

sub error_037_title_with_special_letters_and_no_defaultsort {
    my $error_code = 37;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $category_counter > -1
            and $project ne 'arwiki'
            and $project ne 'jawiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'trwiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki'
            and length($title) > 2 )
        {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort = -1;
            foreach ( @{$magicword_defaultsort} ) {
                $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
            }

            if ( $isDefaultsort == -1 ) {

                my $test_title = $title;
                if ( $project ne 'enwiki' ) {
                    $test_title = substr( $test_title, 0, 5 );
                }

                # Titles such as 'Madonna (singer)' are OK
                $test_title =~ s/\(//g;
                $test_title =~ s/\)//g;

                # Remove ok letters
                $test_title =~ s/[-:,\.\/0-9 A-Za-z!\?']//g;

                # Too many to figure out what is right or not
                $test_title =~ s/#//g;
                $test_title =~ s/\+//g;

                if ( $project eq 'svwiki' ) {
                    $test_title =~ s/[ÅÄÖåäö]//g;
                }
                if ( $project eq 'fiwiki' ) {
                    $test_title =~ s/[ÅÄÖåäö]//g;
                }
                if ( $project eq 'cswiki' ) {
                    $test_title =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g;
                }
                if ( $project eq 'dawiki' ) {
                    $test_title =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'nowiki' ) {
                    $test_title =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'nnwiki' ) {
                    $test_title =~ s/[ÆØÅæøå]//g;
                }
                if ( $project eq 'rowiki' ) {
                    $test_title =~ s/[ăîâşţ]//g;
                }
                if ( $project eq 'ruwiki' ) {
                    $test_title =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g;
                }
                if ( $project eq 'ukwiki' ) {
                    $test_title =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяiїґ]//g;
                }

                if ( $test_title ne '' ) {
                    error_register( $error_code, q{} );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 38
###########################################################################

sub error_038_html_text_style_elements_italic {
    my $error_code = 38;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos = index( $test_text, '<i>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 39
###########################################################################

sub error_039_html_text_style_elements_paragraph {
    my $error_code = 39;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            if ( $test_text =~ /<p>|<p / ) {

                # https://bugzilla.wikimedia.org/show_bug.cgi?id=6200
                if ( $test_text !~
                    /<blockquote|\{\{quote\s*|\{\{cquote|\{\{quotation/ )
                {
                    my $pos = index( $test_text, '<p>' );
                    if ( $pos > -1 ) {
                        error_register( $error_code,
                            substr( $text, $pos, 40 ) );
                    }
                    $pos = index( $test_text, '<p ' );
                    if ( $pos > -1 ) {
                        error_register( $error_code,
                            substr( $text, $pos, 40 ) );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 40
###########################################################################

sub error_040_html_text_style_elements_font {
    my $error_code = 40;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos = index( $test_text, '<font' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 41
###########################################################################

sub error_041_html_text_style_elements_big {
    my $error_code = 41;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos = index( $test_text, '<big>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 42
###########################################################################

sub error_042_html_text_style_elements_small {

    return ();
}

###########################################################################
## ERROR 43
###########################################################################

sub error_043_template_no_correct_end {
    my ($comment) = @_;
    my $error_code = 43;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne ''
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 44
###########################################################################

sub error_044_headline_with_bold {
    my $error_code = 44;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@headlines) {
                my $headline = $_;

                if ( index( $headline, "'''" ) > -1
                    and not $headline =~ /[^']''[^']/ )
                {

                    if ( index( $headline, "<ref" ) < 0 ) {
                        error_register( $error_code,
                            substr( $headline, 0, 40 ) );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 45
###########################################################################

sub error_045_interwiki_double {
    my $error_code = 45;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_double = q{};
            foreach my $i ( 0 .. $interwiki_counter ) {

                for ( my $j = $i + 1 ; $j <= $interwiki_counter ; $j++ ) {
                    if ( lc( $interwiki[$i][5] ) eq lc( $interwiki[$j][5] ) ) {
                        my $test1 = lc( $interwiki[$i][2] );
                        my $test2 = lc( $interwiki[$j][2] );

                        if ( $test1 eq $test2 ) {
                            $found_double =
                              $interwiki[$i][4] . '<br>' . $interwiki[$j][4];
                        }

                    }
                }
            }
            if ( $found_double ne '' ) {
                error_register( $error_code, $found_double );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 46
###########################################################################

sub error_046_count_square_breaks_begin {
    my $error_code = 46;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $text_test = $text;

            my $text_test_1_a = $text_test;
            my $text_test_1_b = $text_test;

            if ( ( $text_test_1_a =~ s/\[\[//g ) !=
                ( $text_test_1_b =~ s/\]\]//g ) )
            {
                my $found_text = q{};
                my $begin_time = time();
                while ( $text_test =~ /\]\]/g ) {

                    # Begin of link
                    my $pos_end     = pos($text_test) - 2;
                    my $link_text   = substr( $text_test, 0, $pos_end );
                    my $link_text_2 = q{};
                    my $beginn_square_brackets = 0;
                    my $end_square_brackets    = 1;
                    while ( $link_text =~ /\[\[/g ) {

                        # Find currect end - number of [[==]]
                        my $pos_start = pos($link_text);
                        $link_text_2 = substr( $link_text, $pos_start );
                        $link_text_2 = ' ' . $link_text_2 . ' ';

                        # Test the number of [[and  ]]
                        my $link_text_2_a = $link_text_2;
                        $beginn_square_brackets =
                          ( $link_text_2_a =~ s/\[\[//g );
                        my $link_text_2_b = $link_text_2;
                        $end_square_brackets = ( $link_text_2_b =~ s/\]\]//g );

                        last
                          if ( $beginn_square_brackets eq $end_square_brackets
                            or $begin_time + 60 > time() );

                    }

                    if ( $beginn_square_brackets != $end_square_brackets ) {

                        # Link has no correct begin
                        $found_text = $link_text;
                        $found_text =~ s/  / /g;
                        $found_text =
                          text_reduce_to_end( $found_text, 50 ) . ']]';
                    }

                    last
                      if ( $found_text ne '' or $begin_time + 60 > time() )
                      ;    # End if a problem was found, no endless run
                }

                if ( $found_text ne '' ) {
                    error_register( $error_code, $found_text );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 47
###########################################################################

sub error_047_template_no_correct_begin {
    my $error_code       = 47;
    my $pos_start        = 0;
    my $pos_end          = 0;
    my $tag_open         = "{{";
    my $tag_close        = "}}";
    my $look_ahead_open  = 0;
    my $look_ahead_close = 0;
    my $look_ahead       = 0;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $test_text = $text;

            my $tag_open_num  = () = $test_text =~ /$tag_open/g;
            my $tag_close_num = () = $test_text =~ /$tag_close/g;

            my $diff = $tag_close_num - $tag_open_num;

            if ( $diff > 0 ) {

                my $pos_open  = rindex( $test_text, $tag_open );
                my $pos_close = rindex( $test_text, $tag_close );
                my $pos_close2 =
                  rindex( $test_text, $tag_close, $pos_open - 2 );

                while ( $diff > 0 ) {
                    if ( $pos_close2 == -1 ) {
                        error_register( $error_code,
                            substr( $text, $pos_close, 40 ) );
                        $diff = -1;
                    }
                    elsif ( $pos_close2 > $pos_open and $look_ahead < 0 ) {
                        error_register( $error_code,
                            substr( $text, $pos_close, 40 ) );
                        $diff--;
                    }
                    else {
                        $pos_close = $pos_close2;
                        $pos_close2 =
                          rindex( $test_text, $tag_close, $pos_close - 2 );
                        $pos_open =
                          rindex( $test_text, $tag_open, $pos_open - 2 );
                        if ( $pos_close2 > 0 ) {
                            $look_ahead_close =
                              rindex( $test_text, $tag_close, $pos_close2 - 2 );
                            $look_ahead_open =
                              rindex( $test_text, $tag_open, $pos_open - 2 );
                            $look_ahead = $look_ahead_open - $look_ahead_close;
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 48
###########################################################################

sub error_048_title_in_text {
    my $error_code = 48;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $test_text = $text;

            my $pos = index( $test_text, '[[' . $title . ']]' );

            if ( $pos == -1 ) {
                $pos = index( $test_text, '[[' . $title . '|' );
            }

            if ( $pos != -1 ) {
                $test_text = substr( $test_text, $pos, 40 );
                $test_text =~ s/\n//g;
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 49
###########################################################################

sub error_049_headline_with_html {
    my $error_code = 49;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $text_test = lc($text);
            my $pos       = -1;
            $pos = index( $text_test, '<h2>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h3>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h4>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h5>' )  if ( $pos == -1 );
            $pos = index( $text_test, '<h6>' )  if ( $pos == -1 );
            $pos = index( $text_test, '</h2>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h3>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h4>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h5>' ) if ( $pos == -1 );
            $pos = index( $text_test, '</h6>' ) if ( $pos == -1 );
            if ( $pos != -1 ) {
                $text_test = substr( $text_test, $pos, 40 );
                $text_test =~ s/\n//g;
                error_register( $error_code, $text_test );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 50
###########################################################################

sub error_050_dash {
    my $error_code = 50;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        my $pos = -1;
        $pos = index( lc($text), '&ndash;' );
        $pos = index( lc($text), '&mdash;' ) if $pos == -1;

        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            my $found_text = substr( $text, $pos, 40 );
            $found_text =~ s/\n//g;
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 51
###########################################################################

sub error_051_interwiki_before_last_headline {
    my $error_code = 51;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_of_headlines = @headlines;
            my $pos                 = -1;

            if ( $number_of_headlines > 0 ) {
                $pos = index( $text, $headlines[ $number_of_headlines - 1 ] );

                #pos of last headline

                my $found_text = q{};
                if ( $pos > -1 ) {
                    foreach my $i ( 0 .. $interwiki_counter ) {
                        if ( $pos > $interwiki[$i][0] ) {
                            $found_text = $interwiki[$i][4];
                        }
                    }
                }
                if ( $found_text ne '' ) {
                    error_register( $error_code, substr( $found_text, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 52
###########################################################################

sub error_052_category_before_last_headline {
    my $error_code = 52;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        my $number_of_headlines = @headlines;
        my $pos                 = -1;

        if ( $number_of_headlines > 0 ) {

            $pos =
              index( $text, $headlines[ $number_of_headlines - 1 ] )
              ;    #pos of last headline
        }
        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $found_text = q{};
            for ( my $i = 0 ; $i <= $category_counter ; $i++ ) {
                if ( $pos > $category[$i][0] ) {
                    $found_text = $category[$i][4];
                }
            }

            if ( $found_text ne '' ) {
                error_register( $error_code, substr( $found_text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 53
###########################################################################

sub error_053_interwiki_before_category {
    my $error_code = 53;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    $category_counter > -1
            and $interwiki_counter > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $pos_interwiki = $interwiki[0][0];
            my $found_text    = $interwiki[0][4];
            foreach my $i ( 0 .. $interwiki_counter ) {
                if ( $interwiki[$i][0] < $pos_interwiki ) {
                    $pos_interwiki = $interwiki[$i][0];
                    $found_text    = $interwiki[$i][4];
                }
            }

            my $found = 'false';
            foreach my $i ( 0 .. $category_counter ) {
                $found = 'true' if ( $pos_interwiki < $category[$i][0] );
            }

            if ( $found eq 'true' ) {
                error_register( $error_code, $found_text );
            }

        }
    }

    return ();
}

###########################################################################
## ERROR 54
###########################################################################

sub error_054_break_in_list {
    my $error_code = 54;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@lines) {

                if ( index( $_, q{*} ) == 0 ) {
                    if ( $_ =~ /<br([ ]+)?(\/)?([ ]+)?>([ ]+)?$/i ) {
                        error_register( $error_code, substr( $_, 0, 40 ) );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 55
###########################################################################

sub error_055_html_text_style_elements_small_double {
    my $error_code = 55;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            if ( index( $test_text, '<small>' ) > -1 ) {

                my $pos = -1;
                $pos = index( $test_text, '<small><small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '<small> <small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '<small>  <small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small></small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </small>' )
                  if ( $pos == -1 );
                $pos = index( $test_text, '</small>  </small>' )
                  if ( $pos == -1 );
                if ( $pos > -1 ) {
                    error_register( $error_code,
                        substr( $test_text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 56
###########################################################################

sub error_056_arrow_as_ASCII_art {
    my $error_code = 56;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = -1;
            $pos = index( lc($text), '->' );
            $pos = index( lc($text), '<-' ) if $pos == -1;
            $pos = index( lc($text), '<=' ) if $pos == -1;
            $pos = index( lc($text), '=>' ) if $pos == -1;

            if ( $pos > -1 ) {
                my $test_text = substr( $text, $pos - 10, 40 );
                $test_text =~ s/\n//g;
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 57
###########################################################################

sub error_057_headline_end_with_colon {
    my $error_code = 57;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@headlines) {
                if ( $_ =~ /:[ ]?[ ]?[ ]?[=]+([ ]+)?$/ ) {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 58
###########################################################################

sub error_058_headline_with_capitalization {
    my $error_code = 58;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@headlines) {
                my $current_line_normal = $_;

                $current_line_normal =~
                  s/[^A-Za-z,\/&]//g;    # Only english characters and comma

                my $current_line_uc = uc($current_line_normal);
                if ( length($current_line_normal) > 10 ) {

                    if ( $current_line_normal eq $current_line_uc ) {

                        # Found ALL CAPS HEADLINE(S)
                        my $check_ok = 'yes';

                        # Check comma
                        if ( index( $current_line_normal, q{,} ) > -1 ) {
                            my @comma_split =
                              split( ',', $current_line_normal );
                            foreach (@comma_split) {
                                if ( length($_) < 10 ) {
                                    $check_ok = 'no';
                                }
                            }
                        }
                        if ( $check_ok eq 'yes' and $_ ne q{} ) {
                            error_register( $error_code, substr( $_, 0, 40 ) );
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 59
###########################################################################

sub error_059_template_value_end_with_br {
    my $error_code = 59;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach my $i ( 0 .. $number_of_template_parts ) {

                if (
                    $template[$i][4] =~ /<br([ ]+)?(\/)?([ ]+)?>([ ])?([ ])?$/ )
                {
                    if ( $found_text eq q{} ) {
                        $found_text =
                          $template[$i][3] . '=...'
                          . text_reduce_to_end( $template[$i][4], 20 );
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 60
###########################################################################

sub error_060_template_parameter_with_problem {
    my $error_code = 60;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach my $i ( 0 .. $number_of_template_parts ) {

                if ( $template[$i][3] =~ /(\[|\]|\|:|\*)/ ) {
                    if ( $found_text eq q{} ) {
                        $found_text =
                          $template[$i][1] . ', ' . $template[$i][3];
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 61
###########################################################################

sub error_061_reference_with_punctuation {
    my $error_code = 61;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_txt = q{};
            my $pos       = -1;
            $pos = index( $text, '</ref>.' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> .' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  .' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>! ' )   if ( $pos == -1 );
            $pos = index( $text, '</ref> ! ' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>  ! ' ) if ( $pos == -1 );
            $pos = index( $text, '</ref>?' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> ?' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  ?' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>,' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> ,' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  ,' )  if ( $pos == -1 );
            $pos = index( $text, '</ref>:' )    if ( $pos == -1 );
            $pos = index( $text, '</ref> :' )   if ( $pos == -1 );
            $pos = index( $text, '</ref>  :' )  if ( $pos == -1 );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
            else {
                if ( $text =~ /(<ref name(.*?)\/>\.)/ ) {
                    $pos = index( $text, $1 );
                }
                elsif ( $text =~ /(<ref name(.*?)\/>,)/ ) {
                    $pos = index( $text, $1 );
                }

                if ( $pos > 0 ) {
                    error_register( $error_code, substr( $text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 62
###########################################################################

sub error_062_headline_alone {
    my $error_code = 62;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_of_headlines = @headlines;
            my $old_level           = 2;
            my $found_txt           = q{};
            if ( $number_of_headlines >= 5 ) {
                foreach my $i ( 0 .. $number_of_headlines - 1 ) {

                    my $headline_test_1 = $headlines[$i];
                    my $headline_test_2 = $headlines[$i];
                    $headline_test_1 =~ s/^([=]+)//;
                    my $current_level =
                      length($headline_test_2) - length($headline_test_1);

                    if (    $current_level > 2
                        and $old_level < $current_level
                        and $i < $number_of_headlines - 1
                        and $found_txt eq q{} )
                    {
                        # First headline in this level
                        my $found_same_level = 'no';
                        my $found_end        = 'no';
                        foreach my $j ( $i + 1 .. $number_of_headlines - 1 ) {

                            # Check all headlinds behind
                            my $headline_test_1b = $headlines[$j];
                            my $headline_test_2b = $headlines[$j];
                            $headline_test_1b =~ s/^([=]+)//;
                            my $test_level =
                              length($headline_test_2b) -
                              length($headline_test_1b);

                            if ( $test_level < $current_level ) {
                                $found_end = 'yes';
                            }

                            if (    $test_level = $current_level
                                and $found_end eq 'no' )
                            {
                                $found_same_level = 'yes';
                            }
                        }

                        if (    $found_txt eq q{}
                            and $found_same_level eq 'no' )
                        {
                            # Found alone text
                            $found_txt = $headlines[$i];
                        }
                    }

                    if (    $current_level > 2
                        and $old_level < $current_level
                        and $i == $number_of_headlines - 1
                        and $found_txt eq q{} )
                    {
                        # Found a last headline stand alone
                        $found_txt = $headlines[$i];
                    }
                    $old_level = $current_level;
                }
            }
            if ( $found_txt ne q{} ) {
                error_register( $error_code, $found_txt );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 63
###########################################################################

sub error_063_html_text_style_elements_small_ref_sub_sup {
    my $error_code = 63;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            my $pos       = -1;

            if ( index( $test_text, '<small>' ) > -1 ) {
                $pos = index( $test_text, '</small></ref>' )  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </ref>' ) if ( $pos == -1 );
                $pos = index( $test_text, '<sub><small>' )    if ( $pos == -1 );
                $pos = index( $test_text, '<sub> <small>' )   if ( $pos == -1 );
                $pos = index( $test_text, '<sup><small>' )    if ( $pos == -1 );
                $pos = index( $test_text, '<sub> <small>' )   if ( $pos == -1 );

                $pos = index( $test_text, '<small><ref' )   if ( $pos == -1 );
                $pos = index( $test_text, '<small> <ref' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small><sub>' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small> <sub>' ) if ( $pos == -1 );
                $pos = index( $test_text, '<small><sup>' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small> <sup>' ) if ( $pos == -1 );

                if ( $pos > -1 ) {
                    error_register( $error_code, substr( $text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 64
###########################################################################

sub error_064_link_equal_linktext {
    my $error_code = 64;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $temp_text = $text;
            if ( $temp_text =~ /\[\[([^|:]*)\|\1\]\]/ ) {
                my $found_text = '[[' . $1 . '|' . $1 . ']]';
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 65
###########################################################################

sub error_065_image_description_with_break {
    my $error_code = 65;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@images_all) {

                if ( $_ =~ /<br([ ]+)?(\/)?([ ]+)?>([ ])?(\||\])/i ) {
                    if ( $found_text eq '' ) {
                        $found_text = $_;
                    }
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 66
###########################################################################

sub error_066_image_description_with_full_small {
    my $error_code = 66;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@images_all) {

                if (    $_ =~ /<small([ ]+)?(\/)?([ ]+)?>([ ])?(\||\])/i
                    and $_ =~ /\|([ ]+)?<small/i )
                {
                    if ( $found_text eq q{} ) {
                        $found_text = $_;
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 67
###########################################################################

sub error_067_reference_after_punctuation {

    return ();
}

###########################################################################
## ERROR 68
###########################################################################

sub error_068_link_to_other_language {
    my $error_code = 68;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@links_all) {

                my $current_link = $_;
                foreach (@inter_list) {
                    my $current_lang = $_;
                    if ( $current_link =~ /^\[\[([ ]+)?:([ ]+)?$_:/i ) {
                        error_register( $error_code, $current_link );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 69
###########################################################################

sub error_069_isbn_wrong_syntax {
    my ($found_text) = @_;
    my $error_code = 69;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 70
###########################################################################

sub error_070_isbn_wrong_length {
    my ($found_text) = @_;
    my $error_code = 70;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_071_isbn_wrong_pos_X {
    my ($found_text) = @_;
    my $error_code = 71;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne '' )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_072_isbn_10_wrong_checksum {
    my ($found_text) = @_;
    my $error_code = 72;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 73
###########################################################################

sub error_073_isbn_13_wrong_checksum {
    my ($found_text) = @_;
    my $error_code = 73;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 74
###########################################################################

sub error_074_link_with_no_target {
    my $error_code = 74;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@links_all) {

                if ( index( $_, '[[|' ) > -1 ) {
                    my $pos = index( $_, '[[|' );
                    error_register( $error_code, substr( $_, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 75
###########################################################################

sub error_075_indented_list {
    my $error_code = 75;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and ( $text =~ /:\*/ or $text =~ /:#/ ) )
        {
            my $list = 0;

            foreach (@lines) {

                if ( index( $_, q{*} ) == 0 or index( $_, q{#} ) == 0 ) {
                    $list = 1;
                }
                elsif ( $list == 1
                    and ( $_ ne q{} and index( $_, q{:} ) != 0 ) )
                {
                    $list = 0;
                }

                if ( $list == 1
                    and ( index( $_, ':*' ) == 0 or index( $_, ':#' ) == 0 ) )
                {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 76
###########################################################################

sub error_076_link_with_no_space {
    my $error_code = 76;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@links_all) {

                if ( $_ =~ /^\[\[([^\|]+)%20([^\|]+)/i ) {
                    error_register( $error_code, $_ );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 77
###########################################################################

sub error_077_image_description_with_partial_small {
    my $error_code = 77;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@images_all) {

                if ( $_ =~ /<small([ ]+)?(\/|\\)?([ ]+)?>([ ])?/i
                    and not $_ =~ /\|([ ]+)?<([ ]+)?small/ )
                {
                    error_register( $error_code, $_ );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 78
###########################################################################

sub error_078_reference_double {
    my $error_code = 78;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text      = lc($text);
            my $number_of_refs = 0;
            my $pos_first      = -1;
            my $pos_second     = -1;
            while ( $test_text =~ /<references[ ]?\/>/g ) {
                my $pos = pos($test_text);

                $number_of_refs++;
                $pos_first = $pos
                  if ( $pos_first == -1 and $number_of_refs == 1 );
                $pos_second = $pos
                  if ( $pos_second == -1 and $number_of_refs == 2 );
            }

            if ( $number_of_refs > 1 ) {
                $test_text = $text;
                $test_text =~ s/\n/ /g;
                my $found_text = substr( $test_text, 0, $pos_first );
                $found_text = text_reduce_to_end( $found_text, 40 );
                my $found_text2 = substr( $test_text, 0, $pos_second );
                $found_text2 = text_reduce_to_end( $found_text2, 40 );
                $found_text = $found_text . '<br>' . $found_text2;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 79
###########################################################################

sub error_079_external_link_without_description {
    my $error_code = 79;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text  = lc($text);
            my $pos        = -1;
            my $found_text = q{};
            while (index( $test_text, '[http://', $pos + 1 ) > -1
                or index( $test_text, '[ftp://',   $pos + 1 ) > -1
                or index( $test_text, '[https://', $pos + 1 ) > -1 )
            {
                my $pos1 = index( $test_text, '[http://',  $pos + 1 );
                my $pos2 = index( $test_text, '[ftp://',   $pos + 1 );
                my $pos3 = index( $test_text, '[https://', $pos + 1 );

                my $next_pos = -1;
                $next_pos = $pos1 if ( $pos1 > -1 );
                $next_pos = $pos2
                  if ( ( $next_pos == -1 and $pos2 > -1 )
                    or ( $pos2 > -1 and $next_pos > $pos2 ) );
                $next_pos = $pos3
                  if ( ( $next_pos == -1 and $pos3 > -1 )
                    or ( $pos3 > -1 and $next_pos > $pos3 ) );

                my $pos_end = index( $test_text, ']', $next_pos );

                my $weblink =
                  substr( $text, $next_pos, $pos_end - $next_pos + 1 );

                if ( index( $weblink, ' ' ) == -1 ) {
                    $found_text = $weblink if ( $found_text eq '' );
                }
                $pos = $next_pos;
            }

            if ( $found_text ne '' ) {
                error_register( $error_code, substr( $found_text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 80
###########################################################################

sub error_080_external_link_with_line_break {
    my $error_code = 80;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text  = lc($text);
            my $pos        = -1;
            my $found_text = q{};
            while (index( $test_text, '[http://', $pos + 1 ) > -1
                or index( $test_text, '[ftp://',   $pos + 1 ) > -1
                or index( $test_text, '[https://', $pos + 1 ) > -1 )
            {
                my $pos1 = index( $test_text, '[http://',  $pos + 1 );
                my $pos2 = index( $test_text, '[ftp://',   $pos + 1 );
                my $pos3 = index( $test_text, '[https://', $pos + 1 );

                my $next_pos = -1;
                $next_pos = $pos1 if ( $pos1 > -1 );
                $next_pos = $pos2
                  if ( ( $next_pos == -1 and $pos2 > -1 )
                    or ( $pos2 > -1 and $next_pos > $pos2 ) );
                $next_pos = $pos3
                  if ( ( $next_pos == -1 and $pos3 > -1 )
                    or ( $pos3 > -1 and $next_pos > $pos3 ) );

                my $pos_end = index( $test_text, ']', $next_pos );

                my $weblink =
                  substr( $text, $next_pos, $pos_end - $next_pos + 1 );

                if ( $weblink =~ /\n/ ) {
                    $found_text = $weblink if ( $found_text eq '' );
                }
                $pos = $next_pos;
            }

            if ( $found_text ne '' ) {
                error_register( $error_code, substr( $found_text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 81
###########################################################################

sub error_081_ref_double {
    my $error_code = 81;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_of_ref = @ref;
            foreach my $i ( 0 .. $number_of_ref - 2 ) {

                foreach my $j ( $i + 1 .. $number_of_ref - 1 ) {

                    if ( $ref[$i] eq $ref[$j] ) {
                        error_register( $error_code,
                            substr( $ref[$i], 0, 40 ) );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 82
###########################################################################

sub error_082_link_to_other_wikiproject {
    my $error_code = 82;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@links_all) {

                my $current_link = $_;
                foreach (@foundation_projects) {
                    if (   $current_link =~ /^\[\[([ ]+)?$_:/i
                        or $current_link =~ /^\[\[([ ]+)?:([ ]+)?$_:/i )
                    {
                        error_register( $error_code, $current_link );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 83
###########################################################################

sub error_083_headline_only_three_and_later_level_two {
    my $error_code = 83;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'yes' ) {
                    error_register( $error_code, $headlines[0] );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 84
###########################################################################

sub error_084_section_without_text {
    my $error_code = 84;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $number_of_headlines = @headlines;

            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {

                # Check level of headline and next headline

                my $level_one = $headlines[$i];
                my $level_two = $headlines[ $i + 1 ];

                $level_one =~ s/^([=]+)//;
                $level_two =~ s/^([=]+)//;
                $level_one = length( $headlines[$i] ) - length($level_one);
                $level_two =
                  length( $headlines[ $i + 1 ] ) - length($level_two);

                # If headline's level is identical or lower to next headline
                # And headline's level is ==
                if ( $level_one >= $level_two and $level_one == 2 ) {
                    if ( $section[$i] ) {
                        my $test_section  = $section[ $i + 1 ];
                        my $test_headline = $headlines[$i];
                        $test_headline    =~ s/\n//g;

                        $test_section =
                          substr( $test_section, length($test_headline) )
                          if ($test_section);

                        if ($test_section) {
                            $test_section =~ s/[ ]//g;
                            $test_section =~ s/\n//g;
                            $test_section =~ s/\t//g;

                            if ( $test_section eq q{} ) {
                                error_register( $error_code, $headlines[$i] );
                            }
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 85
###########################################################################

sub error_085_tag_without_content {
    my $error_code = 85;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            my $found_pos  = -1;

            $found_pos = index( $text, '<noinclude></noinclude>' )
              if ( index( $text, '<noinclude></noinclude>' ) > -1 );
            $found_pos = index( $text, '<onlyinclude></onlyinclude>' )
              if ( index( $text, '<onlyinclude></onlyinclude>' ) > -1 );
            $found_pos = index( $text, '<includeonly></includeonly>' )
              if ( index( $text, '<includeonly></includeonly>' ) > -1 );
            $found_pos = index( $text, '<noinclude>' . "\n" . '</noinclude>' )
              if ( index( $text, '<noinclude>' . "\n" . '</noinclude>' ) > -1 );
            $found_pos =
              index( $text, '<onlyinclude>' . "\n" . '</onlyinclude>' )
              if (
                index( $text, '<onlyinclude>' . "\n" . '</onlyinclude>' ) >
                -1 );
            $found_pos =
              index( $text, '<includeonly>' . "\n" . '</includeonly>' )
              if (
                index( $text, '<includeonly>' . "\n" . '</includeonly>' ) >
                -1 );

            if ( $found_pos != -1 ) {
                $found_text = substr( $text, $found_pos, 40 );
                $found_text =~ s/\n//g;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 86
###########################################################################

sub error_086_link_with_two_brackets_to_external_source {
    my $error_code = 86;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $text;
            if ( $test_text =~ /(\[\[\s*https?:\/\/[^\]:]*)/i ) {
                error_register( $error_code, substr( $1, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 87
###########################################################################

sub error_087_html_names_entities_without_semicolon {
    my $error_code = 87;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $pos       = -1;
            my $test_text = lc($text);

            # REFS USE & FOR INPUT
            $test_text =~ s/<ref>(.*?)ref>//sg;
            $test_text =~ s/<ref name(.*?)ref>//sg;
            $test_text =~ s/\[http(.*?)\]//sg;
            $test_text =~ s/\^http(.*?)//sg;
            $test_text =~ s/\{\{cit(.*?)\}\}//sg;

            # See http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
            while ( $test_text =~ /&sup2[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&sup3[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&auml[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&ouml[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&uuml[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&szlig[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&aring[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&hellip[^;]/g ) { $pos = pos($test_text) }

            while ( $test_text =~ /&quot[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&minus[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&oline[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&cent[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&pound[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&euro[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&sect[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&dagger[^;]/g ) { $pos = pos($test_text) }

            while ( $test_text =~ /&lsquo[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&rsquo[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&middot[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&bull[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&copy[^;]/g )   { $pos = pos($test_text) }
            while ( $test_text =~ /&reg[^;]/g )    { $pos = pos($test_text) }
            while ( $test_text =~ /&trade[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&iquest[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&iexcl[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&aelig[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&ccedil[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&ntilde[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&acirc[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&aacute[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&agrave[^;]/g ) { $pos = pos($test_text) }

            #arrows
            while ( $test_text =~ /&darr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&uarr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&crarr[^;]/g ) { $pos = pos($test_text) }
            while ( $test_text =~ /&rarr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&larr[^;]/g )  { $pos = pos($test_text) }
            while ( $test_text =~ /&harr[^;]/g )  { $pos = pos($test_text) }

            if ( $pos > -1 ) {
                $test_text = substr( $test_text, ( $pos - 6 ), 40 );
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 88
###########################################################################

sub error_088_defaultsort_with_first_blank {
    my $error_code = 88;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort     = -1;
            my $current_magicword = q{};
            foreach ( @{$magicword_defaultsort} ) {
                if ( $isDefaultsort == -1 and index( $text, $_ ) > -1 ) {
                    $isDefaultsort = index( $text, $_ );
                    $current_magicword = $_;
                }
            }

            if ( $isDefaultsort > -1 ) {
                my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
                my $test_text = substr( $text, $isDefaultsort, $pos2 );

                my $sortkey = $test_text;
                $sortkey =~ s/^([ ]+)?$current_magicword//;
                $sortkey =~ s/^([ ]+)?://;

                if ( index( $sortkey, ' ' ) == 0 ) {
                    error_register( $error_code, $test_text );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 89
###########################################################################

sub error_089_defaultsort_with_capitalization_in_the_middle_of_the_word {

    return ();
}

###########################################################################
## ERROR 90
###########################################################################

sub error_090_defaultsort_with_lowercase_letters {

    return ();
}

###########################################################################
## ERROR 91
###########################################################################

sub error_091_title_with_lowercase_letters_and_no_defaultsort {

    return ();
}

###########################################################################
## ERROR 92
###########################################################################

sub error_092_headline_double {
    my $error_code = 92;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            my $found_text          = q{};
            my $number_of_headlines = @headlines;
            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {
                my $first_headline   = $headlines[$i];
                my $secound_headline = $headlines[ $i + 1 ];

                if ( $first_headline eq $secound_headline ) {
                    $found_text = $headlines[$i];
                }
            }
            if ( $found_text ne '' ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

######################################################################
######################################################################
######################################################################

sub error_register {
    my ( $error_code, $notice ) = @_;

    $notice =~ s/\n//g;

    print "\t" . $error_code . "\t" . $title . "\t" . $notice . "\n";

    $Error_number_counter[$error_code] = $Error_number_counter[$error_code] + 1;
    $error_counter = $error_counter + 1;

    insert_into_db( $error_code, $notice );

    return ();
}

######################################################################

sub get_broken_tag {
    my ( $tag_open, $tag_close ) = @_;
    my $text_snippet = q{};
    my $found        = -1;    # Open tag could be at position 0

    my $test_text = lc($text);

    my $pos_open  = index( $test_text, $tag_open );
    my $pos_open2 = index( $test_text, $tag_open, $pos_open + 3 );
    my $pos_close = index( $test_text, $tag_close );

    while ( $found == -1 ) {
        if ( $pos_open2 == -1 ) {    # End of article and no closing tag found
            $found = $pos_open;
        }
        elsif ( $pos_open2 < $pos_close ) {
            $found = $pos_open;
        }
        else {
            $pos_open  = $pos_open2;
            $pos_open2 = index( $test_text, $tag_open, $pos_open + 3 );
            $pos_close = index( $test_text, $tag_close, $pos_close + 3 );
        }
    }

    $text_snippet = substr( $text, $found, 40 );
    return ($text_snippet);
}

######################################################################}

sub insert_into_db {
    my ( $code, $notice ) = @_;
    my ( $table_name, $date_found, $article_title );

    $notice = substr( $notice, 0, 100 );    # Truncate notice.
    $article_title = $title;

    # Problem: sql-command insert, apostrophe ' or backslash \ in text
    $article_title =~ s/\\/\\\\/g;
    $article_title =~ s/'/\\'/g;
    $notice =~ s/\\/\\\\/g;
    $notice =~ s/'/\\'/g;

    $notice =~ s/\&/&amp;/g;
    $notice =~ s/</&lt;/g;
    $notice =~ s/>/&gt;/g;
    $notice =~ s/\"/&quot;/g;

    if ( $dump_or_live eq 'live' or $dump_or_live eq 'delay' ) {
        $table_name = 'cw_error';
        $date_found = strftime( '%F %T', gmtime() );
    }
    else {
        $table_name = 'cw_dumpscan';
        $date_found = $time_found;
    }

    my $sql_text =
        "INSERT IGNORE INTO "
      . $table_name
      . " VALUES ( '"
      . $project . "', '"
      . $article_title . "', "
      . $code . ", '"
      . $notice
      . "', 0, '"
      . $time_found . "' );";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    return ();
}

######################################################################

# Left trim string merciless, but only to full words (result will
# never be longer than $Length characters).
sub text_reduce_to_end {
    my ( $s, $Length ) = @_;

    if ( length($s) > $Length ) {

        # Find first space in the last $Length characters of $s.
        my $pos = index( $s, ' ', length($s) - $Length );

        # If there is no space, just take the last $Length characters.
        $pos = length($s) - $Length if ( $pos == -1 );

        return substr( $s, $pos + 1 );
    }
    else {
        return $s;
    }
}

######################################################################

sub print_line {

    #print a line for better structure of output
    print '-' x 80;
    print "\n";

    return ();
}

######################################################################

sub two_column_display {

    # Print all output in two column well formed
    my $text1 = shift;
    my $text2 = shift;
    printf "%-30s %-30s\n", $text1, $text2;

    return ();
}

######################################################################

sub usage {
    print STDERR "To scan a dump:\n"
      . "$0 -p dewiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --tt-file TEMPLATETIGERFILE --silent\n"
      . "To scan a list of pages live:\n"
      . "$0 -p dewiki\n"
      . "$0 -p dewiki --silent\n"
      . "$0 -p dewiki --load new/done/dump/last_change/old\n";

    return ();
}

###########################################################################
###########################################################################
## MAIN PROGRAM
###########################################################################
###########################################################################

my ( $load_mode, $DumpFilename, $TTFilename, $dump_date_for_output );

my @Options = (
    'load=s'       => \$load_mode,
    'project|p=s'  => \$project,
    'database|D=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'dumpfile=s'   => \$DumpFilename,
    'tt-file=s'    => \$TTFilename,
    'check'        => \$CheckOnlyOne,
);

if (
    !GetOptions(
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
        @Options,
    )
    || defined($DumpFilename) != defined($TTFilename)
  )
{
    usage();
    exit(1);
}

if ( !defined($project) ) {
    usage();
    die("$0: No project name, for example: \"-p dewiki\"\n");
}

$language = $project;
$language =~ s/source$//;
$language =~ s/wiki$//;

print "\n\n";
print_line();
two_column_display( 'Start time:',
    ( strftime "%a %b %e %H:%M:%S %Y", localtime ) );
$time_found = strftime( '%F %T', gmtime() );

if ( defined($DumpFilename) ) {
    $dump_or_live = 'dump';

    # GET DATE FROM THE DUMP FILENAME
    $dump_date_for_output = $DumpFilename;
    $dump_date_for_output =~
s/^(?:.*\/)?\Q$project\E-(\d{4})(\d{2})(\d{2})-pages-articles\.xml\.bz2$/$1-$2-$3/;

    # GET DUMP FILE SIZE, UNCOMPRESS AND THEN OPEN VIA METAWIKI::DumpFile
    #my $dump;
    $file_size = ( stat($DumpFilename) )[7];

    #open( $dump, '-|', 'bzcat', '-q', $DumpFilename )
    #  or die("Couldn't open dump file '$DumpFilename'");

    $DumpFilename =
      '/home/bgwhite/windows/enwiki/enwiki-20130708-pages-articles.xml';
    $dump_date_for_output = '2013-07-08';
    $pages                = $pmwd->pages($DumpFilename);

    #$pages = $pmwd->pages($dump);

    # OPEN TEMPLATETIGER FILE
    if (
        !(
            $TTFile = File::Temp->new(
                DIR      => $ENV{'HOME'} . '/var/tmp',
                TEMPLATE => $project . '-' . $dump_date_for_output . '-XXXX',
                SUFFIX   => '.txt',
                UNLINK   => 0
            )
        )
      )
    {
        die("Couldn't open temporary file for Templatetiger\n");
    }
    binmode( $TTFile, ":encoding(UTF-8)" );
}
elsif ( $load_mode eq 'live' ) {
    $dump_or_live = 'live';
}
elsif ( $load_mode eq 'delay' ) {
    $dump_or_live = 'delay';
}
else {
    die("No load name, for example: \"-l live\"\n");
}

two_column_display( 'Project:',   $project );
two_column_display( 'Scan type:', $dump_or_live . " scan" );

open_db();
clearDumpscanTable() if ( $dump_or_live eq 'dump' );
getErrors();
readMetadata();

# MAIN ROUTINE - SCAN PAGES FOR ERRORS
scan_pages();

updateDumpDate($dump_date_for_output) if ( $dump_or_live eq 'dump' );
update_table_cw_error_from_dump();
delete_done_article_from_db();

close_db();

# CLOSE TEMPLATETIGER FILE
if ( defined($TTFile) ) {

    # Move Templatetiger file to spool.
    $TTFile->close() or die( $! . "\n" );
    if ( !rename( $TTFile->filename(), $TTFilename ) ) {
        die(    "Couldn't rename temporary Templatetiger file from "
              . $TTFile->filename() . ' to '
              . $TTFilename
              . "\n" );
    }
    if ( !chmod( 0664, $TTFilename ) ) {
        die( "Couldn't chmod 664 Templatetiger file " . $TTFilename . "\n" );
    }
    undef($TTFile);
}

print_line();
two_column_display( 'Articles checked:', $artcount );
two_column_display( 'Errors found:',     ++$error_counter );

$time_end = time() - $time_start;
printf "Program run time:              %d hours, %d minutes and %d seconds\n\n",
  ( gmtime $time_end )[ 2, 1, 0 ];
print "PROGRAM FINISHED\n";
print_line();
