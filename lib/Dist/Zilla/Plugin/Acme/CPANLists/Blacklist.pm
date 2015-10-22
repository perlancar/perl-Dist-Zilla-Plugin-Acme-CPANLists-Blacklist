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
        @whitelisted_authors = @{ $whitelist_plugin->author };
        @whitelisted_authors = @{ $whitelist_plugin->module };
    }

    my $prereqs_hash = $self->zilla->prereqs->as_string_hash;

    # Rinci
    if ($self->check_dist_defines_rinci_meta) {
        $self->log_fatal(["Dist defines Rinci metadata, but there is no DevelopRecommends prereq to Rinci"])
            unless $self->_prereq_only_in($prereqs_hash, "Rinci", "develop", "recommends");
    } else {
        $self->log_fatal(["Dist does not define Rinci metadata, but there is a prereq to Rinci"])
            unless $self->_prereq_none($prereqs_hash, "Rinci");
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
