package Rex::JobControl::Help;
$Rex::JobControl::Help::VERSION = '0.7.0';
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub index {
  my $self = shift;
  $self->render;
}

1;