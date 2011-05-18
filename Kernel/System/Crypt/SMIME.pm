# --
# Kernel/System/Crypt/SMIME.pm - the main crypt module
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: SMIME.pm,v 1.52 2011-05-18 18:21:43 dz Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Crypt::SMIME;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.52 $) [1];

=head1 NAME

Kernel::System::Crypt::SMIME - smime crypt backend lib

=head1 SYNOPSIS

This is a sub module of Kernel::System::Crypt and contains all smime functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item Check()

check if environment is working

    my $Message = $CryptObject->Check();

=cut

sub Check {
    my ( $Self, %Param ) = @_;

    if ( !-e $Self->{Bin} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No such $Self->{Bin}!",
        );
        return "No such $Self->{Bin}!";
    }
    elsif ( !-x $Self->{Bin} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "$Self->{Bin} not executable!",
        );
        return "$Self->{Bin} not executable!";
    }
    elsif ( !-e $Self->{CertPath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No such $Self->{CertPath}!",
        );
        return "No such $Self->{CertPath}!";
    }
    elsif ( !-d $Self->{CertPath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No such $Self->{CertPath} directory!",
        );
        return "No such $Self->{CertPath} directory!";
    }
    elsif ( !-w $Self->{CertPath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "$Self->{CertPath} not writable!",
        );
        return "$Self->{CertPath} not writable!";
    }
    elsif ( !-e $Self->{PrivatePath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No such $Self->{PrivatePath}!",
        );
        return "No such $Self->{PrivatePath}!";
    }
    elsif ( !-d $Self->{PrivatePath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "No such $Self->{PrivatePath} directory!",
        );
        return "No such $Self->{PrivatePath} directory!";
    }
    elsif ( !-w $Self->{PrivatePath} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "$Self->{PrivatePath} not writable!",
        );
        return "$Self->{PrivatePath} not writable!";
    }
    return;
}

=item Crypt()

crypt a message

    my $Message = $CryptObject->Crypt(
        Message => $Message,
        Hash    => $CertificateHash,
    );

=cut

sub Crypt {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Message Hash)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }

    my $Certificate = $Self->CertificateGet(%Param);
    my ( $FHCertificate, $CertFile ) = $Self->{FileTempObject}->TempFile();
    print $FHCertificate $Certificate;
    close $FHCertificate;
    my ( $FH, $PlainFile ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Message};
    close $FH;
    my ( $FHCrypted, $CryptedFile ) = $Self->{FileTempObject}->TempFile();
    close $FHCrypted;

    my $Options
        = "smime -encrypt -binary -des3 -in $PlainFile -out $CryptedFile $CertFile";
    my $LogMessage = $Self->_CleanOutput(qx{$Self->{Cmd} $Options 2>&1});
    if ($LogMessage) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Can't crypt: $LogMessage!" );
        return;
    }

    my $CryptedRef = $Self->{MainObject}->FileRead( Location => $CryptedFile );
    return if !$CryptedRef;
    return $$CryptedRef;
}

=item Decrypt()

decrypt a message and returns a hash (Successful, Message, Data)

    my %Message = $CryptObject->Decrypt(
        Message => $CryptedMessage,
        Hash    => $PrivateKeyHash,
    );

=cut

sub Decrypt {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Message Hash)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }
    my ( $Private, $Secret ) = $Self->PrivateGet(%Param);
    my $Certificate = $Self->CertificateGet(%Param);

    my ( $FHPrivate, $PrivateKeyFile ) = $Self->{FileTempObject}->TempFile();
    print $FHPrivate $Private;
    close $FHPrivate;
    my ( $FHCertificate, $CertFile ) = $Self->{FileTempObject}->TempFile();
    print $FHCertificate $Certificate;
    close $FHCertificate;
    my ( $FH, $CryptedFile ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Message};
    close $FH;
    my ( $FHDecrypted, $PlainFile ) = $Self->{FileTempObject}->TempFile();
    close $FHDecrypted;
    my ( $FHSecret, $SecretFile ) = $Self->{FileTempObject}->TempFile();
    print $FHSecret $Secret;
    close $FHSecret;

    my $Options
        = "smime -decrypt -in $CryptedFile -out $PlainFile -recip $CertFile -inkey $PrivateKeyFile"
        . " -passin file:$SecretFile";
    my $LogMessage = qx{$Self->{Cmd} $Options 2>&1};
    unlink $SecretFile;

    if (
        $Param{SearchingNeededKey}
        && $LogMessage =~ m{PKCS7_dataDecode:no recipient matches certificate}
        && $LogMessage =~ m{PKCS7_decrypt:decrypt error}
        )
    {
        return (
            Successful => 0,
            Message    => 'Impossible to decrypt with installed private keys!',
        );
    }

    if ($LogMessage) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Can't decrypt: $LogMessage!" );
        return (
            Successful => 0,
            Message    => $LogMessage,
        );
    }

    my $DecryptedRef = $Self->{MainObject}->FileRead( Location => $PlainFile );
    if ( !$DecryptedRef ) {
        return (
            Successful => 0,
            Message    => "OpenSSL: Can't read $PlainFile!",
            Data       => undef,
        );

    }
    return (
        Successful => 1,
        Message    => "OpenSSL: OK",
        Data       => $$DecryptedRef,
    );
}

