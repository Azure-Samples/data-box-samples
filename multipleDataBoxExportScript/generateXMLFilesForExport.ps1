param (
    [Parameter(Mandatory = $true, ParameterSetName = "byPodSize")]
    [Parameter(Mandatory = $true, ParameterSetName = "byPodDevice")]
    [string]$SubscriptionName,

    [Parameter(Mandatory = $true, ParameterSetName = "byPodSize")]
    [Parameter(Mandatory = $true, ParameterSetName = "byPodDevice")]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, ParameterSetName = "byPodSize")]
    [Parameter(Mandatory = $true, ParameterSetName = "byPodDevice")]
    [string]$StorageAccountName,


    [Parameter(Mandatory = $true, ParameterSetName = "byPodSize")]
    [ValidateRange(1, [long]::MaxValue)]
    [long]$DataSize,

    [Parameter(Mandatory = $true, ParameterSetName = "byPodDevice")]
    [ValidateSet('DataBox', 'DataBoxHeavy')]
    [string]$Device = 'DataBox',

    [string[]]$ContainerNames = "",

    [ValidateRange(1, [int]::MaxValue)]
    [int]$BatchSize = 100000,

    [string]$StorageAccountKey,

    [int]$maxBlobsInExportOrder=500000000, # soft limit of 500 million blobs per order

    # testing args
    [string]$FailureContainer,
    [long]$FailAfterNBlobs

)

Start-Transcript -Path "$PSScriptroot/log.txt" -IncludeInvocationHeader

if ($DataSize -eq 0) {
    if ($Device -eq "DataBox") {
        $DataSize = 76TB * 0.95
    }
    elseif ($Device -eq "DataBoxHeavy") {
        $DataSize = 764TB * 0.95
    }
}


# classes
class StorageBin {
    [string] $fileName
    [system.IO.StreamWriter] $sw
    [long] $remainingStorage 
    [long] $numBlobs
    [long] $storageSize
    
    StorageBin($storageSize, $storageAccountName) {
        $this.fileName = "$PSScriptRoot/exportxmlfiles/export_$($storageAccountName)_$(Get-Date -Format "yyyy-MM-dd_HHmmssfff").xml"
        $this.remainingStorage = $storageSize
        $this.storageSize = $storageSize
        $this.numBlobs = 0

        $fileStream = New-Object system.IO.Filestream($this.fileName, 4)
        $this.sw = New-Object system.IO.StreamWriter($fileStream)

        $this.writeHeader()
    }

    StorageBin($storageSize, $remainingStorage, $fileName, $numBlobs, $filePosition) {
        $this.fileName = $fileName
        $this.numBlobs = $numBlobs
        $this.storageSize = $storageSize
        $this.remainingStorage = $remainingStorage

        $fileStream = New-Object system.IO.Filestream($this.fileName, 4)
        $fileStream.Seek($filePosition, 0)
        $this.sw = New-Object system.IO.StreamWriter($fileStream, ([System.Text.Encoding]::UTF8), 10MB)

    }
    writeHeader() {
        $this.sw.WriteLine("<?xml version=""1.0"" encoding=""utf-8""?>")
        $this.sw.WriteLine("<BlobList>")
    }
    writeBlob($containerName, $blob) {
        $this.sw.WriteLine("`t<BlobPath size='$($blob.Length)'>" + "/" + $containerName + "/" + $blob.Name + "</BlobPath>")
        $this.remainingStorage -= $blob.Length
        $this.numBlobs += 1
    }
    writeSummary() {
        $this.sw.WriteLine("<Summary>")
        $this.sw.WriteLine("`t<numBlobs>$($this.numBlobs)</numBlobs>")
        $this.sw.WriteLine("`t<podSize>$($this.storageSize)</podSize>")
        $this.sw.WriteLine("`t<storageConsumed>$($this.storageSize - $this.remainingStorage)</storageConsumed>")
        $this.sw.WriteLine("`t<remainingStorage>$($this.remainingStorage)</remainingStorage>")
        $this.sw.WriteLine("</Summary>")
    }
    closeBin() {
        $this.sw.WriteLine("</BlobList>")
        $this.writeSummary()
        $this.sw.Close()
    }
}

