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
##       VERSION: 09/20/2013
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

##############################
##  Program wide variables
##############################

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

# Template list retrieved from Translation file
our @Template_list;

# Filename that contains a list of articles titles for list mode
our $ListFilename;

# Filename that contains the dump file for dump mode
our $DumpFilename;

# Total number of Errors
our $number_of_error_description = 0;

##############################
##  Wiki-special variables
##############################

our @namespace;    # Namespace values
                   # 0 number
                   # 1 namespace in project language
                   # 2 namespace in english language

our @namespacealiases;    # Namespacealiases values
                          # 0 number
                          # 1 namespacealias

our @namespace_cat;       # All namespaces for categorys
our @namespace_image;     # All namespaces for images
our @namespace_templates; # All namespaces for templates
our $image_regex = q{};   # Regex used in get_images()
our $cat_regex   = q{};   # Regex used in get_categories()

our $magicword_defaultsort;

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

# See http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
our @html_named_entities = qw( aacute acirc aeligi agrave aring  aumla bull
  ccedil cent copy dagger euro hellip iexcl iquest lsquo  middot minus
  ntilde oline ouml pound quot reg rswuo sect sup2 sup3 szling trade uuml
  crarr darr harr larr rarr uarr );

###############################
## Variables for one article
###############################

our $title                 = q{};    # Title of current article
our $text                  = q{};    # Text of current article
our $lc_text               = q{};    # Text of current article in lower case
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

        # OPEN DUMPFILE BASED IF COMPRESSED OR NOT
        if ( $DumpFilename =~ /(.*?)\.xml\.bz2$/ ) {
            my $dump;
            open( $dump, '-|', 'bzcat', '-q', $DumpFilename )
              or die("Couldn't open dump file '$DumpFilename'");
            $pages = $pmwd->pages($dump);
        }
        else {
            $pages     = $pmwd->pages($DumpFilename);
            $file_size = ( stat($DumpFilename) )[7];
        }

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
    elsif ( $dump_or_live eq 'list' ) {
        list_scan();
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
    my $bytes = $pages->current_byte;

    if ( $file_size > 0 ) {
        my $percent = int( $bytes / $file_size * 100 );
        printf( "   %7d articles;%10s processed;%3d%% completed\n",
            ( $artcount, pretty_bytes($bytes), $percent ) );
    }
    else {
        printf( "   %7d articles;%10s processed\n",
            ( $artcount, pretty_bytes($bytes) ) );
    }

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
    my $error_count = 0;

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
        $magicword_defaultsort = $aliases if ( $name eq 'defaultsort' );
    }

    return ();
}

###########################################################################
##  READ TEMPLATES GIVEN IN TRANSLATION FILE
###########################################################################

sub readTemplates {

    my $template_sql;

    foreach my $i ( 1 .. $number_of_error_description ) {

        $Template_list[$i][0] = '-9999';

        my $sth = $dbh->prepare(
            'SELECT templates FROM cw_template WHERE error=? AND project=?');
        $sth->execute( $i, $project )
          or die "Cannot execute: " . $sth->errstr . "\n";

        $sth->bind_col( 1, \$template_sql );
        while ( $sth->fetchrow_arrayref ) {
            if ( defined($template_sql) ) {
                if ( $Template_list[$i][0] eq '-9999' ) {
                    shift( @{ $Template_list[$i] } );
                }
                push( @{ $Template_list[$i] }, lc($template_sql) );
            }
        }
    }

    return ();
}

###########################################################################
## CHECK ARTICLES VIA A LIVE SCAN
###########################################################################