=item Sign()

sign a message

    my $Sign = $CryptObject->Sign(
        Message => $Message,
        Hash    => $PrivateKeyHash,
        CACert  => \@Hashes, # optional - Hashes of certificates to embed in the signature
    );

=cut

sub Sign {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Message Hash)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }
    my ( $Private, $Secret ) = $Self->PrivateGet( Hash => $Param{Hash} );
    my $Certificate = $Self->CertificateGet( Hash => $Param{Hash} );
    my %Attributes = $Self->CertificateAttributes( Certificate => $Certificate );

    # get CA certs and join all in one file
    my @CACerts;
    @CACerts = @{ $Param{CACert} } if ( $Param{CACert} );

    # get the related certificates
    my @RelatedCertificates
        = $Self->SignerCertRelationGet( CertFingerprint => $Attributes{Fingerprint} );
    for my $Cert (@RelatedCertificates) {
        push @CACerts, $Cert->{CAHash};
    }

    my ( $FHCACertFile, $CAFileName ) = $Self->{FileTempObject}->TempFile();
    my @CACert;
    my $CertFileCommand = '';
    if (@CACerts) {

        # get certificate for every array row
        for my $CertHash (@CACerts) {
            print $FHCACertFile $Self->CertificateGet( Hash => $CertHash ) . "\n";
        }
        $CertFileCommand = " -certfile $CAFileName ";
    }
    close $FHCACertFile;

    my ( $FH, $PlainFile ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Message};
    close $FH;
    my ( $FHPrivate, $PrivateKeyFile ) = $Self->{FileTempObject}->TempFile();
    print $FHPrivate $Private;
    close $FHPrivate;
    my ( $FHCertificate, $CertFile ) = $Self->{FileTempObject}->TempFile();
    print $FHCertificate $Certificate;
    close $FHCertificate;
    my ( $FHSign, $SignFile ) = $Self->{FileTempObject}->TempFile();
    close $FHSign;
    my ( $FHSecret, $SecretFile ) = $Self->{FileTempObject}->TempFile();
    print $FHSecret $Secret;
    close $FHSecret;

    my $Options
        = "smime -sign -in $PlainFile -out $SignFile -signer $CertFile -inkey $PrivateKeyFile"
        . " -text -binary -passin file:$SecretFile";

    # add the certfile parameter
    $Options .= $CertFileCommand;

    my $LogMessage = $Self->_CleanOutput(qx{$Self->{Cmd} $Options 2>&1});
    unlink $SecretFile;
    if ($LogMessage) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Can't sign: $LogMessage! (Command: $Options)"
        );
        return;
    }

    my $SignedRef = $Self->{MainObject}->FileRead( Location => $SignFile );
    return if !$SignedRef;
    return $$SignedRef;

}

=item Verify()

verify a message with signature and returns a hash (Successful, Message, SignerCertificate)

    my %Data = $CryptObject->Verify(
        Message     => $Message,
        Certificate => $PathtoCert, # optional send path to the CA cert, when unsing self signed certificates
    );

=cut

