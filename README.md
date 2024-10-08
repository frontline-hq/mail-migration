# mail-migration

A bash toolset that handles IMAP mail migrations including a safe maildir backup.

Capabilities:

-   Automated setup using shell script
-   Automatic mass backup of all [origin, destination] pairs from automatic setup (as maildir)
-   Automatic mass migration of all [origin, destination] pairs from automatic setup
-   Automatic Microsoft OAUTH2 handling
-   Every backup and migration run is documented via log files

Limitations:

-   Can only backup mailboxes where the password doesnt contain '%' chars (but migration works!)
-   Backups of oauth2 based imap authentication is not possible, but can be in the future
-   Currently only set up to migrate from regular IMAPS to MICROSOFT IMAPS OAUTH2 mailboxes

## Prerequisites

### Origin mailbox passwords

Currently, due to a bug in offlineimap, origin (!) mailbox passwords cannot contain % signs.
Issue: [https://github.com/OfflineIMAP/offlineimap/issues/650](https://github.com/OfflineIMAP/offlineimap/issues/650)

### Software

Install the following applications:

-   offlineimap3 [https://github.com/OfflineIMAP/offlineimap3](https://github.com/OfflineIMAP/offlineimap3) (not offlineimap!!)
-   imapsync [https://github.com/imapsync/imapsync](https://github.com/imapsync/imapsync)
-   jq [https://github.com/jqlang/jq](https://github.com/jqlang/jq)
-   powershell (pwsh) [https://learn.microsoft.com/de-de/powershell/scripting/install/installing-powershell?view=powershell-7.4](https://learn.microsoft.com/de-de/powershell/scripting/install/installing-powershell?view=powershell-7.4)

#### Mac OS

On Mac OS these are available via homebrew:

-   offlineimap3 [https://formulae.brew.sh/formula/offlineimap](https://formulae.brew.sh/formula/offlineimap)
-   imapsync [https://formulae.brew.sh/formula/imapsync](https://formulae.brew.sh/formula/imapsync)
-   jq [https://formulae.brew.sh/formula/jq](https://formulae.brew.sh/formula/jq)
-   powershell (pwsh) [https://github.com/PowerShell/Homebrew-Tap](https://github.com/PowerShell/Homebrew-Tap)

### Microsoft OAUTH2 requirements

When migrating to microsoft oauth2, please make sure you have the following set up (depending on your flow!!):

#### authorize flow

-   IMAP App enabled in Exchange Admin Portal
-   A "Mobile and desktop applications" (!!) App named "imapsync" created in Azure AD, with the following specs:
    -   Permissions -> Microsoft Graph -> IMAP.AccessAsUser.All
    -   Grant admin consent on permissions!
    -   Of type: Mobile and desktop applications
    -   redirect url: http://localhost:8087

#### client credentials flow

-   IMAP App enabled in Exchange Admin Portal
-   A "Mobile and desktop applications" (!!) App named "imapsync" created in Azure AD, with the following specs:
    -   Permissions -> Office 365 Exchange Online -> IMAP.AccessAsApp
    -   Grant admin consent on permissions!
    -   Of type: Mobile and desktop applications
-   Run the `./pwsh/prepare-tenant.ps1` script to prepare the tenant: `pwsh -File ./pwsh/prepare-tenant.ps1` (You can find the service principal application and object id in `Microsoft Entra admin center -> Applications -> Enterprise applications -> <your-app-name> -> Overview -> Properties`)

## Get Started

First, you will need to clone this repo.
We recommend that you do this for every new migration project!

## Instructions

**0. Take care of prerequisites**

I.e. if you are using microsoft client credentials flow, make sure that the corresponding tenant(s) are correctly set up using our instructions and the powershell script.

**1. Run setup**

Execute setup.sh: `./setup.sh`.
This will ask you (in a loop) for the connection data of your origin and destination mailboxes.

**2. Run backup setup**

Execute setup-backup.sh: `./setup-backup.sh`.
This will prepare the necessary files to backup all mailboxes.

**3. Run backup**

Execute backup.sh to create a backup of all set up origin accounts: `./backup.sh`

-> You can then find the backups in the `migrations/<sub-folder>/maildir-backup/` folder.

**4. Run migration setup**

Execute setup-backup.sh: `./setup-migration.sh`.
This will prepare the necessary files to migrate all mailboxes.

**5. Run migration dry run**

To verify the setup migrations, run the migration dry run: `./migration.sh --dry-run`.
This will NOT change anything on either the origin or destination mailbox.

-> Check the logs of this dry run in the `migrations/<sub-folder>/imapsync/logs/dry-run/` folder.

**6. Run migration**

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
-   Maybe there is another flow that needs no manual login via webbrowser but instead server-to-server, which would make this script able to run on a server.

**Handling of expired oauth2 token**

It seems that imapsync will crash when the oauth2 token expires.

-> Can this be handled and automatically refreshed while running?

**Encrypt sensitive data locally**

We could use a secrets manager (like infisical) to query an encryption secret.

-   Encrypt all data that we store locally (encryption at rest).

**Generate log summary**

It would be cool to generate a log summary (redacted!!) for the last backup and the last migration logs.
This can then be pasted into an AI for analysis without the need to look at it!

**Export of backups script**

Create a script that exports all backups into a handy, encrypted archive.

-> Where to store the encryption key?