sub list_scan {

    $page_namespace = 0;
    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'http',
            host     => $ServerName,
        }
    );

    if ( !defined($ListFilename) ) {
        die "The filename of the list was not defined";
    }

    open( my $list_of_titles, '<:encoding(UTF-8)', $ListFilename )
      or die 'Could not open file ' . $ListFilename . "\n";

    while (<$list_of_titles>) {
        set_variables_for_article();
        chomp($_);
        $title = $_;
        $text  = $bot->get_text($title);
        if ( defined($text) ) {
            check_article();
        }
    }

    close($list_of_titles);
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

    $lc_text = lc($text);

    #------------------------------------------------------
    # Following calls do not interact with other get_* or error #'s
    #------------------------------------------------------

    # CALLS #28
    get_tables();

    # CALLS #69, #70, #71, #72 ISBN CHECKS
    get_isbn();

    #------------------------------------------------------
    # Following interacts with other get_* or error #'s
    #------------------------------------------------------

    # CREATES @ref - USED IN #81
    get_ref();

    # CREATES @templates_all - USED IN #12, #31
    # CALLS #43
    get_templates_all();

    # DOES TEMPLATETIGER
    # USES @templates_all
    # CREATES @template - USED IN #59, #60
    get_template();

  # CREATES @links_all & @images_all - USED IN #65, #66, #67, #68, #74, #76, #82
  # CALLS #10
    get_links();

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

        $nowiki_begin = () = $test_text =~ /<nowiki>/g;
        $nowiki_end   = () = $test_text =~ /<\/nowiki>/g;

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
## GET TABLES
###########################################################################