sub Verify {
    my ( $Self, %Param ) = @_;

    my %Return;
    my $Message     = '';
    my $MessageLong = '';
    my $UsedKey     = '';

    # check needed stuff
    if ( !$Param{Message} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Need Message!" );
        return;
    }

    my ( $FH, $SignedFile ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Message};
    close $FH;
    my ( $FHOutput, $VerifiedFile ) = $Self->{FileTempObject}->TempFile();
    close $FHOutput;
    my ( $FHSigner, $SignerFile ) = $Self->{FileTempObject}->TempFile();
    close $FHSigner;

    # path to the cert, when self signed certs
    # specially for openssl 1.0
    my $CertificateOption = '';
    if ( $Param{Certificate} ) {
        $CertificateOption = "-CAfile $Param{Certificate}";
    }

    my $Options
        = "smime -verify -in $SignedFile -out $VerifiedFile -signer $SignerFile "
        . "-CApath $Self->{CertPath} $CertificateOption $SignedFile";

    my @LogLines = qx{$Self->{Cmd} $Options 2>&1};

    for my $LogLine (@LogLines) {
        $MessageLong .= $LogLine;
        if ( $LogLine =~ /^\d.*:(.+?):.+?:.+?:$/ || $LogLine =~ /^\d.*:(.+?)$/ ) {
            $Message .= ";$1";
        }
        else {
            $Message .= $LogLine;
        }
    }

    # TODO: maybe use _FetchAttributesFromCert() to determine the cert-hash and return that instead?
    # determine hash of signer certificate
    my $SignerCertRef    = $Self->{MainObject}->FileRead( Location => $SignerFile );
    my $SignedContentRef = $Self->{MainObject}->FileRead( Location => $VerifiedFile );

    # return message
    if ( $Message =~ /Verification successful/i ) {
        %Return = (
            SignatureFound    => 1,
            Successful        => 1,
            Message           => 'OpenSSL: ' . $Message,
            MessageLong       => 'OpenSSL: ' . $MessageLong,
            SignerCertificate => $$SignerCertRef,
            Content           => $$SignedContentRef,
        );
    }
    elsif ( $Message =~ /self signed certificate/i ) {
        %Return = (
            SignatureFound => 1,
            Successful     => 0,
            Message =>
                'OpenSSL: self signed certificate, to use it send the \'Certificate\' parameter : '
                . $Message,
            MessageLong =>
                'OpenSSL: self signed certificate, to use it send the \'Certificate\' parameter : '
                . $MessageLong,
            SignerCertificate => $$SignerCertRef,
            Content           => $$SignedContentRef,
        );
    }
    else {
        %Return = (
            SignatureFound => 0,
            Successful     => 0,
            Message        => 'OpenSSL: ' . $Message,
            MessageLong    => 'OpenSSL: ' . $MessageLong,
        );
    }
    return %Return;
}

=item Search()

search a certifcate or an private key

    my @Result = $CryptObject->Search(
        Search => 'some text to search',
    );

=cut

sub Search {
    my ( $Self, %Param ) = @_;

    my @Result = $Self->CertificateSearch(%Param);
    @Result = ( @Result, $Self->PrivateSearch(%Param) );
    return @Result;
}

=item CertificateSearch()

search a local certifcate

    my @Result = $CryptObject->CertificateSearch(
        Search => 'some text to search',
    );

=cut

sub CertificateSearch {
    my ( $Self, %Param ) = @_;

    my $Search = $Param{Search} || '';
    my @Result;
    my @Hash = $Self->CertificateList();
    for (@Hash) {
        my $Certificate = $Self->CertificateGet( Hash => $_ );
        my %Attributes = $Self->CertificateAttributes( Certificate => $Certificate );
        my $Hit = 0;
        if ($Search) {
            for ( keys %Attributes ) {
                if ( eval { $Attributes{$_} =~ /$Search/i } ) {
                    $Hit = 1;
                }
            }
        }
        else {
            $Hit = 1;
        }
        if ($Hit) {
            push @Result, \%Attributes;
        }
    }
    return @Result;
}

=item CertificateAdd()

add a certificate to local certificates

    $CryptObject->CertificateAdd(
        Certificate => $CertificateString,
    );

=cut

sub CertificateAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Certificate} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Certificate!' );
        return;
    }
    my %Attributes = $Self->CertificateAttributes(%Param);
    if ( $Attributes{Hash} ) {
        my $File = "$Self->{CertPath}/$Attributes{Hash}.0";
        if ( open( my $OUT, '>', $File ) ) {
            print $OUT $Param{Certificate};
            close($OUT);
            return 'Certificate uploaded!';
        }
        else {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Can't write $File: $!!" );
            return;
        }
    }
    $Self->{LogObject}->Log( Priority => 'error', Message => "Can't add invalid certificat!" );
    return;
}

=item CertificateGet()

get a local certificate

    my $Certificate = $CryptObject->CertificateGet(
        Hash => $CertificateHash,
    );

=cut

sub CertificateGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Hash} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Hash!' );
        return;
    }
    my $File = "$Self->{CertPath}/$Param{Hash}.0";
    my $CertificateRef = $Self->{MainObject}->FileRead( Location => $File );

    return if !$CertificateRef;

    return $$CertificateRef;
}