class state {
    [System.Object] $token 
    [int] $containerIdx
    [long] $blobCount
    [StorageBin] $currentBin

    # metadata about previous run
    [string]$subscriptionName
    [string]$resourceGroupName
    [string]$storageAccountName
    [string[]]$containerNames
    [long]$dataSize
    [string] $dateTime

    state () {}

    state($token, $containerIdx, $blobCount, $currentBin, $subscriptionName, $resourceGroupName, $storageAccountName, $containerNames) {
        $this.token = $token
        $this.containerIdx = $containerIdx
        $this.blobCount = $blobCount
        $this.currentBin = $currentBin

        $this.subscriptionName = $subscriptionName
        $this.resourceGroupName = $resourceGroupName
        $this.storageAccountName = $storageAccountName
        $this.containerNames = $containerNames
        $this.dateTime = Get-Date
    }

    saveToJson() {
        $json = @{
            'token'        = $this.token   
            'containerIdx' = $this.containerIdx
            'blobCount'    = $this.blobCount
            'currentBin'   = @{
                'fileName'         = $this.currentBin.fileName
                'numBlobs'         = $this.currentBin.numBlobs
                'storageSize'      = $this.currentBin.storageSize
                'remainingStorage' = $this.currentBin.remainingStorage
                'filePosition'     = $this.currentBin.sw.BaseStream.Position
            }
            'meta'         = @{
                'subscriptionName'       = $this.subscriptionName
                'resourceGroupName'  = $this.resourceGroupName
                'storageAccountName' = $this.storageAccountName
                'containerNames'     = $this.containerNames
                'dateTime'           = $this.dateTime
            }
        }
        ConvertTo-Json $json -Depth 3 | Out-File "checkpoint.json"
    }
}

function getNextBlobBatch($blobContainers, $containerIdx, $continuationToken, $batchSize) {
    $blobContainer = $blobContainers[$containerIdx]
    try {
        $blobs = $blobContainer | Get-AzStorageBlob -MaxCount $batchSize -ContinuationToken $continuationToken -ClientTimeoutPerRequest 240 -ErrorAction Stop
        return $blobs
    }
    catch {
        if ($_.Exception.Message -like "*Server failed to authenticate the request.*") {
            Write-Error "Get-AzStorageBlob - Could not authenticate the request. Please check your StorageAccountKey" -ErrorAction Stop
        }
        else {
            $_
        }
    }
}

function areMoreBlobsInContainer($token) {
    return $null -ne $token
}

function getContainers($storageAccountContext, $containerNames) {
    if ($containerNames) {
        $containers = @()
        foreach ($name in $containerNames) {
            $containers += Get-AzStorageContainer -Context $storageAccountContext -Name $name -ErrorAction Stop
        }
        return $containers
    }
    else {
        return Get-AzStorageContainer -Context $storageAccountContext -ErrorAction Stop #gets all containers in account
    }
}

function matchesPreviousRun($subscriptionName, $resourceGroupName, $storageAccountName, $containerNames) {
    $prevRunMeta = (Get-Content "checkpoint.json" | Out-String | ConvertFrom-Json).meta

    $prevRunContainerNamesStr = $prevRunMeta.containerNames -join ","
    $containerNamesStr = $containerNames -join ","

    [bool]$ret = ($prevRunMeta.subscriptionName -eq $subscriptionName -and $prevRunMeta.resourceGroupName -eq $resourceGroupName -and $prevRunMeta.storageAccountName -eq $storageAccountName -and $prevRunContainerNamesStr -eq $containerNamesStr)
    return $ret
}

