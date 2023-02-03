---
title: Export data from Azure VM
description: Export data from Azure VMs into an Azure Data Box.
services: databox
author: sipastak

ms.service: databox
ms.subservice: pod
ms.topic: sample
ms.date: 02/02/2023
ms.author: alkohli
---

# Export data from an Azure VM into an Azure Data Box

The `databoxExportVm.ps` exports data from your Azure VM into your Azure Data Box device. 

## Prerequisites

Before you begin, make sure you have:

- PowerShell installed. See [Install Windows PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell?view=powershell-7.1).
- Az PowerShell module installed. See [Install Az PowerShell 6.4.0](https://docs.microsoft.com/powershell/azure/install-az-ps?view=azps-6.4.0&preserve-view=true).
- `databoxExportVm.ps` script, stored in a convenient location. Go to the [repo in Azure Samples where Data Box sample files are stored](https://github.com/Azure-Samples/data-box-samples). The script is located in the ExportVmScript folder.

## Run the script

1. Set the execution policy to RemoteSigned.

	```
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. Install the Az module.

	```
   Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
   ```

3. Run the `databoxExportVm.ps1` script. It will prompt for Subscription, ResourceGroup, DiskName, Storage Account Name, Container, Storage Account Key, and Destination VHD name.
   
    After entering the above details, the script will prompt you for authentication to connect to Azure. 

    Below is the script execution with output.

    ```
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
    ```
    Output: 

    ```    
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
    ```