=item CertificateRemove()

remove a local certificate

    $CryptObject->CertificateRemove(
        Hash => $CertificateHash,
    );

=cut

sub CertificateRemove {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Hash} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Hash!' );
        return;
    }
    unlink "$Self->{CertPath}/$Param{Hash}.0" || return $!;
    return 1;
}

=item CertificateList()

get list of local certificates

    my @HashList = $CryptObject->CertificateList();

=cut

sub CertificateList {
    my ( $Self, %Param ) = @_;

    my @Hash;
    my @List = $Self->{MainObject}->DirectoryRead(
        Directory => "$Self->{CertPath}",
        Filter    => '*.0',
    );
    for my $File (@List) {
        $File =~ s!^.*/!!;
        $File =~ s/(.*)\.0/$1/;
        push @Hash, $File;
    }
    return @Hash;
}

=item CertificateAttributes()

get certificate attributes

    my %CertificateArrtibutes = $CryptObject->CertificateAttributes(
        Certificate => $CertificateString,
    );

=cut

sub CertificateAttributes {
    my ( $Self, %Param ) = @_;

    my %Attributes;
    if ( !$Param{Certificate} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Certificate!' );
        return;
    }
    my ( $FH, $Filename ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Certificate};
    close $FH;
    $Self->_FetchAttributesFromCert( $Filename, \%Attributes );
    if ( $Attributes{Hash} ) {
        my ($Private) = $Self->PrivateGet( Hash => $Attributes{Hash} );
        if ($Private) {
            $Attributes{Private} = 'Yes';
        }
        else {
            $Attributes{Private} = 'No';
        }
        $Attributes{Type} = 'cert';
    }
    return %Attributes;
}

=item PrivateSearch()

returns private keys

    my @Result = $CryptObject->PrivateSearch(
        Search => 'some text to search',
    );

=cut

sub PrivateSearch {
    my ( $Self, %Param ) = @_;

    my $Search = $Param{Search} || '';
    my @Result;
    my @Hash = $Self->CertificateList();
    for (@Hash) {
        my $Certificate = $Self->CertificateGet( Hash => $_ );
        my %Attributes = $Self->CertificateAttributes( Certificate => $Certificate );
        my $Hit = 0;
        if ($Search) {
            for ( keys %Attributes ) {
                if ( $Attributes{$_} =~ /$Search/i ) {
                    $Hit = 1;
                }
            }
        }
        else {
            $Hit = 1;
        }
        if ( $Hit && $Attributes{Private} eq 'Yes' ) {
            $Attributes{Type} = 'key';
            push @Result, \%Attributes;
        }
    }
    return @Result;
}

=item PrivateAdd()

add private key

    my $Message = $CryptObject->PrivateAdd(
        Private => $PrivateKeyString,
        Secret  => 'Password',
    );

=cut

sub PrivateAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Private} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Private!' );
        return;
    }

    # get private attributes
    my %Attributes = $Self->PrivateAttributes(%Param);
    if ( !$Attributes{Modulus} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'No Private Key!' );
        return;
    }

    # get certificate hash
    my @Certificates = $Self->CertificateSearch( Search => $Attributes{Modulus} );
    if ( !@Certificates ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need Certificate of Private Key first -$Attributes{Modulus})!",
        );
        return;
    }
    elsif ( $#Certificates > 0 ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Multiple Certificates with the same Modulus, can't add Private Key!",
        );
        return;
    }
    my %CertificateAttributes = $Self->CertificateAttributes(
        Certificate => $Self->CertificateGet( Hash => $Certificates[0]->{Hash} ),
    );
    if ( $CertificateAttributes{Hash} ) {
        my $File = "$Self->{PrivatePath}/$CertificateAttributes{Hash}";
        if ( open( my $PrivKeyFH, '>', "$File.0" ) ) {
            print $PrivKeyFH $Param{Private};
            close $PrivKeyFH;
            open( my $PassFH, '>', "$File.P" );
            print $PassFH $Param{Secret};
            close $PassFH;
            return 'Private Key uploaded!';
        }
        else {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Can't write $File: $!!" );
            return;
        }
    }
    $Self->{LogObject}->Log( Priority => 'error', Message => "Can't add invalid private key!" );
    return;
}

=item PrivateGet()

get private key

    my ($PrivateKey, $Secret) = $CryptObject->PrivateGet(
        Hash => $PrivateKeyHash,
    );

=cut

