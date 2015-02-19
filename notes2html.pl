use warnings;
use strict;
use diagnostics;

use File::Slurp;
use utf8;

use Getopt::Long;
use File::Basename;


my %files;
my %ids;

GetOptions (
    'debug'    => \my $debug
);

my $in_dir   = shift or die;
my $out_dir  = shift or die;



for my $pass (1..2) {
  for my $file (glob "$in_dir/*") {
    next if $file =~ /\.swp$/;
    next unless -f $file;
    next if $file =~ /\.[^\/\\]*$/;
    process_a_note($pass, $file);
  }
}



sub process_a_note { # {{{

  my $pass           = shift;
  my $file_with_path = shift;

  my $file           = basename ($file_with_path);

  my $level = 0;

  my $out;
  my $in_p = 0;

  my @h_stack;

  push @h_stack, {id => $file};
  my $current_id = $file;


  if ($pass == 2) { # {{{ Open html file, write <head> etc

    my $class_published = $files{$file}{publish_sign} eq '-' ? 'private' : 'public';

    open $out, '>:encoding(UTF-8)', "$out_dir/$file.html" or die "could not open $out_dir/$file.html";
    print $out "<!DOCTYPE html>\n";
    print $out qq{<html><head>
<title>$files{$file}{title}</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<link rel="stylesheet" type="text/css" href="notes.css"/>
</head><body class="$class_published"><h1>$files{$file}{title}</h1>
};

  } # }}}

  my @lines = read_file($file_with_path, binmode => ':utf8');


  my $publish_sign = shift @lines; # {{{
  chomp $publish_sign;

  if ($pass == 1) {
    die "$file, publish_sign: $publish_sign" unless $publish_sign eq '-' or $publish_sign eq '+';

    $files{$file}{publish_sign} = $publish_sign unless exists $files{$file}{publish_sign};
  }
  # }}}

  my $title_line = shift @lines; # {{{

  if ($pass == 1) {
    chomp $title_line;
    my $title;
    die ">$file< $title_line: no valid title" unless ($title) = $title_line =~ /^\$ *(.*)/;
  
    $files{$file}{title}=$title;
    $ids{$file}{title} = $title;
    $ids{$file}{file}  = $file;
  } # }}}

  for my $line (@lines) { # {{{
    my $id = $2 if $line =~ s/(^|\s)id=(\w+)//;

    if ($id) {

       if ($pass == 1) {
          die "$file: id $id already found in $ids{$id}{file}" if exists $ids{$id} and $ids{$id}{file} ne '?';
          $ids{$id}{file}=$file;
       }

    }

    my ($h) = $+ if $line =~ /^ *{ *(.*)/;


    if ($h) {

      $h =~ s/\s*$//;

      if ($pass == 1 and $id) {
        $ids{$id}{title} = $h;
        $ids{$id}{is_anchor} = 1;
      }
    }


    if ($h) {                    # {{{ Line contains start of a heading


      if ($pass == 2) {

        if ($in_p) {
          print $out "</p>";
          $in_p = 0;
        }
  
        print $out '<h' . ($level+2);
  
        print $out " id=\"$id\"" if $id;
        
        print $out ">$h</h" . ($level+2) .">\n";
  
        $level++;

      }

      my $stack_entry = {};
      if ($id) {
        $stack_entry->{id} = $id;
        $current_id        = $id;
      }
      else {
        $stack_entry->{id} = $current_id;
      }
      push @h_stack, $stack_entry;



    } # }}}
    elsif ($line =~ /^ *} *$/) { # {{{ The section belonging to the heading ends

      my $stack_entry = pop @h_stack;
      $current_id = $stack_entry->{id};

      if ($pass == 2) {
#       print $out "<p>current_id = $current_id</p>\n";
        $level--;
  
        if ($in_p) {
          print $out "</p>";
          $in_p = 0;
        }

        links_here($current_id, $out);
  
      }

    } # }}}
    else {                       # {{{ The rest

      if ($id) {
        if ($pass == 2) {
          print $out " id=\"$id\"";
        }
        else {
          print "Warning id found in $file without heading, implement me later!\n";
        }
      }

      if ($line =~ /\w/) { # {{{ Text that belongs to a paragraph

         unless ($in_p) {

           if ($pass == 2) {
             print $out "<p>\n";
             $in_p = 1;
           }

         }

         $line =~ s{→ *(\w+)}{

           my $ret = '';

           if ($pass == 1) {
             $ids{$1}{links_here}->{$current_id} =1;

             unless (exists $ids{$1}{file}) {
               $ids{$1}{file} = '?';
             }

           }
           else {

             if ($files{$ids{$1}{file}}{publish_sign} eq '+') {

               if ($ids{$1}{is_anchor}) {
  
                 $ret = "<a href=\"$ids{$1}{file}.html#$1\">";
  
               }
               else {
  
                 $ret = "<a href=\"$ids{$1}{file}.html\">";
               }
  
               $ret .= $ids{$1}{title};
  
               $ret .= '</a>';
             }
             else {
               $ret = "<i>$ids{$1}{title}</i>";
             }
           }
           $ret;

         }ge;

         if ($pass == 2) {

           $line =~ s/^\s*//;
           $line =~ s/\s*$//;
           print $out "$line\n";
        }

      } # }}}
      else {               # {{{ Empty line (or whitespaces only)

        if ($in_p) {
          print $out "</p>\n";
          $in_p = 0;
        }

      } # }}}


    } # }}}


  } # }}}

  if ($pass == 1) {

    die "Level: $level in $file" if $level;

  }


  if ($pass == 2) {
#       print $out "What links here: $file?<br>";
    links_here($file, $out);
    print $out '<div class="end"></div>';
    print $out "</body></html>";

  }

    
} # }}}

sub links_here { # {{{
    my $id  = shift;
    my $out = shift;

    my $first = 1;

    for my $links_here_id (keys %{$ids{$id}{links_here}}) {

      next if $files{  $ids{$links_here_id}{file}  }{publish_sign} eq '-';
      
      if ($first) {
        $first = 0;
        print $out "<p class='links_here'>Inbound links\n";
      }
      print $out "<br><a href=\"$ids{$links_here_id}{file}.html";

      if ($ids{$links_here_id}{is_anchor}) {
        print $out "#$links_here_id";
      }
      
      print $out "\">$ids{$links_here_id}{title}";
      print $out " [$id/$links_here_id]" if $debug; 
      print $out "</a>\n";

    }

    unless ($first) {
      print $out "</p>\n";
    }
} # }}}
