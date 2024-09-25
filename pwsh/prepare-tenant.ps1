Install-Module -Name ExchangeOnlineManagement
Import-module ExchangeOnlineManagement

# Collect required information
$tenantAdminEmail = Read-Host "Enter the tenant admin email address"
$servicePrincipalAppId = Read-Host "Enter the service principal application ID"
$servicePrincipalObjectId = Read-Host "Enter the service principal object ID"

# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName $tenantAdminEmail

# Check if the service principal already exists
$existingServicePrincipal = Get-ServicePrincipal -Identity $servicePrincipalAppId -ErrorAction SilentlyContinue

if (-not $existingServicePrincipal) {
    # Create new service principal
    try {
        New-ServicePrincipal -AppId $servicePrincipalAppId -ObjectId $servicePrincipalObjectId -ErrorAction Stop
        Write-Host "Service principal created successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create service principal." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "Service principal already exists. Skipping creation." -ForegroundColor Yellow
}

# Get all user mailboxes
$mailboxes = Get-Mailbox -ResultSize Unlimited -Filter {RecipientTypeDetails -eq "UserMailbox"}

# Loop through each mailbox and add the permission
foreach ($mailbox in $mailboxes) {
    try {
        Add-MailboxPermission -Identity $mailbox.UserPrincipalName -User $servicePrincipalObjectId -AccessRights FullAccess -ErrorAction Stop
        Write-Host "Successfully added permission to mailbox: $($mailbox.UserPrincipalName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to add permission to mailbox: $($mailbox.UserPrincipalName)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false