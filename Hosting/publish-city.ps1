param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName,
    [Parameter(Mandatory = $true)]
    [string]$DistributionId,
    [string]$Region = 'us-east-1'
)

$ErrorActionPreference = 'Stop'
$cityBuild = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Frontend-City/penguincity/build/web'))
if (-not (Test-Path -LiteralPath (Join-Path $cityBuild 'index.html'))) {
    throw 'Build the city Flutter web app before publishing.'
}
if ($BucketName -notmatch '^[a-z0-9][a-z0-9.-]+[a-z0-9]$') {
    throw 'BucketName must be an S3 bucket name, without a URL or path.'
}

$destination = "s3://$BucketName/"
aws s3 sync "$cityBuild/" $destination --cache-control no-cache --region $Region --exclude '*.mjs' --exclude '*.wasm'
if ($LASTEXITCODE -ne 0) { throw 'City app upload failed.' }

# AWS CLI MIME guessing can label Dart/Amplify module workers as text/plain.
# cp deliberately reapplies metadata even when the bytes have not changed.
aws s3 cp "$cityBuild/" $destination --recursive --exclude '*' --include '*.mjs' --content-type application/javascript --cache-control no-cache --region $Region
if ($LASTEXITCODE -ne 0) { throw 'JavaScript module upload failed.' }
aws s3 cp "$cityBuild/" $destination --recursive --exclude '*' --include '*.wasm' --content-type application/wasm --cache-control no-cache --region $Region
if ($LASTEXITCODE -ne 0) { throw 'WebAssembly upload failed.' }

aws cloudfront create-invalidation --distribution-id $DistributionId --paths '/*'
if ($LASTEXITCODE -ne 0) { throw 'CloudFront invalidation failed.' }