sub PrivateGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Hash} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Hash!' );
        return;
    }
    my $File = "$Self->{PrivatePath}/$Param{Hash}.0";
    if ( !-f $File ) {

        # no private exists
        return;
    }
    elsif ( open( my $IN, '<', $File ) ) {
        my $Private = '';
        while (<$IN>) {
            $Private .= $_;
        }
        close($IN);

        # read secret
        my $File   = "$Self->{PrivatePath}/$Param{Hash}.P";
        my $Secret = '';
        if ( open( my $IN, '<', $File ) ) {
            while (<$IN>) {
                $Secret .= $_;
            }
            close($IN);
        }
        return ( $Private, $Secret );
    }

    $Self->{LogObject}->Log( Priority => 'error', Message => "Can't open $File: $!!" );
    return;
}

=item PrivateRemove()

remove private key

    $CryptObject->PrivateRemove(
        Hash => $PrivateKeyHash,
    );

=cut

sub PrivateRemove {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Hash} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Hash!' );
        return;
    }

    # get the cert attributes
    my @Results = $Self->PrivateSearch( Search => $Param{Hash} );

    # delete all relations for this cert
    if (@Results) {
        $Self->SignerCertRelationDelete(
            CertFingerprint => $Results[0]->{Fingerprint},
            UserID          => 1,
        );
    }

    unlink "$Self->{PrivatePath}/$Param{Hash}.0" || return;
    unlink "$Self->{PrivatePath}/$Param{Hash}.P" || return;

    return 1;
}

=item PrivateList()

returns a list of private key hashs

    my @HashList = $CryptObject->PrivateList();

=cut

sub PrivateList {
    my ( $Self, %Param ) = @_;

    my @Hash;
    my @List = $Self->{MainObject}->DirectoryRead(
        Directory => "$Self->{PrivatePath}",
        Filter    => '*.0',
    );
    for my $File (@List) {
        $File =~ s!^.*/!!;
        $File =~ s/(.*)\.0/$1/;
        push @Hash, $File;
    }
    return @Hash;
}

=item PrivateAttributes()

returns attributes of private key

    my %Hash = $CryptObject->PrivateAttributes(
        Private => $PrivateKeyString,
        Secret => 'Password',
    );

=cut

sub PrivateAttributes {
    my ( $Self, %Param ) = @_;

    my %Attributes;
    my %Option = ( Modulus => '-modulus', );
    if ( !$Param{Private} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need Private!' );
        return;
    }
    my ( $FH, $Filename ) = $Self->{FileTempObject}->TempFile();
    print $FH $Param{Private};
    close $FH;
    my ( $FHSecret, $SecretFile ) = $Self->{FileTempObject}->TempFile();
    print $FHSecret $Param{Secret};
    close $FHSecret;
    my $Options    = "rsa -in $Filename -noout -modulus -passin file:$SecretFile";
    my $LogMessage = qx{$Self->{Cmd} $Options 2>&1};
    unlink $SecretFile;
    $LogMessage =~ tr{\r\n}{}d;
    $LogMessage =~ s/Modulus=//;
    $Attributes{Modulus} = $LogMessage;
    $Attributes{Type}    = 'P';
    return %Attributes;
}

=begin Internal:

=cut

sub _Init {
    my ( $Self, %Param ) = @_;

    $Self->{Bin}         = $Self->{ConfigObject}->Get('SMIME::Bin') || '/usr/bin/openssl';
    $Self->{CertPath}    = $Self->{ConfigObject}->Get('SMIME::CertPath');
    $Self->{PrivatePath} = $Self->{ConfigObject}->Get('SMIME::PrivatePath');

    if ( $^O =~ m{Win}i ) {

        # take care to deal properly with paths containing whitespace
        $Self->{Cmd} = qq{"$Self->{Bin}"};
    }
    else {

        # make sure that we are getting POSIX (i.e. english) messages from openssl
        $Self->{Cmd} = "LC_MESSAGES=POSIX $Self->{Bin}";
    }

    # ensure that there is a random state file that we can write to (otherwise openssl will bail)
    $ENV{RANDFILE} = $Self->{ConfigObject}->Get('TempDir') . '/.rnd';

    # prepend RANDFILE declaration to openssl cmd
    $Self->{Cmd}
        = "HOME=" . $Self->{ConfigObject}->Get('Home') . " RANDFILE=$ENV{RANDFILE} $Self->{Cmd}";

    # get the openssl version string, e.g. OpenSSL 0.9.8e 23 Feb 2007
    $Self->{OpenSSLVersionString} = qx{$Self->{Cmd} version};

    # get the openssl major version, e.g. 1 for version 1.0.0
    if ( $Self->{OpenSSLVersionString} =~ m{ \A (?: OpenSSL )? \s* ( \d )  }xmsi ) {
        $Self->{OpenSSLMajorVersion} = $1;
    }

    return $Self;
}

