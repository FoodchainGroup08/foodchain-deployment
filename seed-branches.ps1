# FoodChain Branch Seeder - Lagos, Nigeria
# Calls branch-service directly on port 8081 - no JWT needed.

$BASE  = 'http://localhost:8081/api'
$HEADS = @{ 'Content-Type' = 'application/json'; 'X-User-Id' = 'seed-script'; 'X-User-Role' = 'OFFICE_ADMIN' }

function Post($url, $body) {
    try {
        Invoke-RestMethod -Method POST -Uri $url -Headers $HEADS -Body ($body | ConvertTo-Json -Depth 3)
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $null
    }
}

function Activate($id) {
    try {
        Invoke-RestMethod -Method PATCH -Uri "$BASE/branch/$id/activate" -Headers $HEADS
    } catch {
        Write-Host "  WARN: Could not activate $id - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Creating branches in Lagos, Nigeria...' -ForegroundColor Cyan

$branches = @(
    @{
        name        = 'FoodChain Victoria Island'
        address     = '15 Adeola Odeku Street, Victoria Island, Lagos'
        phone       = '+234-812-001-0001'
        description = 'Our flagship Victoria Island location. Upscale dining in the heart of VI business district.'
        latitude    = 6.4281
        longitude   = 3.4219
    },
    @{
        name        = 'FoodChain Lekki Phase 1'
        address     = '24 Admiralty Way, Lekki Phase 1, Lagos'
        phone       = '+234-812-001-0002'
        description = 'Serving the Lekki corridor with dine-in, takeaway and delivery options.'
        latitude    = 6.4474
        longitude   = 3.4756
    },
    @{
        name        = 'FoodChain Ikoyi'
        address     = '3 Kingsway Road, Ikoyi, Lagos'
        phone       = '+234-812-001-0003'
        description = 'Nestled in the quiet streets of Ikoyi, perfect for a relaxed meal.'
        latitude    = 6.4509
        longitude   = 3.4355
    },
    @{
        name        = 'FoodChain Ikeja GRA'
        address     = '7 Joel Ogunnaike Street, Ikeja GRA, Lagos'
        phone       = '+234-812-001-0004'
        description = 'Conveniently located in Ikeja GRA, minutes from the airport and Alausa.'
        latitude    = 6.5958
        longitude   = 3.3419
    },
    @{
        name        = 'FoodChain Surulere'
        address     = '52 Adeniran Ogunsanya Street, Surulere, Lagos'
        phone       = '+234-812-001-0005'
        description = 'A mainland favourite, busy and lively with quick service for the Surulere crowd.'
        latitude    = 6.5020
        longitude   = 3.3510
    },
    @{
        name        = 'FoodChain Yaba'
        address     = '18 Herbert Macaulay Way, Yaba, Lagos'
        phone       = '+234-812-001-0006'
        description = 'Right in the tech hub of Lagos, popular with Unilag students and startup teams.'
        latitude    = 6.5052
        longitude   = 3.3740
    },
    @{
        name        = 'FoodChain Ajah'
        address     = 'Abraham Adesanya Estate, Lekki-Epe Expressway, Ajah, Lagos'
        phone       = '+234-812-001-0007'
        description = 'Serving the fast-growing Ajah and Sangotedo communities on the Lekki corridor.'
        latitude    = 6.4698
        longitude   = 3.5678
    },
    @{
        name        = 'FoodChain Maryland'
        address     = '12 Ikorodu Road, Maryland, Lagos'
        phone       = '+234-812-001-0008'
        description = 'Maryland Mall area branch, ideal for shoppers and commuters heading to the mainland.'
        latitude    = 6.5632
        longitude   = 3.3582
    },
    @{
        name        = 'FoodChain Festac Town'
        address     = '2nd Avenue, Festac Town, Lagos'
        phone       = '+234-812-001-0009'
        description = 'Proudly serving the Festac community with great food and a family atmosphere.'
        latitude    = 6.4631
        longitude   = 3.2743
    },
    @{
        name        = 'FoodChain Oshodi'
        address     = 'International Airport Road, Oshodi, Lagos'
        phone       = '+234-812-001-0010'
        description = 'High-traffic location serving commuters and travellers near the Oshodi interchange.'
        latitude    = 6.5570
        longitude   = 3.3394
    }
)

$created  = 0
$failed   = 0
$branchIds = @()

foreach ($b in $branches) {
    $payload = @{
        name        = $b.name
        address     = $b.address
        phone       = $b.phone
        description = $b.description
        latitude    = $b.latitude
        longitude   = $b.longitude
    }
    $r = Post "$BASE/branch" $payload
    if ($r -and $r.id) {
        Write-Host "  OK $($b.name) -> $($r.id)" -ForegroundColor Green
        $branchIds += $r.id
        $created++
    } else {
        $failed++
    }
}

Write-Host ''
Write-Host 'Activating branches...' -ForegroundColor Cyan

foreach ($id in $branchIds) {
    Activate $id
    Write-Host "  ACTIVATED $id" -ForegroundColor Green
}

Write-Host ''
Write-Host "Done. $created branches created and activated, $failed failed." -ForegroundColor Cyan
