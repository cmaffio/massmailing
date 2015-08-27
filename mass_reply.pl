#!/usr/bin/perl
$|=1;
use FindBin qw($Bin);
use DBI;
use Switch;

require "$Bin/mass_mailing.conf";
$file_log = "$Bin/mass_mailing.log";

my $destinatario;
my $action;
my $status;
my $stato;
my $dc;
my $id_user;
my $message_id;

my $last = "";
while (<>) {
	if (/^Original-Recipient: rfc822;\s*([\w_\.-]+@[\w\.-]+)/) {
		$destinatario = $1;
		next;
	}

	if (/^Action: (.*)$/) {
		$action = lc($1);

		switch ($action) {
			case "failed" { $stato = -2 }
			case "delivered" { $stato = 1 }
			case "expanded" { $stato = 1 }
			case "relayed" { $stato = 1 }
			case "delayed" { $stato = -1 }
		}

		next;
	}

	if (/^Status: (.*)$/) {
		$status = $1;
		next;
	}

	if (/^Diagnostic-Code: (.*)$/) {
		$dc = $1;
		$last = "dc";
		next;
	}

	if (/^\s+(.*)$/ && $last eq "dc") {
		$last = "";
		$dc .= " $1";
		next;
	}

	$server_id = $conf{'server_id'};
	if (/^Message-Id: <(\d+)\.(\d+)\@$server_id>/) {
		$id_user = $1;
		$message_id = $2;
		next;
	}

	if ($last ne "") {
		$last = "";
		next;
	}
}

my $sql = "SELECT invii.id FROM invii JOIN destinatari ON invii.id_destinatari = destinatari.id WHERE message_id = '$id_user.$message_id' AND destinatari.indirizzo = '$destinatario' AND invii.stato IN (0, -1)";

my $sth = $db->prepare($sql);
$sth->execute();
my $numrows = $sth->rows;
if ($numrows == 1) {
	my ($id) = $sth->fetchrow_array;
	$dc = AddSlashes($dc);
	my $sql = "UPDATE invii SET data_reply = NOW(), stato = $stato, action = '$action', status = '$status', dc = '$dc' WHERE id = $id";
	save_query ($sql);
	$sth = $db->prepare($sql);
	$sth->execute();

	if ($stato == -2) {

		my $sql = "	UPDATE
					destinatari
				SET
					errori = errori + 1,
					stato  = CASE WHEN errori >= ".$conf{'maxerr'}." THEN stato = 0 ELSE stato = 1 END,
					data_mod = NOW()
				WHERE
					id = $id_user
		";

		$sth = $db->prepare($sql);
		$sth->execute();

	}
}

sub AddSlashes {
	$text = shift;
	## Make sure to do the backslash first!
	$text =~ s/\\/\\\\/g;
	$text =~ s/'/\\'/g;
	$text =~ s/"/\\"/g;
	$text =~ s/\\0/\\\\0/g;
	return $text;
}

sub save_query {
	my $query = shift;

	open LOG, ">> $file_log";

	print LOG "$query\n";
	close LOG;
}
