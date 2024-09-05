# mail-migration

A tool that handles IMAP mail migrations including a safe maildir backup

## Prerequisites

### Origin mailbox passwords

Currently, due to a bug in offlineimap, origin (!) mailbox passwords cannot contain % signs.
Issue: [https://github.com/OfflineIMAP/offlineimap/issues/650](https://github.com/OfflineIMAP/offlineimap/issues/650)

### Software

Install the following applications:

-   offlineimap3 [https://github.com/OfflineIMAP/offlineimap3](https://github.com/OfflineIMAP/offlineimap3) (not offlineimap!!)
-   imapsync [https://github.com/imapsync/imapsync](https://github.com/imapsync/imapsync)
-   jq [https://github.com/jqlang/jq](https://github.com/jqlang/jq)

#### Mac OS

On Mac OS these are available via homebrew:

-   offlineimap3 [https://formulae.brew.sh/formula/offlineimap](https://formulae.brew.sh/formula/offlineimap)
-   imapsync [https://formulae.brew.sh/formula/imapsync](https://formulae.brew.sh/formula/imapsync)
-   jq [https://formulae.brew.sh/formula/jq](https://formulae.brew.sh/formula/jq)

### Microsoft OAUTH2 requirements

When migrating to microsoft oauth2, please make sure you have the following set up:

-   IMAP App enabled in Exchange Admin Portal
-   A "Mobile and desktop applications" (!!) App named "imapsync" created in Azure AD, with the following specs:
    -   IMAP.AccessAsUser.All
    -   Of type: Mobile and desktop applications
    -   redirect url: http://localhost:8087

## Get Started

First, you will need to clone this repo.
We recommend that you do this for every new migration project!

## Instructions

**1. Run setup**

Execute setup.sh: `./setup.sh`.
This will ask you (in a loop) for the connection data of your origin and destination mailboxes.

**2. Run backup setup**

Execute setup-backup.sh: `./setup-backup.sh`.
This will prepare the necessary files to backup all mailboxes.

**3. Run backup**

Execute backup.sh to create a backup of all set up origin accounts: `./backup.sh`

-> You can then find the backups in the `migrations/<sub-folder>/maildir-backup/` folder.

**4. Run migration dry run**

To verify the setup migrations, run the migration dry run: `./migration.sh --dry-run`.
This will NOT change anything on either the origin or destination mailbox.

-> Check the logs of this dry run in the `migrations/<sub-folder>/imapsync/logs/dry-run/` folder.

**5. Run migration dry run**

To execute the final migrations, run the migration: `./migration.sh`.
This will sync all mails from origin to destination, with the following specs:

-   Not deleting messages on destination that are not on origin

## Test oauth2

Once the `setup.sh` script has been run, you can test the oauth2 connection by running `./oauth2-test.sh`.

Don't worry, this will also run in the backup and migration script ☺️

## Planned improvements

**Better oauth2 flow for microsoft**

We are currently using the /authorize flow to generate an oauth2 access token for every user.

-   This can probably be improved by just authenticating once as the admin.
-   Maybe there is another flow that needs no manual login via webbrowser, which would make this script able to run on a server.

**Encrypt sensitive data locally**

We could use a secrets manager (like infisical) to query an encryption secret.

-   Encrypt all data that we store locally (encryption at rest).

**Generate log summary**

It would be cool to generate a log summary (redacted!!) for the last backup and the last migration logs.
This can then be pasted into an AI for analysis without the need to look at it!

**Export of backups script**

Create a script that exports all backups into a handy, encrypted archive.

-> Where to store the encryption key?