function userWantsToLoadCheckpoint() {
    $dateTime = (Get-Content "checkpoint.json" | Out-String | ConvertFrom-Json).meta.dateTime

    $resp = Read-Host -Prompt "Would you like to load from checkpoint for previous job ran at $($dateTime)? (Y)/N"
    $resp.ToLower()
    return ($resp -eq 'y') -or (!$resp)
}

function createNewOutputDir() {
    if (Test-Path -Path "$PSScriptRoot\exportxmlfiles") {
        Remove-Item "$PSScriptRoot\exportxmlfiles" -Recurse
    }
    New-Item -Path $PSScriptRoot -Name "exportxmlfiles" -ItemType "directory" | Out-Null
}

function deleteCheckpointIfExists () {
    if (Test-Path -Path "$PSScriptRoot\checkpoint.json") {
        Remove-Item "$PSScriptRoot\checkpoint.json"
    }
}

function getStorageAccountContextFromAccountKey($storageAccountName, $storageAccountKey) {
    Write-Host "authenticating storage account with storageAccountKey"
    $storageAccountContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey -ErrorAction Stop
    return $storageAccountContext
}

function getStorageAccountContextFromCredentialsOrSavedContext($resourceGroupName, $storageAccountName, $subscriptionName) {
    $currentContext = Get-AzContext
    if ($currentContext.Subscription.Name -eq $subscriptionName) {
        Write-Host "storage account context loaded from previous run, skipping authentication"
    }
    else {
        Write-Host "authenticating storage account.."
        Connect-AzAccount -Subscription $subscriptionName -ErrorAction Stop | Out-Null
        Write-Host "storage account authenticated"
    }
    $storageAccountContext = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop).Context
    return $storageAccountContext
}

function shouldLoadCheckpoint ($subscriptionName, $resourceGroupName, $storageAccountName, $containerNames) {
    $shouldLoadCheckpoint = (Test-Path -Path "checkpoint.json") -and (matchesPreviousRun $subscriptionName $resourceGroupName $storageAccountName $containerNames) -and ((userWantsToLoadCheckpoint) -eq $true)
    return $shouldLoadCheckpoint
}

function createNewState($subscriptionName, $resourceGroupName, $storageAccountName, $containerNames, $dataSize) {
    $token = $null
    $containerIdx = 0
    $blobCount = 0
    $currentBin = [StorageBin]::new($dataSize, $storageAccountName)
    return [state]::new($token, $containerIdx, $blobCount, $currentBin, $subscriptionName, $resourceGroupName, $storageAccountName, $containerNames)
}

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function loadStateFromCheckpoint() {
    $jsonData = (Get-Content "checkpoint.json" | Out-String | ConvertFrom-Json)
    [state] $state = [state]::new()
    $state.token = $jsonData.token
    $state.containerIdx = $jsonData.containerIdx
    $state.blobCount = $jsonData.blobCount

    $currentBinData = $jsonData.currentBin
    $state.currentBin = [StorageBin]::new($currentBinData.storageSize, $currentBinData.remainingStorage, $currentBinData.fileName, $currentBinData.numBlobs, $currentBinData.filePosition)

    $state.subscriptionName = $jsonData.meta.subscriptionName
    $state.resourceGroupName = $jsonData.meta.resourceGroupName
    $state.storageAccountName = $jsonData.meta.storageAccountName
    $state.containerNames = $jsonData.meta.containerNames
    $state.dateTime = $jsonData.meta.dateTime
    return $state
}