sub _FetchAttributesFromCert {
    my ( $Self, $Filename, $AttributesRef ) = @_;

    # The hash algorithm used in the -subject_hash and -issuer_hash options before OpenSSL 1.0.0
    # was based on the deprecated MD5 algorithm and the encoding of the distinguished name.
    # In OpenSSL 1.0.0 and later it is based on a canonical version of the DN using SHA1.
    #
    # output the hash of the certificate subject name using the older algorithm as
    # used by OpenSSL versions before 1.0.0.

    # hash
    my $HashAttribute = '-subject_hash';

    if ( $Self->{OpenSSLMajorVersion} >= 1 ) {
        $HashAttribute = '-subject_hash_old';
    }

    # testing new solution
    my $OptionString = ' '
        . "$HashAttribute "
        . '-issuer '
        . '-fingerprint -sha1 '
        . '-serial '
        . '-subject '
        . '-startdate '
        . '-enddate '
        . '-email '
        . '-modulus '
        . ' ';

    # call all attributes at same time
    my $Options = "x509 -in $Filename -noout $OptionString";

    # get the output string
    my $Output = qx{$Self->{Cmd} $Options 2>&1};

    # filters
    my %Filters = (
        Hash        => '(\w{8})',
        Issuer      => '(issuer=\s.*)',
        Fingerprint => 'SHA1\sFingerprint=(.*)',
        Serial      => '(serial=.*)',
        Subject     => 'subject=(.*)',
        StartDate   => 'notBefore=(.*)',
        EndDate     => 'notAfter=(.*)',
        Email       => '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4})',
        Modulus     => 'Modulus=(.*)',
    );

    # parse output string
    my @Attributes = split( /\n/, $Output );
    for my $Line (@Attributes) {

        # clean end spaces
        $Line =~ tr{\r\n}{}d;

        # look for every attribute by filter
        for my $Filter ( keys %Filters ) {
            if ( $Line =~ m{\A $Filters{$Filter} \z}xms ) {
                $AttributesRef->{$Filter} = $1;

          # delete the match key from filter  to don't search again this value and improve the speed
                delete $Filters{$Filter};
                last;
            }
        }
    }

    # prepare attributes data for use
    $AttributesRef->{Issuer}  =~ s/=/= /g;
    $AttributesRef->{Subject} =~ s/subject=//;
    $AttributesRef->{Subject} =~ s/\// /g;
    $AttributesRef->{Subject} =~ s/=/= /g;

    my %Month = (
        Jan => '01',
        Feb => '02',
        Mar => '03',
        Apr => '04',
        May => '05',
        Jun => '06',
        Jul => '07', Aug => '08', Sep => '09', Oct => '10', Nov => '11', Dec => '12',
    );

    for my $DateType ( 'StartDate', 'EndDate' ) {
        if ( $AttributesRef->{$DateType} =~ /(.+?)\s(.+?)\s(\d\d:\d\d:\d\d)\s(\d\d\d\d)/ ) {
            my $Day   = $2;
            my $Month = '';
            my $Year  = $4;

            if ( $Day < 10 ) {
                $Day = "0" . int($Day);
            }

            for my $MonthKey ( keys %Month ) {
                if ( $AttributesRef->{$DateType} =~ /$MonthKey/i ) {
                    $Month = $Month{$MonthKey};
                    last;
                }
            }
            $AttributesRef->{"Short$DateType"} = "$Year-$Month-$Day";
        }
    }
    return 1;
}

sub _CleanOutput {
    my ( $Self, $Output ) = @_;

    # remove spurious warnings that appear on Windows
    if ( $^O =~ m{Win}i ) {
        $Output =~ s{Loading 'screen' into random state - done\r?\n}{}igms;
    }

    return $Output;
}

=item SignerCertRelationAdd ()

add a relation between signer certificate and CA certificate to attach to the signature
returns 1 if success

    my $RelationID = $CryptObject->SignerCertRelationAdd(
        CertFingerprint => $CertFingerprint,
        CAFingerprint => $CAFingerprint,
        UserID => 1,
    );

=cut

