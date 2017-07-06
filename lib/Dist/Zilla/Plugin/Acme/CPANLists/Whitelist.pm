package Dist::Zilla::Plugin::Acme::CPANLists::Whitelist;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

with (
    'Dist::Zilla::Role::AfterBuild',
);

has author => (is=>'rw');
has module => (is=>'rw');

sub mvp_multivalue_args { qw(author module) }

sub after_build {}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Specify whitelist

=for Pod::Coverage .+

=head1 SYNOPSIS

In your F<dist.ini>:

 [Acme::CPANLists::Blacklist]
 module_list=PERLANCAR::Modules I'm avoiding
 module_list=PERLANCAR::Test list

 [Acme::CPANLists::Whitelist]
 module=Log::Any

This means that if your dist specifies a prereq to C<Log::Any>, the Blacklist
plugin will not abort build even though the module is listed in one of the
blacklists.


=head1 SEE ALSO

L<Acme::CPANLists>

C<Acme::CPANLists::*> modules

L<Dist::Zilla::Plugin::Acme::CPANLists::Blacklist>
