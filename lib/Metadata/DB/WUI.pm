package Metadata::DB::WUI;
use strict;
use base 'CGI::Application';

use CGI::Application::Plugin::MetadataDB;

use Carp;
use CGI::Application::Plugin::AutoRunmode;
use CGI::Application::Plugin::Feedback;
use CGI::Application::Plugin::Session;
use HTML::Template::Default 'get_tmpl';

use CGI::Application::Plugin::Forward;
use CGI::Application::Plugin::Menu;
use LEOCHARRE::DEBUG;

use LEOCHARRE::DBI;

#use Cwd;
our $VERSION = sprintf "%d.%02d", q$Revision: 1.16 $ =~ /(\d+)/g;



sub conf {
   my $self = shift;

   unless($self->{__conf}){      
      if( my $abs = $self->_abs_conf ){
         debug("attempting $abs conf load..");
         require YAML;
         my $conf =  YAML::LoadFile($abs);
         #$conf->{mdw_search_tmpl_name} ||= 'mdw.search.html';
         #$conf->{mdw_search_results_tmpl_name} ||= 'mdw.search_results.html';
         
         $self->mdw_search_tmpl_name( $conf->{mdw_search_tmpl_name} ); # if undef, changes nothing
         $self->mdw_search_results_tmpl_name( $conf->{mdw_search_results_tmpl_name} ); # same
         $ENV{HTML_TEMPLATE_ROOT} ||= $conf->{HTML_TEMPLATE_ROOT};

         my $DBH;
         if ($conf->{DBABSPATH}){
            $DBH = DBI::connect_sqlite($conf->{DBABSPATH});
         }
         elsif( $conf->{DBNAME} ){
            $DBH = DBI::connect_mysql(
               $conf->{DBNAME}, $conf->{DBUSER}, $conf->{DBPASSWORD}, $conf->{DBHOST}
               );
         }
         if ($DBH){
            $self->param( DBH => $DBH );
         }

         $self->{__conf} = $conf;
      }
   }
   return $self->{__conf};
}
sub _abs_conf {
   my $self = shift;

   # detect the change
   if ( my $val = $self->query->param('conf') ){
      $self->feedback("changed to $val");
      $self->session->param('conf' => $val );
   }
   my $abs_conf;
   $abs_conf =   $self->query->param('conf');
   $abs_conf ||= $self->session->param('conf');
   $abs_conf ||= $self->param('conf');
   $abs_conf ||='mdw.conf';

   unless( -f "./$abs_conf" ){
      $self->feedback("$abs_conf not on disk");            
      return;
   }
   return $abs_conf;
}
sub _mdw_confs { # returns list
   my $self = shift;

   unless( $self->{_mdw_confs} ){

      if( opendir(DIR,'./') ){
         my @p = grep { /md.+\.conf$/ } readdir DIR;
         $self->{_mdw_confs} = \@p;
      }
      else {
         $self->{_mdw_confs} = [];
      }
   }
   return $self->{_mdw_confs};
}
sub _mdw_confs_count {
   my $self = shift;
   return ( scalar @{$self->_mdw_confs} );
}
sub mdw_select : Runmode {
   my $self = shift;

   my $code = q{
   <h5>Select..</h5>
   <ul>
   <TMPL_LOOP MDW_CONFS_LOOP>
   <li><a href="?rm=mdw_search&conf=<TMPL_VAR FILE>"><TMPL_VAR FILE></a></li>
   </TMPL_LOOP>
   </ul>
   };

   my $tmpl = get_tmpl(\$code);
   my $outer = $self->feed_tmpl_mdw;
   
   my @seloop;
   for my $conf ( @{$self->_mdw_confs} ){
      push @seloop, { FILE => $conf };   
   }
   $tmpl->param( MDW_CONFS_LOOP => \@seloop );
   $outer->param( BODY => ($tmpl->output) );
   return $outer->output;
}
sub setup {
   my $self = shift;
   $self->start_mode('mdw_search');
   $self->mode_param('rm');
   $self->conf;

}



# runmode
# the search form is generated by Metadata::DB::WUI bin/mdri
# for options see on the command line: # mdri -h
sub mdw_search : Runmode {
   my $self = shift;

   my $tmpl = $self->mdw_search_tmpl;

   my $outer = $self->feed_tmpl_mdw;
   $outer->param( BODY => ($tmpl->output) );
   return $outer->output;
  
}

sub mdw_help : Runmode {
   my $self = shift;
   my $default = q{
   <pre>
For help, please see admin.
This document will be further updated.
   </pre>
   };
   my $tmpl = get_tmpl('mdw_help.html',\$default);
   my $outer = $self->feed_tmpl_mdw;
   $outer->param( BODY => $tmpl->output);

   return $outer->output;
}

# runmode
sub mdw_search_results : Runmode {
   my $self = shift;

   $self->mdw_process_search
      or return $self->forward('mdw_search');

   my $tmpl = $self->mdw_search_results_tmpl;
   
   my $search_results_loop = $self->mdw_results_loop_detailed;  
  
   $tmpl->param( 
      SEARCH_RESULTS_LOOP     => $search_results_loop,
   );   
   
   
   my $outer = $self->feed_tmpl_mdw;
   $outer->param( BODY => $tmpl->output );
   my $output =  $outer->output;
   return $output;
}


sub feed_tmpl_mdw {
   my $self  = shift;

   my $tmain = $self->tmpl_outer;

   $tmain->param(
      FEEDBACK => $self->get_feedback_html,
      MENU => ($self->menu->output),
   );
 
   return $tmain;
}


sub tmpl_outer {
   my $self = shift;

   unless ( $self->{tmpl_outer} ){
      

      my $default_code = q{
   <html>

   <title><TMPL_VAR NAME="TITLE" DEFAULT="Metadata Search"></title>
   <body>
   <h5><TMPL_VAR NAME="TITLE" DEFAULT="Metadata Search"></h5>

   <TMPL_VAR MENU>

   <TMPL_VAR FEEDBACK>

   <hr>
   <div><TMPL_VAR BODY></div>
   <hr>
   <p><small><TMPL_VAR VERSION></small></p>
   </body>
   </html>
   };

      $self->{tmpl_outer} = get_tmpl(\$default_code, 'mdw_main.html');
      $self->feedback("loaded mdw_main.html") if DEBUG;
      
      # init menu

      $self->menu->add('mdw_search', 'new search');
      $self->menu->add('mdw_select', 'select conf') if ( $self->_mdw_confs_count > 1 );
   }

   return $self->{tmpl_outer};

}




1;


__END__

=pod

=head1 NAME

Metadata::DB::WUI - minimal search interface example

=head1 DESCRIPTION

Example using CGI::Application::Plugin::MetadataDB





=head1    
