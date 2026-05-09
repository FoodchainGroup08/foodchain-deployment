# FoodChain Branch Hours Seeder - Lagos, Nigeria
# Fetches branches dynamically then sets hours per branch type.

$BASE       = 'http://localhost:8081/api'
$HEADS      = @{ 'Content-Type' = 'application/json'; 'X-User-Id' = 'seed-script'; 'X-User-Role' = 'OFFICE_ADMIN' }
$HEADS_GET  = @{ 'X-User-Id' = 'seed-script'; 'X-User-Role' = 'OFFICE_ADMIN' }

function PutHours($branchId, $hours) {
    try {
        Invoke-RestMethod -Method PUT -Uri "$BASE/branch/$branchId/hours" -Headers $HEADS -Body ($hours | ConvertTo-Json -Depth 3)
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $null
    }
}

# ── Hour schedule templates ────────────────────────────────────────────────────
# dayOfWeek: 0=Mon 1=Tue 2=Wed 3=Thu 4=Fri 5=Sat 6=Sun

# Upscale (VI, Ikoyi, Lekki) - later open, later close on weekends
function Get-UpscaleHours {
    @(
        @{ dayOfWeek=0; openTime='11:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=1; openTime='11:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=2; openTime='11:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=3; openTime='11:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=4; openTime='11:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=5; openTime='11:00:00'; closeTime='23:30:00'; closed=$false },
        @{ dayOfWeek=6; openTime='12:00:00'; closeTime='21:00:00'; closed=$false }
    )
}

# Commuter hub (Oshodi, Maryland, Ikeja) - early open for breakfast crowd
function Get-CommuterHours {
    @(
        @{ dayOfWeek=0; openTime='07:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=1; openTime='07:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=2; openTime='07:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=3; openTime='07:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=4; openTime='07:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=5; openTime='08:00:00'; closeTime='21:00:00'; closed=$false },
        @{ dayOfWeek=6; openTime='09:00:00'; closeTime='20:00:00'; closed=$false }
    )
}

# Student area (Yaba) - late nights Mon-Sat, lighter on Sunday
function Get-StudentHours {
    @(
        @{ dayOfWeek=0; openTime='09:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=1; openTime='09:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=2; openTime='09:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=3; openTime='09:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=4; openTime='09:00:00'; closeTime='23:30:00'; closed=$false },
        @{ dayOfWeek=5; openTime='10:00:00'; closeTime='23:30:00'; closed=$false },
        @{ dayOfWeek=6; openTime='11:00:00'; closeTime='21:00:00'; closed=$false }
    )
}

# Standard (Surulere, Festac, Ajah) - typical Lagos restaurant hours
function Get-StandardHours {
    @(
        @{ dayOfWeek=0; openTime='10:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=1; openTime='10:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=2; openTime='10:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=3; openTime='10:00:00'; closeTime='22:00:00'; closed=$false },
        @{ dayOfWeek=4; openTime='10:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=5; openTime='10:00:00'; closeTime='23:00:00'; closed=$false },
        @{ dayOfWeek=6; openTime='11:00:00'; closeTime='21:00:00'; closed=$false }
    )
}

# ── Fetch all branches ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Fetching branches...' -ForegroundColor Cyan

try {
    $resp = Invoke-RestMethod -Method GET -Uri "$BASE/branch?size=50" -Headers $HEADS_GET
} catch {
    Write-Host "ERROR fetching branches: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Handle both paged (content array) and plain array responses
if ($resp.content) {
    $branches = $resp.content
} else {
    $branches = $resp
}

Write-Host "  Found $($branches.Count) branches" -ForegroundColor Green

# ── Assign hours template per branch name ─────────────────────────────────────
Write-Host ''
Write-Host 'Setting branch hours...' -ForegroundColor Cyan

$ok   = 0
$fail = 0

foreach ($b in $branches) {
    $name = $b.name

    if ($name -like '*Victoria Island*' -or $name -like '*Ikoyi*' -or $name -like '*Lekki*') {
        $hours = Get-UpscaleHours
        $type  = 'Upscale'
    } elseif ($name -like '*Oshodi*' -or $name -like '*Maryland*' -or $name -like '*Ikeja*') {
        $hours = Get-CommuterHours
        $type  = 'Commuter'
    } elseif ($name -like '*Yaba*') {
        $hours = Get-StudentHours
        $type  = 'Student'
    } else {
        $hours = Get-StandardHours
        $type  = 'Standard'
    }

    $r = PutHours $b.id $hours
    if ($r) {
        Write-Host "  OK [$type] $name" -ForegroundColor Green
        $ok++
    } else {
        Write-Host "  FAIL $name" -ForegroundColor Red
        $fail++
    }
}

Write-Host ''
Write-Host "Done. $ok branches updated, $fail failed." -ForegroundColor Cyan
