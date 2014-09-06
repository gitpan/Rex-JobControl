
=encoding UTF-8

=head1 NAME

Rex::JobControl - Job-Control Webinterface for Rex

=head1 DESCRIPTION

(R)?ex is a configuration- and deployment management framework. You can write tasks in a file named I<Rexfile>.

You can find examples and howtos on L<http://rexify.org/>

This is the official webinterface for Rex.

=head1 GETTING HELP

=over 4

=item * Web Site: L<http://rexify.org/>

=item * IRC: irc.freenode.net #rex

=item * Bug Tracker: L<https://github.com/RexOps/rex-jobcontrol/issues>

=item * Twitter: L<http://twitter.com/RexOps>

=back

=head1 INSTALLATION

To install Rex::JobControl you can use the normal cpan tools. We recommend using cpanm from http://cpanmin.us/.

 cpanm Rex::JobControl

=head1 CONFIGURATION

The configuration file is looked up in 3 locations.

=over 4

=item /etc/rex/jobcontrol.conf

=item /usr/local/etc/rex/jobcontrol.conf

=item ./jobcontrol.conf

=back

You find an example configuration file on https://github.com/RexOps/rex-jobcontrol.

=head1 RUNNING

Rex::JobControl consists of 2 services. The Webinterface and the Worker.

To start the worker you have to run the following command. You can start as many worker as you need/want.

 rex_job_control minion worker

To start the Webinterface you have to run this command. This will start a webserver at port 8080. 

 hypnotoad /usr/bin/rex_job_control 


=head1 MANAGING USERS

Currently there is no webinterface to manage the users, but you can use a cli command to do this.

Add user:

 rex_job_control jobcontrol adduser -u $user -p $password

Remove user:

 rex_job_control jobcontrol deluser -u $user

List user:

 rex_job_control jobcontrol listuser

=cut

package Rex::JobControl;
$Rex::JobControl::VERSION = '0.0.1';
use File::Basename 'dirname';
use File::Spec::Functions 'catdir';
use Mojo::Base 'Mojolicious';
use Data::Dumper;
use Rex::JobControl::Mojolicious::Command::jobcontrol;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  # $self->plugin('PODRenderer');

  #######################################################################
  # Load configuration
  #######################################################################
  my @cfg = (
    "/etc/rex/jobcontrol.conf", "/usr/local/etc/rex/jobcontrol.conf",
    "jobcontrol.conf"
  );
  my $cfg;
  for my $file (@cfg) {
    if ( -f $file ) {
      $cfg = $file;
      last;
    }
  }

  #######################################################################
  # Load plugins
  #######################################################################
  $self->plugin( "Config", file => $cfg );
  $self->plugin("Rex::JobControl::Mojolicious::Plugin::Project");

  $self->plugin( Minion => { File => $self->app->config->{minion_db_file} } );
  $self->plugin("Rex::JobControl::Mojolicious::Plugin::MinionJobs");
  $self->plugin("Rex::JobControl::Mojolicious::Plugin::User");
  $self->plugin("Rex::JobControl::Mojolicious::Plugin::Audit");
  $self->plugin(
    "Authentication" => {
      autoload_user => 1,
      session_key   => $self->config->{session}->{key},
      load_user     => sub {
        my ( $app, $uid ) = @_;

        my $user = $app->get_user($uid);
        return $user;    # user objekt
      },
      validate_user => sub {
        my ( $app, $username, $password ) = @_;
        return $app->check_password( $username, $password );
      },
    }
  );

  #######################################################################
  # Define routes
  #######################################################################
  my $base_routes = $self->routes;

  # Normal route to controller

  my $r = $base_routes->bridge('/')->to('dashboard#prepare_stash');

  $r->get('/login')->to('dashboard#login');
  $r->post('/login')->to('dashboard#login_post');

  my $r_formular_execute =
    $r->bridge('/project/:project_dir/formular/:formular_dir/execute')
    ->to("formular#check_public");

  my $r_auth = $r->bridge('/')->to("dashboard#check_login");

  $r_auth->get('/logout')->to('dashboard#ctrl_logout');
  $r_auth->get('/')->to('dashboard#index');

  $r_auth->get('/project/new')->to('project#project_new');
  $r_auth->post('/project/new')->to('project#project_new_create');

  my $project_r =
    $r_auth->bridge('/project/:project_dir')->to('project#prepare_stash');
  my $rex_r = $r_auth->bridge('/project/:project_dir/rexfile/:rexfile_dir')
    ->to('rexfile#prepare_stash');
  my $job_r = $r_auth->bridge('/project/:project_dir/job/:job_dir')
    ->to('job#prepare_stash');
  my $form_r = $r_auth->bridge('/project/:project_dir/formular/:formular_dir')
    ->to('formular#prepare_stash');

  $project_r->get('/nodes')->to('nodes#index');
  $project_r->get('/audit')->to('audit#index');

  $project_r->get('/')->to('project#view');
  $project_r->get('/job/new')->to('job#job_new');
  $project_r->post('/job/new')->to('job#job_new_create');
  $project_r->get('/delete')->to('project#remove');
  $project_r->get('/rexfile/new')->to('rexfile#rexfile_new');
  $project_r->post('/rexfile/new')->to('rexfile#rexfile_new_create');
  $project_r->get('/formular/new')->to('formular#formular_new');
  $project_r->post('/formular/new')->to('formular#formular_new_create');

  $form_r->get('/')->to('formular#view');
  $form_r->get('/edit')->to('formular#edit');
  $form_r->post('/edit')->to('formular#edit_save');
  $r_formular_execute->get('/')->to('formular#view_formular');
  $r_formular_execute->post('/')->to('formular#view_formular');
  $form_r->post('/execute/delete_data_item')->to('formular#delete_data_item');
  $form_r->get('/delete')->to('formular#remove');

  $rex_r->get('/')->to('rexfile#view');
  $rex_r->get('/reload')->to('rexfile#reload');
  $rex_r->get('/delete')->to('rexfile#remove');

  $job_r->get('/')->to('job#view');
  $job_r->get('/edit')->to('job#edit');
  $job_r->post('/edit')->to('job#edit_save');
  $job_r->get('/delete')->to('job#job_delete');
  $job_r->get('/execute')->to('job#job_execute');
  $job_r->post('/execute')->to('job#job_execute_dispatch');

  #######################################################################
  # for the package
  #######################################################################

  # Switch to installable home directory
  $self->home->parse( catdir( dirname(__FILE__), 'JobControl' ) );

  # Switch to installable "public" directory
  $self->static->paths->[0] = $self->home->rel_dir('public');

  # Switch to installable "templates" directory
  $self->renderer->paths->[0] = $self->home->rel_dir('templates');

}

1;