sub get_tables {

    my $test_text = $text;

    my $tag_open_num  = () = $test_text =~ /\{\|/g;
    my $tag_close_num = () = $test_text =~ /\|\}/g;

    my $diff = $tag_open_num - $tag_close_num;

    if ( $diff > 0 ) {

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
        my $test_text = uc($text);

        if ( $test_text =~ / ISBN([-]|[:])/g ) {
            my $output = substr( $test_text, pos($test_text) - 5, 16 );
            error_069_isbn_wrong_syntax($output);
        }

        while ( $test_text =~ /ISBN([ ]|[-]|[=]|[:])/g ) {
            my $pos_start = pos($test_text) - 5;
            my $current_isbn = substr( $test_text, $pos_start );

            $current_isbn =~
/\b(?:ISBN(?:-?1[03])?:?\s*|(ISBN\s*=\s*))([\dX ‐—–-]{4,24}[\dX])\b/gi;

            if ( defined $2 ) {
                my $isbn       = $2;
                my $isbn_strip = $2;
                $isbn_strip =~ s/[^0-9X]//g;

                my $digits = length($isbn_strip);

                if ( $digits != 10 and $digits != 13 ) {
                    error_070_isbn_wrong_length($isbn);
                }
                elsif ( index( $isbn_strip, 'X' ) != 9
                    and index( $isbn_strip, 'X' ) > -1 )
                {
                    error_071_isbn_wrong_pos_X($isbn);
                }
                else {
                    if ( $digits == 10 ) {
                        my $sum;
                        my @digits = split //, $isbn_strip;
                        foreach ( reverse 2 .. 10 ) {
                            $sum += $_ * ( shift @digits );
                        }
                        my $checksum = ( 11 - ( $sum % 11 ) ) % 11;
                        $checksum = 'X' if $checksum == 10;

                        if ( $checksum ne substr( $isbn_strip, 9, 1 ) ) {
                            $isbn = $isbn . ' vs ' . $checksum;
                            error_072_isbn_10_wrong_checksum($isbn);
                        }
                    }
                    elsif ( $digits == 13 ) {
                        my $sum;
                        foreach my $index ( 0, 2, 4, 6, 8, 10 ) {
                            $sum += substr( $isbn_strip, $index, 1 );
                            $sum += 3 * substr( $isbn_strip, $index + 1, 1 );
                        }
                        my $checksum =
                          ( 10 * ( int( $sum / 10 ) + 1 ) - $sum ) % 10;

                        if ( $checksum ne substr( $isbn_strip, 12, 1 ) ) {
                            $isbn = $isbn . ' vs ' . $checksum;
                            error_073_isbn_13_wrong_checksum($isbn);
                        }
                    }
                }
            }
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
    my $test_text = $text;

    $test_text =~ s/\n//g;    # Delete all breaks     --> only one line
    $test_text =~ s/\t//g;    # Delete all tabulator  --> better for output

    while ( $test_text =~ /\{\{/g ) {

        $pos_start = pos($test_text) - 2;
        my $temp_text      = substr( $test_text, $pos_start );
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
                $value    =~ s/^[ ]+//g;
                $value    =~ s/[ ]+$//g;

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

    return ();
}

###########################################################################
##
###########################################################################

sub get_links {

    my $pos_start = 0;
    my $pos_end   = 0;

    my $test_text = $text;

    $test_text =~ s/\n//g;

    while ( $test_text =~ /\[\[/g ) {

        $pos_start = pos($test_text) - 2;
        my $link_text      = substr( $test_text, $pos_start );
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

sub get_ref {

    my $pos_start_old = 0;
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

    if ( index( $lc_text, '#redirect' ) > -1 ) {
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
        my $pos_end            = 0;
        my $pos_start          = 0;
        my $counter            = 0;
        my $test_text          = $text;
        my $search_word        = $namespace_cat_word;

        while ( $test_text =~ /\[\[([ ]+)?($search_word:)/ig ) {
            $pos_start = pos($test_text) - length($search_word) - 1;
            $pos_end   = index( $test_text, ']]', $pos_start );
            $pos_start = $pos_start - 2;

            if ( $pos_start > -1 and $pos_end > -1 ) {

                $counter               = ++$category_counter;
                $pos_end               = $pos_end + 2;
                $category[$counter][0] = $pos_start;
                $category[$counter][1] = $pos_end;
                $category[$counter][4] =
                  substr( $test_text, $pos_start, $pos_end - $pos_start );
                $category[$counter][2] = $category[$counter][4];
                $category[$counter][3] = $category[$counter][4];

                $category[$counter][2] =~ s/\[\[//g;        # Delete [[
                $category[$counter][2] =~ s/^([ ]+)?//g;    # Delete blank
                $category[$counter][2] =~ s/\]\]//g;        # Delete ]]
                $category[$counter][2] =~ s/^$namespace_cat_word//i;
                $category[$counter][2] =~ s/^://;                   # Delete :
                $category[$counter][2] =~ s/\|(.)*//g;              # Delete |xy
                $category[$counter][2] =~ s/^ //g;    # Delete blank
                $category[$counter][2] =~ s/ $//g;    # Delete blank

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
        error_009_more_then_one_category_in_a_line();
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
        error_011_html_named_entities();
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
        error_029_gallery_no_correct_end();

        #error_030_image_without_description('');          # DEACTIVATED
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
        error_062_headline_alone();    # DEACTIVATED
        error_063_html_text_style_elements_small_ref_sub_sup();
        error_064_link_equal_linktext();
        error_065_image_description_with_break();
        error_066_image_description_with_full_small();
        error_067_reference_after_punctuation();
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
        error_087_html_named_entities_without_semicolon();
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_line = q{};
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
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if (   index( $text, '<ref>' ) > -1
                or index( $text, '<ref name' ) > -1 )
            {

                my $test      = "false";
                my $test_text = $lc_text;

                $test = "true"
                  if (  $test_text =~ /<[ ]?+references>/
                    and $test_text =~ /<[ ]?+\/references>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references[ ]?+\/>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references group/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refbegin/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refend/ );

                if ( $Template_list[$error_code][0] ne '-9999' ) {

                    my @ack = @{ $Template_list[$error_code] };

                    for my $temp (@ack) {
                        if ( $test_text =~ /\{\{[ ]?+($temp)/ ) {
                            $test = "true";
                        }
                    }
                }
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
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'hewiki' )
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
                $test_text =~ s/[-–:,\.\/\(\)0-9 A-Za-z!\?']//g;

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

            if ( $text =~
                /\[\[($cat_regex):(.*?)\]\]([ ]*)\[\[($cat_regex):(.*?)\]\]/g )
            {

                my $error_text =
                    '[['
                  . $1 . ':'
                  . $2 . ']]'
                  . $3 . '[['
                  . $4 . ':'
                  . $5 . "]]\n";
                error_register( $error_code, substr( $error_text, 0, 40 ) );
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

sub error_011_html_named_entities {
    my $error_code = 11;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos       = -1;
            my $test_text = $lc_text;

            foreach (@html_named_entities) {
                if ( $test_text =~ /&$_;/g ) {
                    $pos = $-[0];
                }
            }

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
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

            my $test_text = $lc_text;

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
                $search = "\x{200E}|\x{FEFF}\x{200B}\x{2028}";
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

            my $test_text = $lc_text;
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
        if ( $comment ne ''
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $test = "false";

            if ( $Template_list[$error_code][0] ne '-9999' ) {

                my @ack = @{ $Template_list[$error_code] };

                for my $temp (@ack) {
                    if ( index( $lc_text, $temp ) == -1 ) {
                        $test = "true";
                    }
                }
            }
            if ( $test eq "true" ) {
                error_register( $error_code, $comment );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 29
###########################################################################

sub error_029_gallery_no_correct_end {
    my $error_code = 29;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;

            if ( $test_text =~ /<gallery/ ) {
                my $gallery_begin = 0;
                my $gallery_end   = 0;

                $gallery_begin = () = $test_text =~ /<gallery/g;
                $gallery_end   = () = $test_text =~ /<\/gallery>/g;

                if ( $gallery_begin > $gallery_end ) {
                    my $snippet = get_broken_tag( '<gallery', '</gallery>' );
                    error_register( $error_code, $snippet );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 30
###########################################################################

sub error_030_image_without_description {

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
            my $test_text = $lc_text;

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

            my $test_text = $lc_text;
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
            if ( $lc_text =~ /#redirect[ ]?+[^ :\[][ ]?+\[/ ) {
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
            and $project ne 'hewiki'
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

            my $test_text = $lc_text;
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

            my $test_text = $lc_text;
            if ( $test_text =~ /<p>|<p / ) {

                # https://bugzilla.wikimedia.org/show_bug.cgi?id=6200
                if ( $test_text !~
                    /<blockquote|\{\{quote\s*|\{\{cquote|\{\{quotation/ )
                {
                    $test_text =~ s/<ref(.*?)<\/ref>//sg;
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

            my $test_text = $lc_text;
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

            my $test_text = $lc_text;
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

            my $test_text     = $text;
            my $test_text_1_a = $test_text;
            my $test_text_1_b = $test_text;

            if ( ( $test_text_1_a =~ s/\[\[//g ) !=
                ( $test_text_1_b =~ s/\]\]//g ) )
            {
                my $found_text = q{};
                my $begin_time = time();
                while ( $test_text =~ /\]\]/g ) {

                    # Begin of link
                    my $pos_end     = pos($test_text) - 2;
                    my $link_text   = substr( $test_text, 0, $pos_end );
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
    my $error_code = 47;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $tag_open         = "{{";
            my $tag_close        = "}}";
            my $look_ahead_open  = 0;
            my $look_ahead_close = 0;
            my $look_ahead       = 0;
            my $test_text        = $text;

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

            # OK (MUST) TO HAVE IN IMAGEMAPS
            $test_text =~ s/<imagemap>(.*?)<\/imagemap>//sg;

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

            my $test_text = $lc_text;
            my $pos       = -1;
            $pos = index( $test_text, '<h2>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h3>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h4>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h5>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h6>' )  if ( $pos == -1 );
            $pos = index( $test_text, '</h2>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h3>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h4>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h5>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h6>' ) if ( $pos == -1 );
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
## ERROR 50
###########################################################################

sub error_050_dash {
    my $error_code = 50;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        my $pos = -1;
        $pos = index( $lc_text, '&ndash;' );
        $pos = index( $lc_text, '&mdash;' ) if $pos == -1;

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

            my $test_text = $lc_text;
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
            $pos = index( $lc_text, '->' );
            $pos = index( $lc_text, '<-' ) if $pos == -1;
            $pos = index( $lc_text, '<=' ) if $pos == -1;
            $pos = index( $lc_text, '=>' ) if $pos == -1;

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

            if ( $text =~ /<\/ref>[ ]{0,2}(\.|,|\?|:|! )/ ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
            elsif ( $text =~ /(<ref name(.*?)\/>[ ]{0,2}(\.|,|\?|:|! ))/ ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
            elsif ( $Template_list[$error_code][0] ne '-9999' ) {

                my $pos = -1;
                my @ack = @{ $Template_list[$error_code] };

                for my $temp (@ack) {
                    if ( $text =~
                        /\{\{[ ]?+$temp[^\}]*\}{2,4}[ ]{0,2}([\.,\?:]|! )/
                        and $pos == -1 )
                    {
                        $pos = $-[0];
                    }
                }
                if ( $pos > -1 ) {
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

    return ();
}

###########################################################################
## ERROR 63
###########################################################################

sub error_063_html_text_style_elements_small_ref_sub_sup {
    my $error_code = 63;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;
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

            # OK (MUST) TO HAVE IN TIMELINE
            $temp_text =~ s/<timeline>(.*?)<\/timeline>//sg;

            # Account for [[Foo|foo]] and [[foo|Foo]] by capitalizing the
            # the first character after the [ and |.  Acount for
            # [[foo_foo|foo foo]] by removing all _.

            $temp_text =~ tr/_/ /;
            $temp_text =~ s/\[\[\s*([\w])/\[\[\u$1/;
            $temp_text =~ s/\[\[\s*([^|:]*)\s*\|\s*(.)/\[\[$1\|\u$2/;
            if ( $temp_text =~ /(\[\[\s*([^|:]*)\s*\|\s*\2\s*\]\])/ ) {
                my $found_text = $1;
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
    my $error_code = 67;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = -1;
            $pos = index( $text, '.<ref' )   if ( $pos == -1 );
            $pos = index( $text, '. <ref' )  if ( $pos == -1 );
            $pos = index( $text, '.  <ref' ) if ( $pos == -1 );
            $pos = index( $text, '!<ref' )   if ( $pos == -1 );
            $pos = index( $text, '! <ref' )  if ( $pos == -1 );
            $pos = index( $text, '!  <ref' ) if ( $pos == -1 );
            $pos = index( $text, '?<ref' )   if ( $pos == -1 );
            $pos = index( $text, '? <ref' )  if ( $pos == -1 );
            $pos = index( $text, '?  <ref' ) if ( $pos == -1 );
            $pos = index( $text, ',<ref' )   if ( $pos == -1 );
            $pos = index( $text, ' ,<ref' )  if ( $pos == -1 );
            $pos = index( $text, '  ,<ref' ) if ( $pos == -1 );
            $pos = index( $text, ':<ref' )   if ( $pos == -1 );
            $pos = index( $text, ' :<ref' )  if ( $pos == -1 );
            $pos = index( $text, '  :<ref' ) if ( $pos == -1 );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

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

            my $test_text      = $lc_text;
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

            my $test_text  = $lc_text;
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

            my $pos_start_old = 0;
            my $end_search    = 0;
            my $test_text     = $lc_text;

            while ( $end_search == 0 ) {
                my $pos_start   = 0;
                my $pos_start_s = 0;
                my $pos_end     = 0;
                $end_search = 1;

                $pos_start   = index( $test_text, '[http://',  $pos_start_old );
                $pos_start_s = index( $test_text, '[https://', $pos_start_old );
                if ( ( $pos_start_s < $pos_start ) and ( $pos_start_s > -1 ) ) {
                    $pos_start = $pos_start_s;
                }
                $pos_end = index( $test_text, ']', $pos_start );

                if ( $pos_start > -1 and $pos_end > -1 ) {

                    $end_search    = 0;
                    $pos_start_old = $pos_end;

                    my $weblink =
                      substr( $test_text, $pos_start, $pos_end - $pos_start );

                    if ( $weblink =~ /\n/ ) {
                        error_register( $error_code,
                            substr( $weblink, 0, 40 ) );
                    }
                }
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

            my $section_text = q{};
            my @my_lines = split( /\n/, $text_without_comments );
            my @my_headlines;
            my @my_section;

            foreach (@my_lines) {
                my $current_line = $_;

                if ( substr( $current_line, 0, 1 ) eq '=' ) {
                    push( @my_section, $section_text );
                    $section_text = q{};
                    push( @my_headlines, $current_line );
                }
                $section_text = $section_text . $_ . "\n";
            }
            push( @my_section, $section_text );

            my $number_of_headlines = @my_headlines;

            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {

                # Check level of headline and next headline

                my $level_one = $my_headlines[$i];
                my $level_two = $my_headlines[ $i + 1 ];

                $level_one =~ s/^([=]+)//;
                $level_two =~ s/^([=]+)//;
                $level_one = length( $my_headlines[$i] ) - length($level_one);
                $level_two =
                  length( $my_headlines[ $i + 1 ] ) - length($level_two);

                # If headline's level is identical or lower to next headline
                # And headline's level is ==
                if ( $level_one >= $level_two and $level_one == 2 ) {
                    if ( $my_section[$i] ) {
                        my $test_section  = $my_section[ $i + 1 ];
                        my $test_headline = $my_headlines[$i];
                        $test_headline =~ s/\n//g;

                        $test_section =
                          substr( $test_section, length($test_headline) )
                          if ($test_section);

                        if ($test_section) {
                            $test_section =~ s/[ ]//g;
                            $test_section =~ s/\n//g;
                            $test_section =~ s/\t//g;

                            if ( $test_section eq q{} ) {
                                error_register( $error_code,
                                    $my_headlines[$i] );
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

sub error_087_html_named_entities_without_semicolon {
    my $error_code = 87;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $pos       = -1;
            my $test_text = $text;

            # IMAGE'S CAN HAVE HTML NAMED ENTITES AS PART OF THEIR FILENAME
            foreach (@images_all) {
                $test_text =~ s/\Q$_\E//sg;
            }

            $test_text = lc($test_text);

            # REFS USE '&' FOR INPUT
            $test_text =~ s/<ref(.*?)>https?:(.*?)<\/ref>//sg;
            $test_text =~ s/https?:(.*?)\n//g;

            foreach (@html_named_entities) {
                if ( $test_text =~ /&$_[^;]/g ) {
                    $pos = $-[0];
                }
            }

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $test_text, $pos, 40 ) );
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

    my $sth = $dbh->prepare(
        'SELECT OK FROM cw_whitelist WHERE error=? AND title=? AND project=?');
    $sth->execute( $error_code, $title, $project )
      or die "Cannot execute: " . $sth->errstr . "\n";

    my $whitelist = $sth->fetchrow_arrayref();

    if ( !defined($whitelist) ) {
        $notice =~ s/\n//g;

        print "\t" . $error_code . "\t" . $title . "\t" . $notice . "\n";

        $Error_number_counter[$error_code] =
          $Error_number_counter[$error_code] + 1;
        $error_counter = $error_counter + 1;

        insert_into_db( $error_code, $notice );
    }
    else {
        print $title . " is in whitelist with error: " . $error_code . "\n";
    }

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
    $notice        =~ s/\\/\\\\/g;
    $notice        =~ s/'/\\'/g;

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
      . "$0 -p dewiki --dumpfile DUMPFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --silent\n"
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

my ( $load_mode, $dump_date_for_output );

my @Options = (
    'load=s'       => \$load_mode,
    'project|p=s'  => \$project,
    'database|D=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'dumpfile=s'   => \$DumpFilename,
    'listfile=s'   => \$ListFilename,
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
s/^(?:.*\/)?\Q$project\E-(\d{4})(\d{2})(\d{2})-pages-articles\.xml(.*?)$/$1-$2-$3/;
}
elsif ( $load_mode eq 'live' ) {
    $dump_or_live = 'live';
}
elsif ( $load_mode eq 'delay' ) {
    $dump_or_live = 'delay';
}
elsif ( $load_mode eq 'list' ) {
    $dump_or_live = 'list';
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
readTemplates();

# MAIN ROUTINE - SCAN PAGES FOR ERRORS
scan_pages();

updateDumpDate($dump_date_for_output) if ( $dump_or_live eq 'dump' );
update_table_cw_error_from_dump();
delete_done_article_from_db();

close_db();

print_line();
two_column_display( 'Articles checked:', $artcount );
two_column_display( 'Errors found:',     ++$error_counter );

$time_end = time() - $time_start;
printf "Program run time:              %d hours, %d minutes and %d seconds\n\n",
  ( gmtime $time_end )[ 2, 1, 0 ];
print "PROGRAM FINISHED\n";
print_line();
