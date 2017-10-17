package DateTime::Duration::Lite;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use overload (
    fallback => 1,
    '+'      => '_add_overload',
    '-'      => '_subtract_overload',
    '*'      => '_multiply_overload',
    '<=>'    => '_compare_overload',
    'cmp'    => '_compare_overload',
);

use constant MAX_NANOSECONDS => 1_000_000_000;    # 1E9 = almost 32 bits

use Class::Accessor::PackedString::Set +{
    constructor => '_new',
    accessors => [
        _years        => "f",
        _months       => "f",
        _weeks        => "f",
        _days         => "f",
        _hours        => "f",
        _minutes      => "f",
        _seconds      => "f",
        _nanoseconds  => "f",
        _end_of_month => "c", # w(rap), l(imit), p(reserve)
    ],
};

my @all_units = qw( months days minutes seconds nanoseconds );

sub new {
    my $class = shift;
    my $self = $class->_new;
    my %p = @_;

    no warnings 'uninitialized';
    $self->_months( $p{years} * 12 + $p{months} );
    $self->_days( $p{weeks} * 7  + $p{days} );
    $self->_minutes( $p{hours} * 60 + $p{minutes} );
    $self->_seconds( $p{seconds} );
    if ( $p{nanoseconds} ) {
        $self->_nanoseconds( $p{nanoseconds} );
        $self->_normalize_nanoseconds;
    }

    $self->_end_of_month(
        defined $p{end_of_month} ? $p{end_of_month}
            : $self->_months < 0      ? 'preserve'
            :                            'wrap'
    );

    return $self;
}

# make the signs of seconds, nanos the same; 0 < abs(nanos) < MAX_NANOS
# NB this requires nanoseconds != 0 (callers check this already)
sub _normalize_nanoseconds {
    my $self = shift;

    return
        if ( $self->{nanoseconds} == DateTime::INFINITY()
        || $self->{nanoseconds} == DateTime::NEG_INFINITY()
        || $self->{nanoseconds} eq DateTime::NAN() );

    my $seconds = $self->{seconds} + $self->{nanoseconds} / MAX_NANOSECONDS;
    $self->{seconds}     = int($seconds);
    $self->{nanoseconds} = $self->{nanoseconds} % MAX_NANOSECONDS;
    $self->{nanoseconds} -= MAX_NANOSECONDS if $seconds < 0;
}

sub clone { bless { %{ $_[0] } }, ref $_[0] }

sub years       { abs( $_[0]->in_units('years') ) }
sub months      { abs( $_[0]->in_units( 'months', 'years' ) ) }
sub weeks       { abs( $_[0]->in_units('weeks') ) }
sub days        { abs( $_[0]->in_units( 'days', 'weeks' ) ) }
sub hours       { abs( $_[0]->in_units('hours') ) }
sub minutes     { abs( $_[0]->in_units( 'minutes', 'hours' ) ) }
sub seconds     { abs( $_[0]->in_units('seconds') ) }
sub nanoseconds { abs( $_[0]->in_units( 'nanoseconds', 'seconds' ) ) }

sub is_positive { $_[0]->_has_positive  && !$_[0]->_has_negative }
sub is_negative { !$_[0]->_has_positive && $_[0]->_has_negative }

sub _has_positive {
    ( grep { $_ > 0 } @{ $_[0] }{@all_units} ) ? 1 : 0;
}

sub _has_negative {
    ( grep { $_ < 0 } @{ $_[0] }{@all_units} ) ? 1 : 0;
}

sub is_zero {
    return 0 if grep { $_ != 0 } @{ $_[0] }{@all_units};
    return 1;
}

sub delta_months      { $_[0]->{months} }
sub delta_days        { $_[0]->{days} }
sub delta_minutes     { $_[0]->{minutes} }
sub delta_seconds     { $_[0]->{seconds} }
sub delta_nanoseconds { $_[0]->{nanoseconds} }

sub deltas {
    map { $_ => $_[0]->{$_} } @all_units;
}

