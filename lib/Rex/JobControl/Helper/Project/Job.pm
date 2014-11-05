#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::JobControl::Helper::Project::Job;
$Rex::JobControl::Helper::Project::Job::VERSION = '0.6.0';
use strict;
use warnings;

use File::Spec;
use File::Path;
use YAML;
use Rex::JobControl::Helper::Chdir;
use Data::Dumper;

sub new {
  my $that  = shift;
  my $proto = ref($that) || $that;
  my $self  = {@_};

  bless( $self, $proto );

  $self->load;

  return $self;
}

sub name             { (shift)->{job_configuration}->{name} }
sub description      { (shift)->{job_configuration}->{description} }
sub environment      { (shift)->{job_configuration}->{environment} }
sub project          { (shift)->{project} }
sub directory        { (shift)->{directory} }
sub steps            { (shift)->{job_configuration}->{steps} }
sub fail_strategy    { (shift)->{job_configuration}->{fail_strategy} }
sub execute_strategy { (shift)->{job_configuration}->{execute_strategy} }

sub load {
  my ($self) = @_;

  if ( -f $self->_config_file() ) {
    $self->{job_configuration} = YAML::LoadFile( $self->_config_file );
  }
}

sub _config_file {
  my ($self) = @_;
  return File::Spec->catfile( $self->project->project_path(),
    "jobs", $self->{directory}, "job.conf.yml" );
}

sub create {
  my ( $self, %data ) = @_;

  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );

  $self->project->app->log->debug(
    "Creating new job $self->{directory} in $job_path.");

  File::Path::make_path($job_path);

  delete $data{directory};

  my $job_configuration = {%data};

  YAML::DumpFile( "$job_path/job.conf.yml", $job_configuration );
}

sub update {
  my ( $self, %data ) = @_;
  $self->{job_configuration} = \%data;

  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );

  YAML::DumpFile( "$job_path/job.conf.yml", \%data );
}

sub remove {
  my ($self) = @_;
  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );

  File::Path::remove_tree($job_path);
}

sub execute {
  my ( $self, $user, $cmdb, @server ) = @_;
  $self->project->app->log->debug( "Executing job: " . $self->name );
  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );

  my $pid          = time;
  my $execute_path = "$job_path/execute/$pid";
  my $cmdb_path    = "$job_path/execute/$pid/cmdb";

  my @status;

  File::Path::make_path($execute_path);
  File::Path::make_path($cmdb_path);

  $self->project->app->log->debug(
    "Executing-Strategy: " . $self->execute_strategy );
  $self->project->app->log->debug( "Fail-Strategy: " . $self->fail_strategy );

  if ($cmdb) {
    $self->project->app->log->debug("Creating cmdb file");
    YAML::DumpFile( "$cmdb_path/jobcontrol.yml", $cmdb );
  }

  if ( $self->execute_strategy eq "step" ) {

    # execute strategy = step
    # execute a step on all hosts, than continue with next step

  STEP: for my $s ( @{ $self->steps } ) {

    SERVER: for my $srv (@server) {

        my ( $rexfile_name, $task ) = split( /\//, $s );
        my $rexfile = $self->project->get_rexfile($rexfile_name);

        my $ret = $rexfile->execute(
          task   => $task,
          server => [$srv],
          job    => $self,
          ( $cmdb ? ( cmdb => $cmdb_path ) : () )
        );
        push @status, $ret->[0];

        if ( exists $ret->[0]->{terminate_message} ) {
          $self->project->app->log->debug("Terminating due to fail strategy.");
          last STEP;
        }

      }
    }

  }
  else {

    # execute strategt = node
    # execute all steps on a server, than continue

  SERVER: for my $srv (@server) {

    STEP: for my $s ( @{ $self->steps } ) {

        if(-f $self->project->project_path . "/next_server.txt") {
          $srv = eval { local(@ARGV, $/) = ($self->project->project_path . "/next_server.txt"); <>; };
          chomp $srv;
          unlink $self->project->project_path . "/next_server.txt";
        }

        my ( $rexfile_name, $task ) = split( /\//, $s );
        my $rexfile = $self->project->get_rexfile($rexfile_name);

        my $ret = $rexfile->execute(
          task   => $task,
          server => [$srv],
          job    => $self,
          ( $cmdb ? ( cmdb => $cmdb_path ) : () )
        );
        push @status, $ret->[0];

        if ( exists $ret->[0]->{terminate_message} ) {
          $self->project->app->log->debug("Terminating due to fail strategy.");
          last SERVER;
        }
      }

    }

  }

  YAML::DumpFile(
    "$execute_path/run.status.yml",
    {
      start_time => $pid,
      end_time   => time,
      user       => $user,
      status     => \@status,
    }
  );
}

sub last_status {
  my ($self) = @_;

  my $last_execution = $self->last_execution;

  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );
  my $execute_path = "$job_path/execute/$last_execution";

  if ( !-f "$execute_path/run.status.yml" ) {
    return "not executed yet";
  }

  my $ref = YAML::LoadFile("$execute_path/run.status.yml");

  my ($failed) = grep { $_->{status} eq "failed" } @{ $ref->{status} };

  if ($failed) {
    return "failed";
  }

  return "success";
}

sub last_execution {
  my ($self) = @_;
  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );
  my $execute_path = "$job_path/execute";

  if ( -d $execute_path ) {
    my @entries;
    opendir( my $dh, $execute_path ) or die($!);
    while ( my $entry = readdir($dh) ) {
      next if ( !-f "$execute_path/$entry/run.status.yml" );
      push @entries, $entry;
    }
    closedir($dh);

    my ($last) = sort { $b <=> $a } @entries;

    return $last;
  }
  else {
    return 0;
  }

}

sub get_logs {
  my ($self) = @_;

  my $job_path = File::Spec->catdir( $self->project->project_path,
    "jobs", $self->{directory} );

  my $execute_path = "$job_path/execute";

  if ( -d $execute_path ) {

    my @entries;
    opendir( my $dh, $execute_path ) or die($!);
    while ( my $entry = readdir($dh) ) {
      next if ( !-f "$execute_path/$entry/run.status.yml" );
      push @entries, YAML::LoadFile("$execute_path/$entry/run.status.yml");
    }
    closedir($dh);

    @entries = sort { $b->{start_time} <=> $a->{start_time} } @entries;

    return \@entries;

  }

  else {

    return [];

  }
}

1;