sub SignerCertRelationAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw( CertFingerprint CAFingerprint UserID )) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Needed!" );
            return;
        }
    }

    if ( $Param{CertFingerprint} eq $Param{CAFingerprint} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'CertFingerprint must be different to the CAFingerprint param',
        );
        return;
    }

    # searh certificates by fingerprint
    my @CertResult = $Self->PrivateSearch(
        Search => $Param{CertFingerprint},
    );

    # results?
    if ( !scalar @CertResult ) {
        $Self->{LogObject}->Log(
            Message  => "Wrong CertFingerprint, certificate not found!",
            Priority => 'error',
        );
        return 0;
    }

    # searh certificates by fingerprint
    my @CAResult = $Self->CertificateSearch(
        Search => $Param{CAFingerprint},
    );

    # results?
    if ( !scalar @CAResult ) {
        $Self->{LogObject}->Log(
            Message  => "Wrong CAFingerprint, certificate not found!",
            Priority => 'error',
        );
        return 0;
    }

    my $Success = $Self->{DBObject}->Do(
        SQL => 'INSERT INTO smime_signer_cert_relations'
            . ' ( cert_hash, cert_fingerprint, ca_hash, ca_fingerprint, created, created_by, changed, changed_by)'
            . ' VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$CertResult[0]->{Hash}, \$CertResult[0]->{Fingerprint}, \$CAResult[0]->{Hash},
            \$CAResult[0]->{Fingerprint},
            \$Param{UserID}, \$Param{UserID},
        ],
    );

    return $Success;
}

=item SignerCertRelationGet ()

get relation data by ID or by Certificate finger print
returns data Hash if ID given or Array of all relations if CertFingerprint given

    my %Data = $CryptObject->SignerCertRelationGet(
        ID => $RelationID,
    );

    my @Data = $CryptObject->SignerCertRelationGet(
        CertFingerprint => $CertificateFingerprint,
    );

=cut

sub SignerCertRelationGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} && !$Param{CertFingerprint} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Needed ID or CertFingerprint!' );
        return;
    }

    # ID
    my %Data;
    my @Data;
    if ( $Param{ID} ) {
        my $Success = $Self->{DBObject}->Prepare(
            SQL =>
                'SELECT id, cert_hash, cert_fingerprint, ca_hash, ca_fingerprint, created, created_by, changed, changed_by'
                . ' FROM smime_signer_cert_relations'
                . ' WHERE id = ? ORDER BY created DESC',
            Bind  => [ \$Param{ID} ],
            Limit => 1,
        );

        if ($Success) {
            while ( my @ResultData = $Self->{DBObject}->FetchrowArray() ) {

                # format date
                %Data = (
                    ID              => $ResultData[0],
                    CertHash        => $ResultData[1],
                    CertFingerprint => $ResultData[2],
                    CAHash          => $ResultData[3],
                    CAFingerprint   => $ResultData[4],
                    Changed         => $ResultData[5],
                    ChangedBy       => $ResultData[6],
                    Created         => $ResultData[7],
                    CreatedBy       => $ResultData[8],
                );
            }
            return %Data || '';
        }
        else {
            $Self->{LogObject}->Log(
                Message  => 'DB error: not possible to get relation!',
                Priority => 'error',
            );
            return;
        }
    }
    else {
        my $Success = $Self->{DBObject}->Prepare(
            SQL =>
                'SELECT id, cert_hash, cert_fingerprint, ca_hash, ca_fingerprint, created, created_by, changed, changed_by'
                . ' FROM smime_signer_cert_relations'
                . ' WHERE cert_fingerprint = ? ORDER BY id DESC',
            Bind => [ \$Param{CertFingerprint} ],
        );

        if ($Success) {
            while ( my @ResultData = $Self->{DBObject}->FetchrowArray() ) {
                my %ResultData = (
                    ID              => $ResultData[0],
                    CertHash        => $ResultData[1],
                    CertFingerprint => $ResultData[2],
                    CAHash          => $ResultData[3],
                    CAFingerprint   => $ResultData[4],
                    Changed         => $ResultData[5],
                    ChangedBy       => $ResultData[6],
                    Created         => $ResultData[7],
                    CreatedBy       => $ResultData[8],
                );
                push @Data, \%ResultData;
            }
            return @Data;
        }
        else {
            $Self->{LogObject}->Log(
                Message  => 'DB error: not possible to get relations!',
                Priority => 'error',
            );
            return;
        }
    }
    return;
}

=item SignerCertRelationExists ()

returns the ID if the relation exists

    my $Result = $CryptObject->SignerCertRelationExists(
        CertFingerprint => $CertificateFingerprint,
        CAFingerprint => $CAFingerprint,
    );

    my $Result = $CryptObject->SignerCertRelationExists(
        ID => $RelationID,
    );

