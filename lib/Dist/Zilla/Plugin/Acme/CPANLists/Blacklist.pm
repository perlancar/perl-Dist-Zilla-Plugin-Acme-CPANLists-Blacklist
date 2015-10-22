package Dist::Zilla::Plugin::Acme::CPANLists::Blacklist;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

use Module::Load;

with (
    'Dist::Zilla::Role::InstallTool',
);

has author_list => (is=>'rw');
has module_list => (is=>'rw');

sub mvp_multivalue_args { qw(author_list module_list) }

sub _prereq_check {
    my ($self, $prereqs_hash, $mod, $wanted_phase, $wanted_rel) = @_;

    #use DD; dd $prereqs_hash;

    my $num_any = 0;
    my $num_wanted = 0;
    for my $phase (keys %$prereqs_hash) {
        for my $rel (keys %{ $prereqs_hash->{$phase} }) {
            if (exists $prereqs_hash->{$phase}{$rel}{$mod}) {
                $num_any++;
                $num_wanted++ if
                    (!defined($wanted_phase) || $phase eq $wanted_phase) &&
                    (!defined($wanted_rel)   || $rel   eq $wanted_rel);
            }
        }
    }
    ($num_any, $num_wanted);
}

sub _prereq_only_in {
    my ($self, $prereqs_hash, $mod, $wanted_phase, $wanted_rel) = @_;

    my ($num_any, $num_wanted) = $self->_prereq_check(
        $prereqs_hash, $mod, $wanted_phase, $wanted_rel,
    );
    $num_wanted == 1 && $num_any == 1;
}

sub _prereq_none {
    my ($self, $prereqs_hash, $mod) = @_;

    my ($num_any, $num_wanted) = $self->_prereq_check(
        $prereqs_hash, $mod, 'whatever', 'whatever',
    );
    $num_any == 0;
}

# actually we use InstallTool phase just so we are run after all the
# PrereqSources plugins
sub setup_installer {
    use experimental 'smartmatch';
    no strict 'refs';

    my $self = shift;

    my %blacklisted_authors; # cpanid => {list=>'...', summary=>'...'}
    for my $l (@{ $self->author_list // [] }) {
        my ($ns, $name) = $l =~ /(.+)::(.+)/
            or die "Invalid author_list name '$l', must be 'NAMESPACE::Some name'";
        my $pkg = "Acme::CPANLists::$ns";
        load $pkg;
        my $found = 0;
        for my $ml (@{"$pkg\::Author_Lists"}) {
            next unless $ml->{name} eq $name || $ml->{summary} eq $name;
            $found++;
            for my $ent (@{ $ml->{entries} }) {
                $blacklisted_authors{$ent->{author}} //= {
                    list => $l,
                    summary => $ent->{summary},
                };
            }
            last;
        }
        unless ($found) {
            die "author_list named '$name' not found in $pkg";
        }
    }

    my %blacklisted_modules; # module => {list=>'...', summary=>'...'}
    for my $l (@{ $self->module_list // [] }) {
        my ($ns, $name) = $l =~ /(.+)::(.+)/
            or die "Invalid module_list name '$l', must be 'NAMESPACE::Some name'";
        my $pkg = "Acme::CPANLists::$ns";
        load $pkg;
        my $found = 0;
        for my $ml (@{"$pkg\::Module_Lists"}) {
            next unless
                defined($ml->{name}) && $ml->{name} eq $name ||
                defined($ml->{summary}) && $ml->{summary} eq $name;
            $found++;
            for my $ent (@{ $ml->{entries} }) {
                $blacklisted_modules{$ent->{module}} //= {
                    list => $l,
                    summary => $ent->{summary},
                };
            }
            last;
        }
        unless ($found) {
            die "module_list named '$name' not found in $pkg";
        }
    }

    my @whitelisted_authors;
    my @whitelisted_modules;
    {
        my $whitelist_plugin;
        for my $pl (@{ $self->zilla->plugins }) {
            if ($pl->isa("Dist::Zilla::Plugin::Acme::CPANLists::Whitelist")) {
                $whitelist_plugin = $pl; last;
            }
        }
        last unless $whitelist_plugin;
        @whitelisted_authors = @{ $whitelist_plugin->author // []};
        @whitelisted_modules = @{ $whitelist_plugin->module // []};
    }

    my $prereqs_hash = $self->zilla->prereqs->as_string_hash;

    my @all_prereqs;
    for my $phase (keys %$prereqs_hash) {
        for my $rel (keys %{ $prereqs_hash->{$phase} }) {
            for my $mod (keys %{ $prereqs_hash->{$phase}{$rel} }) {
                push @all_prereqs, $mod
                    unless $mod ~~ @all_prereqs;
            }
        }
    }

    if (keys %blacklisted_authors) {
        $self->log_debug(["Checking against blacklisted authors ..."]);
        require App::lcpan::Call;
        my @res = App::lcpan::Call::call_lcpan_script(argv=>['mods', '--or', '--detail', @all_prereqs]);
        for my $rec (@res) {
            next unless $rec->{name} ~~ @all_prereqs;
            if ($blacklisted_authors{$rec->{author}} &&
                    !($rec->{author} ~~ @whitelisted_authors)) {
                $self->log_fatal(["Module '%s' is released by blacklisted author '%s' (list=%s, summary=%s)",
                                  $rec->{name}, $rec->{author},
                                  $blacklisted_authors{$rec->{author}}{list},
                                  $blacklisted_authors{$rec->{author}}{summary}]);
            }
        }
    }

    if (keys %blacklisted_modules) {
        $self->log_debug(["Checking against blacklisted authors ..."]);
        for my $mod (@all_prereqs) {
            if ($blacklisted_modules{$mod} && !($mod ~~ @whitelisted_modules)) {
                $self->log_fatal(["Module '%s' is blacklisted (list=%s, summary=%s)",
                                  $mod,
                                  $blacklisted_modules{$mod}{list},
                                  $blacklisted_modules{$mod}{summary}]);
            }
        }
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Ensure prereq to spec modules

=for Pod::Coverage .+

=head1 SYNOPSIS

In C<dist.ini>:

 [PERLANCAR::EnsurePrereqToSpec]


=head1 DESCRIPTION

I like to specify prerequisite to spec modules such as L<Rinci>, L<Riap>,
L<Sah>, L<Setup>, etc as DevelopRecommends, to express that a distribution
conforms to such specification(s).

Currently only L<Rinci> is checked.