sub in_units {
    my $self  = shift;
    my @units = @_;

    my %units = map { $_ => 1 } @units;

    my %ret;

    my ( $months, $days, $minutes, $seconds )
        = @{$self}{qw( months days minutes seconds )};

    if ( $units{years} ) {
        $ret{years} = int( $months / 12 );
        $months -= $ret{years} * 12;
    }

    if ( $units{months} ) {
        $ret{months} = $months;
    }

    if ( $units{weeks} ) {
        $ret{weeks} = int( $days / 7 );
        $days -= $ret{weeks} * 7;
    }

    if ( $units{days} ) {
        $ret{days} = $days;
    }

    if ( $units{hours} ) {
        $ret{hours} = int( $minutes / 60 );
        $minutes -= $ret{hours} * 60;
    }

    if ( $units{minutes} ) {
        $ret{minutes} = $minutes;
    }

    if ( $units{seconds} ) {
        $ret{seconds} = $seconds;
        $seconds = 0;
    }

    if ( $units{nanoseconds} ) {
        $ret{nanoseconds} = $seconds * MAX_NANOSECONDS + $self->{nanoseconds};
    }

    wantarray ? @ret{@units} : $ret{ $units[0] };
}

sub is_wrap_mode     { $_[0]->{end_of_month} eq 'wrap'     ? 1 : 0 }
sub is_limit_mode    { $_[0]->{end_of_month} eq 'limit'    ? 1 : 0 }
sub is_preserve_mode { $_[0]->{end_of_month} eq 'preserve' ? 1 : 0 }

sub end_of_month_mode { $_[0]->{end_of_month} }

sub calendar_duration {
    my $self = shift;

    return ( ref $self )
        ->new( map { $_ => $self->{$_} } qw( months days end_of_month ) );
}

sub clock_duration {
    my $self = shift;

    return ( ref $self )
        ->new( map { $_ => $self->{$_} }
            qw( minutes seconds nanoseconds end_of_month ) );
}

sub inverse {
    my $self = shift;
    my %p    = @_;

    my %new;
    foreach my $u (@all_units) {
        $new{$u} = $self->{$u};

        # avoid -0 bug
        $new{$u} *= -1 if $new{$u};
    }

    $new{end_of_month} = $p{end_of_month}
        if exists $p{end_of_month};

    return ( ref $self )->new(%new);
}

sub add_duration {
    my ( $self, $dur ) = @_;

    foreach my $u (@all_units) {
        $self->{$u} += $dur->{$u};
    }

    $self->_normalize_nanoseconds if $self->{nanoseconds};

    return $self;
}

sub add {
    my $self = shift;

    return $self->add_duration( ( ref $self )->new(@_) );
}

sub subtract_duration { return $_[0]->add_duration( $_[1]->inverse ) }

sub subtract {
    my $self = shift;

    return $self->subtract_duration( ( ref $self )->new(@_) );
}

sub multiply {
    my $self       = shift;
    my $multiplier = shift;

    foreach my $u (@all_units) {
        $self->{$u} *= $multiplier;
    }

    $self->_normalize_nanoseconds if $self->{nanoseconds};

    return $self;
}

sub compare {
    my ( undef, $dur1, $dur2, $dt ) = @_;

    $dt ||= DateTime->now;

    return DateTime->compare(
        $dt->clone->add_duration($dur1),
        $dt->clone->add_duration($dur2)
    );
}

sub _add_overload {
    my ( $d1, $d2, $rev ) = @_;

    ( $d1, $d2 ) = ( $d2, $d1 ) if $rev;

    if ( DateTime::Helpers::isa( $d2, 'DateTime' ) ) {
        $d2->add_duration($d1);
        return;
    }

    # will also work if $d1 is a DateTime.pm object
    return $d1->clone->add_duration($d2);
}

sub _subtract_overload {
    my ( $d1, $d2, $rev ) = @_;

    ( $d1, $d2 ) = ( $d2, $d1 ) if $rev;

    Carp::croak(
        "Cannot subtract a DateTime object from a DateTime::Duration object")
        if DateTime::Helpers::isa( $d2, 'DateTime' );

    return $d1->clone->subtract_duration($d2);
}

sub _multiply_overload {
    my $self = shift;

    my $new = $self->clone;

    return $new->multiply(@_);
}

sub _compare_overload {
    Carp::croak( 'DateTime::Duration does not overload comparison.'
            . '  See the documentation on the compare() method for details.'
    );
}

1;
# ABSTRACT: Duration objects for date math (lite version)

=head1 SYNOPSIS


=head1 DESCRIPTION

B<EXPERIMENTAL, EARLY RELEASE.>

This class is an alternative to L<DateTime::Duration>. The goal is to provide a
reasonably compatible interface with less {startup overhead, code, memory
usage}.


=head1 SEE ALSO

L<DateTime::Duration>
