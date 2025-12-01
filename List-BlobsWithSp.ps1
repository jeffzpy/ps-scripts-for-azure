param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $false)]
    [string]$Prefix,

    [Parameter(Mandatory = $false)]
    [switch]$RawXml
)

function Get-StorageAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://storage.azure.com/.default"
        grant_type    = "client_credentials"
    }

    Write-Verbose "Requesting AAD token for https://storage.azure.com/"

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $response = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body -ErrorAction Stop
    return $response.access_token
}

function Get-BlobList {
    param(
        [string]$AccessToken,
        [string]$StorageAccountName,
        [string]$ContainerName,
        [string]$Prefix
    )

    $baseUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName"
    $uri = "$baseUri?restype=container&comp=list"

    if ($Prefix) {
        $uri += "&prefix=$([uri]::EscapeDataString($Prefix))"
    }

    $allBlobs = @()

    while ($true) {
        $headers = @{
            Authorization  = "Bearer $AccessToken"
            "x-ms-version" = "2023-11-03"
            "x-ms-date"    = (Get-Date).ToUniversalTime().ToString("R")
        }

        Write-Verbose "Calling: $uri"

        $response = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -ErrorAction Stop

        [xml]$xml = $response.Content

        if ($RawXml) {
            $xml
        }

        $blobs = $xml.EnumerationResults.Blobs.Blob

        foreach ($blob in $blobs) {
            $obj = [PSCustomObject]@{
                Name          = $blob.Name
                LastModified  = [datetime]$blob.Properties.'Last-Modified'
                ContentLength = [int64]$blob.Properties.'Content-Length'
                ContentType   = $blob.Properties.'Content-Type'
                ETag          = $blob.Properties.ETag
            }
            $allBlobs += $obj
        }

        $nextMarker = $xml.EnumerationResults.NextMarker

        if ([string]::IsNullOrEmpty($nextMarker)) {
            break
        }

        # Continue with marker for next page
        $uri = "$baseUri?restype=container&comp=list&marker=$([uri]::EscapeDataString($nextMarker))"
        if ($Prefix) {
            $uri += "&prefix=$([uri]::EscapeDataString($Prefix))"
        }
    }

    return $allBlobs
}

try {
    Write-Host "Getting AAD token for Storage using service principal..." -ForegroundColor Cyan
    $accessToken = Get-StorageAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

    Write-Host "Listing blobs in container '$ContainerName' from storage account '$StorageAccountName'..." -ForegroundColor Cyan
    if ($Prefix) {
        Write-Host "Prefix filter: $Prefix" -ForegroundColor Cyan
    }

    $result = Get-BlobList -AccessToken $accessToken -StorageAccountName $StorageAccountName -ContainerName $ContainerName -Prefix $Prefix

    Write-Host "Total blobs found: $($result.Count)" -ForegroundColor Green
    $result | Format-Table -AutoSize
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails)" -ForegroundColor DarkRed
    }
    throw
}