=cut

sub SignerCertRelationExists {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} && !( $Param{CertFingerprint} && $Param{CAFingerprint} ) ) {
        $Self->{LogObject}
            ->Log( Priority => 'error', Message => "Need ID or CertFingerprint & CAFingerprint!" );
        return;
    }

    if ( $Param{CertFingerprint} && $Param{CAFingerprint} ) {
        my $Data;
        my $Success = $Self->{DBObject}->Prepare(
            SQL => 'SELECT id FROM smime_signer_cert_relations '
                . 'WHERE cert_fingerprint = ? AND ca_fingerprint = ?',
            Bind => [ \$Param{CertFingerprint}, \$Param{CAFingerprint} ],
            Limit => 1,
        );

        if ($Success) {
            while ( my @ResultData = $Self->{DBObject}->FetchrowArray() ) {
                $Data = $ResultData[0];
            }
            return $Data || '';
        }
        else {
            $Self->{LogObject}->Log(
                Message  => 'DB error: not possible to check relation!',
                Priority => 'error',
            );
            return;
        }
    }
    elsif ( $Param{ID} ) {
        my $Data;
        my $Success = $Self->{DBObject}->Prepare(
            SQL => 'SELECT id FROM smime_signer_cert_relations '
                . 'WHERE id = ?',
            Bind  => [ \$Param{ID}, ],
            Limit => 1,
        );

        if ($Success) {
            while ( my @ResultData = $Self->{DBObject}->FetchrowArray() ) {
                $Data = $ResultData[0];
            }
            return $Data || '';
        }
        else {
            $Self->{LogObject}->Log(
                Message  => 'DB error: not possible to check relation!',
                Priority => 'error',
            );
            return;
        }
    }

    return;
}

=item SignerCertRelationDelete ()

returns 1 if success

    # delete all relations for a cert
    my $Success = $CryptObject->SignerCertRelationDelete (
        CertFingerprint => $CertFingerprint,
        UserID => 1,
    );

    # delete one relation by ID
    $Success = $CryptObject->SignerCertRelationDelete (
        ID => '45',
        UserID => 1,
    );

    # delete one relation by CertFingerprint & CAFingerprint
    $Success = $CryptObject->SignerCertRelationDelete (
        CertFingerprint => $CertFingerprint,
        CAFingerprint   => $CAFingerprint,
        UserID => 1,
    );

=cut

sub SignerCertRelationDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw( UserID )) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Needed!" );
            return;
        }
    }

    if ( !$Param{CertFingerprint} && !$Param{ID} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need ID or CertFingerprint!' );
        return;
    }

    if ( $Param{ID} ) {

        # delete row
        my $Success = $Self->{DBObject}->Do(
            SQL => 'DELETE FROM smime_signer_cert_relations '
                . 'WHERE id = ?',
            Bind => [ \$Param{ID} ],
        );

        if ( !$Success ) {
            $Self->{LogObject}->Log(
                Message  => "DB Error, Not possible to delete relation ID:$Param{ID}!",
                Priority => 'error',
            );
        }
        return $Success;
    }
    elsif ( $Param{CertFingerprint} && $Param{CAFingerprint} ) {

        # delete one row
        my $Success = $Self->{DBObject}->Do(
            SQL => 'DELETE FROM smime_signer_cert_relations '
                . 'WHERE cert_fingerprint = ? AND ca_fingerprint = ?',
            Bind => [ \$Param{CertFingerprint}, \$Param{CAFingerprint} ],
        );

        if ( !$Success ) {
            $Self->{LogObject}->Log(
                Message =>
                    "DB Error, Not possible to delete relation for "
                    . "CertFingerprint:$Param{CertFingerprint} and CAFingerprint:$Param{CAFingerprint}!",
                Priority => 'error',
            );
        }
        return $Success;
    }
    else {

        # delete all rows
        my $Success = $Self->{DBObject}->Do(
            SQL => 'DELETE FROM smime_signer_cert_relations '
                . 'WHERE cert_fingerprint = ?',
            Bind => [ \$Param{CertFingerprint} ],
        );

        if ( !$Success ) {
            $Self->{LogObject}->Log(
                Message =>
                    "DB Error, Not possible to delete relations for CertFingerprint:$Param{CertFingerprint}!",
                Priority => 'error',
            );
        }
        return $Success;
    }
    return;
}

1;

=end Internal:

=cut

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.52 $ $Date: 2011-05-18 18:21:43 $

=cut
