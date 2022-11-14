Prerequisites:
1. Set the execution policy to RemoteSigned.
	Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
2. Install "Az" module running below command.
	Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

3. Run the databox-copy-manageddisk-to-storageaccount.ps1 from powershell windows which prompts for Subscriptio, ResourceGroup, DiskName, Storage Account Name, Container, Storage Account Key and Destination VHD name.
   After entering above details, scripts prompts for Authentication to connect to Azure. 

Below is the script execution with output.
PS C:\> .\databox-copy-manageddisk-to-storageaccount.ps1
Enter Subscription ID:: xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx                                                            
Enter Resource Group:: testrg
Enter Disk Name:: testmanageddisk.vhd
Enter Storage Account Name:: testsa
Enter Storage account container name:: mdisktopage
Enter Storage Account Key:: <storage account Key>
Enter Destination VHD name:: destinationMdname.vhd
WARNING: TenantId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' contains more than one active subscription. First one will be
selected for further use. To select another subscription, use Set-AzContext.

Account               SubscriptionName          TenantId                             Environment
-------               ----------------          --------                             -----------
test@contoso.com Subscription Name yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy AzureCloud

Name               : Subscription Name (xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) - yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy -
                     test@contoso.com
Account            : test@contoso.com
Environment        : AzureCloud
Subscription       : xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Tenant             : yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
TokenCache         :
VersionProfile     :
ExtendedProperties : {}


ICloudBlob                         : Microsoft.Azure.Storage.Blob.CloudPageBlob
BlobType                           : PageBlob
Length                             : size
IsDeleted                          : False
BlobClient                         : Azure.Storage.Blobs.BlobClient
BlobBaseClient                     : Azure.Storage.Blobs.BlobClient
BlobProperties                     : Azure.Storage.Blobs.Models.BlobProperties
RemainingDaysBeforePermanentDelete :
ContentType                        : application/octet-stream
LastModified                       : 8/12/2022 12:24:19 AM +00:00
SnapshotTime                       :
ContinuationToken                  :
VersionId                          :
IsLatestVersion                    : False
AccessTier                         :
TagCount                           : 0
Tags                               :
Context                            : Microsoft.WindowsAzure.Commands.Storage.AzureStorageContext
Name                               : destinationMdname.vhd



PS C:\>