# Main program starts here
try {
    # authentication logic
    if ($StorageAccountKey) {
        $storageAccountContext = getStorageAccountContextFromAccountKey $StorageAccountName $StorageAccountKey
    }
    else {
        $storageAccountContext = getStorageAccountContextFromCredentialsOrSavedContext $ResourceGroupName $StorageAccountName $SubscriptionName
    }

    # creating new state or loading previous state from checkpoint file
    if (shouldLoadCheckpoint $SubscriptionName $ResourceGroupName $StorageAccountName $ContainerNames) {
        $state = loadStateFromCheckpoint
    }
    else {
        createNewOutputDir
        deleteCheckpointIfExists
        $state = createNewState $SubscriptionName $ResourceGroupName $StorageAccountName $ContainerNames $DataSize
    }

    #getting containers 
    try {
        $blobContainers = getContainers $storageAccountContext $ContainerNames
    }
    catch {
        if ($_.Exception.Message -like "*Server failed to authenticate the request.*") {
            Write-Error "getContainers - Could not authenticate the request. Please check your StorageAccountKey" -ErrorAction Stop
        }
        else {
            Write-Error $_ -ErrorAction Stop
        }
    }

    if (!$blobContainers) {
        Write-Error "No containers matching '$ContainerNames' found in '$StorageAccountName'" -ErrorAction Stop
    }
    Write-Host "$(Get-Timestamp) Processing containers: '$($blobContainers.Name)', storage account: '${StorageAccountName}', resource group: '${ResourceGroupName}'"

    # enumerating each blob in container and writing to xml file
    for ($state.containerIdx; $state.containerIdx -lt $blobContainers.Length; $state.containerIdx++) {

        $containerName = $blobContainers[$state.containerIdx].Name
        Write-Host "`n$(Get-TimeStamp) processing container: '$containerName'..."

        do {
            #save checkpoint
            $state.currentBin.sw.Flush()
            $state.saveToJson()

            #for testing, sets failure point after enumerating n blobs in x container
            if ($FailureContainer) {
                if ($ContainerNames[$state.containerIdx] -eq $FailureContainer -and $state.blobCount -ge $FailAfterNBlobs) {
                    Write-Error "exception" -ErrorAction Stop
                }
            }

            # get blob batch from azure
            $blobs = getNextBlobBatch $blobContainers $state.containerIdx $state.token $BatchSize
            if ($blobs.Length -le 0) {
                Write-Error "getNextBlobBatch returned 0 blobs, please check that the data in $containerName has not been deleted" -ErrorAction Stop
            }
            $state.blobCount += $blobs.Count
            $state.token = $blobs[$blobs.Count - 1].ContinuationToken

            # write blob batch to xml files
            foreach ($blob in $blobs) {
                if ($blob.Length -gt $DataSize) {
                    Write-Error "the size of one blob cannot be greater than the device size" -ErrorAction Stop
                }
                if (($state.currentBin.remainingStorage - $blob.Length) -lt 0 -or ($state.currentBin.numBlobs -ge $maxBlobsInExportOrder)) {
                    $state.currentBin.closeBin()
                    Write-Host -ForeGroundColor Green "`r$(Get-TimeStamp) $($state.currentBin.fileName) is ready for an export order!" | timestamp
                    Write-Host -ForeGroundColor Yellow -NoNewLine "$(Get-TimeStamp) blobs processed: $($state.blobCount)"
                    $state.currentBin = [StorageBin]::new($DataSize, $StorageAccountName)
                }
                $state.currentBin.writeBlob($containerName, $blob)
            }

            # write yellow output if enumeration is still in progress, otherwise white
            Write-Host -ForeGroundColor Yellow -NoNewLine "`r$(Get-TimeStamp) blobs processed: $($state.blobCount)"
            if (-not (areMoreBlobsInContainer $state.token)) {
                Write-Host -NoNewLine "`r$(Get-Timestamp) blobs processed: $($state.blobCount)"
            }
            
        } while (areMoreBlobsInContainer $state.token)
    }
    Remove-Item "checkpoint.json"
    $state.currentBin.closeBin()
    Write-Host -ForeGroundColor Green "`n$(Get-TimeStamp) processing complete, export xml files generated successfully in exportxmlfiles/" 

}
finally {
    if ($state) {
        $state.currentBin.sw.Close()
    }
    Stop-Transcript
}