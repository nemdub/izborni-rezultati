# ============================================================================
# Izborni Rezultati - RIK (Windows PowerShell verzija)
# ============================================================================
# Ova skripta koristi zvanični veb servis Republičke izborne komisije za
# učitavanje podataka o izbornim rezultatima:
# https://www.rik.parlament.gov.rs
#
# Skripta vodi korisnika kroz proces odabira tipa izbora, izbornog kruga,
# regiona, opštine i biračkih mesta, zatim učitava rezultate glasanja
# i snima ih u CSV fajlove.
# ============================================================================

# Ensure UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$BASE_URL = "https://www.rik.parlament.gov.rs"
$OUTPUT_DIR = ".\output"
$TMP_DIR = ".\output\tmp"
$PDF_DIR = ".\output\pdf"

# Common headers for web requests
$USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36'

# Cyrillic to Latin mapping (built dynamically for PowerShell 5.1 compatibility)
$CyrillicToLatin = @{}
# Upper and lowercase pairs: Cyrillic hex code, Latin equivalent
$mappings = @(
    @(0x0410, 'A'),  @(0x0430, 'a')   # А, а
    @(0x0411, 'B'),  @(0x0431, 'b')   # Б, б
    @(0x0412, 'V'),  @(0x0432, 'v')   # В, в
    @(0x0413, 'G'),  @(0x0433, 'g')   # Г, г
    @(0x0414, 'D'),  @(0x0434, 'd')   # Д, д
    @(0x0402, 'Dj'), @(0x0452, 'dj')  # Ђ, ђ
    @(0x0415, 'E'),  @(0x0435, 'e')   # Е, е
    @(0x0416, 'Z'),  @(0x0436, 'z')   # Ж, ж
    @(0x0417, 'Z'),  @(0x0437, 'z')   # З, з
    @(0x0418, 'I'),  @(0x0438, 'i')   # И, и
    @(0x0408, 'J'),  @(0x0458, 'j')   # Ј, ј
    @(0x041A, 'K'),  @(0x043A, 'k')   # К, к
    @(0x041B, 'L'),  @(0x043B, 'l')   # Л, л
    @(0x0409, 'Lj'), @(0x0459, 'lj')  # Љ, љ
    @(0x041C, 'M'),  @(0x043C, 'm')   # М, м
    @(0x041D, 'N'),  @(0x043D, 'n')   # Н, н
    @(0x040A, 'Nj'), @(0x045A, 'nj')  # Њ, њ
    @(0x041E, 'O'),  @(0x043E, 'o')   # О, о
    @(0x041F, 'P'),  @(0x043F, 'p')   # П, п
    @(0x0420, 'R'),  @(0x0440, 'r')   # Р, р
    @(0x0421, 'S'),  @(0x0441, 's')   # С, с
    @(0x0422, 'T'),  @(0x0442, 't')   # Т, т
    @(0x040B, 'C'),  @(0x045B, 'c')   # Ћ, ћ
    @(0x0423, 'U'),  @(0x0443, 'u')   # У, у
    @(0x0424, 'F'),  @(0x0444, 'f')   # Ф, ф
    @(0x0425, 'H'),  @(0x0445, 'h')   # Х, х
    @(0x0426, 'C'),  @(0x0446, 'c')   # Ц, ц
    @(0x0427, 'C'),  @(0x0447, 'c')   # Ч, ч
    @(0x040F, 'Dz'), @(0x045F, 'dz')  # Џ, џ
    @(0x0428, 'S'),  @(0x0448, 's')   # Ш, ш
)
foreach ($m in $mappings) {
    $CyrillicToLatin[[char]$m[0]] = $m[1]
}

# Convert Cyrillic to Latin
function Convert-CyrillicToLatin {
    param([string]$Text)

    $result = $Text
    foreach ($key in $CyrillicToLatin.Keys) {
        # Convert char key to string for .Replace(string, string) method
        $result = $result.Replace([string]$key, $CyrillicToLatin[$key])
    }
    return $result
}

# Print colored output
function Write-Info { param([string]$Message) Write-Host "i " -ForegroundColor Cyan -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Err { param([string]$Message) Write-Host "[X] " -ForegroundColor Red -NoNewline; Write-Host $Message }

# Print banner
function Show-Banner {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "                   Izborni Rezultati - RIK                        " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Print step header
function Show-Step {
    param([int]$StepNum, [string]$StepTitle)
    Write-Host ""
    Write-Host ("=" * 68) -ForegroundColor Blue
    Write-Host "Korak ${StepNum}: $StepTitle" -ForegroundColor Green
    Write-Host ("=" * 68) -ForegroundColor Blue
    Write-Host ""
}

# Setup directories
function Initialize-Directories {
    if (-not (Test-Path $OUTPUT_DIR)) { New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null }
    if (-not (Test-Path $TMP_DIR)) { New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null }
    if (-not (Test-Path $PDF_DIR)) { New-Item -ItemType Directory -Path $PDF_DIR -Force | Out-Null }
    Write-Success "Kreiran izlazni direktorijum: $OUTPUT_DIR"
}

# Make API request
function Invoke-ApiRequest {
    param(
        [string]$Url,
        [string]$Body,
        [string]$OutputFile
    )

    $headers = @{
        "Referer" = "$BASE_URL/"
        "User-Agent" = $USER_AGENT
        "Origin" = $BASE_URL
        "Accept" = "application/json, text/javascript, */*; q=0.01"
        "Accept-Language" = "en-US,en;q=0.9"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
        "X-Requested-With" = "XMLHttpRequest"
        "Content-Type" = "application/x-www-form-urlencoded; charset=utf-8"
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -Method POST -Headers $headers -Body $Body -UseBasicParsing
        $response.Content | Out-File -FilePath $OutputFile -Encoding UTF8
        return $response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            return $_.Exception.Response.StatusCode.value__
        }
        return 0
    }
}

# Interactive menu selector
function Select-FromMenu {
    param(
        [array]$Ids,
        [array]$Names
    )

    $total = $Ids.Count
    $script:menuSelected = 0
    $script:menuViewportStart = 0
    $viewportSize = 15

    if ($total -lt $viewportSize) {
        $viewportSize = $total
    }

    Write-Info "Koristite strelice GORE/DOLE za navigaciju, ENTER za potvrdu izbora"
    Write-Host ""

    # Total lines needed for menu (top indicator + items + bottom indicator)
    $menuHeight = $viewportSize + 2

    # Ensure we have enough space by printing empty lines first
    for ($i = 0; $i -lt $menuHeight; $i++) {
        Write-Host ""
    }

    # Now move cursor back up to where we'll start drawing
    $startY = [Console]::CursorTop - $menuHeight

    # Hide cursor
    [Console]::CursorVisible = $false

    # Get console width (leave 1 char margin to prevent wrapping)
    $consoleWidth = [Console]::WindowWidth - 1
    if ($consoleWidth -lt 40) { $consoleWidth = 40 }

    function Draw-Menu {
        # Adjust viewport to keep selected item visible
        if ($script:menuSelected -lt $script:menuViewportStart) {
            $script:menuViewportStart = $script:menuSelected
        }
        elseif ($script:menuSelected -ge ($script:menuViewportStart + $viewportSize)) {
            $script:menuViewportStart = $script:menuSelected - $viewportSize + 1
        }

        $lineNum = 0

        # Top scroll indicator
        [Console]::SetCursorPosition(0, $startY + $lineNum)
        if ($script:menuViewportStart -gt 0) {
            $text = "  ^ jos $($script:menuViewportStart) iznad"
        } else {
            $text = ""
        }
        $text = $text.PadRight($consoleWidth)
        if ($text.Length -gt $consoleWidth) { $text = $text.Substring(0, $consoleWidth) }
        if ($script:menuViewportStart -gt 0) {
            Write-Host $text -ForegroundColor Cyan -NoNewline
        } else {
            Write-Host $text -NoNewline
        }
        $lineNum++

        # Draw visible items
        for ($i = 0; $i -lt $viewportSize; $i++) {
            [Console]::SetCursorPosition(0, $startY + $lineNum)

            $itemIndex = $script:menuViewportStart + $i
            if ($itemIndex -lt $total) {
                $id = $Ids[$itemIndex]
                $name = $Names[$itemIndex]

                # Truncate name if too long
                $prefix = "  [$id] "
                $maxNameLen = $consoleWidth - $prefix.Length - 1
                if ($maxNameLen -lt 10) { $maxNameLen = 10 }
                if ($name.Length -gt $maxNameLen) {
                    $name = $name.Substring(0, $maxNameLen - 3) + "..."
                }

                if ($itemIndex -eq $script:menuSelected) {
                    $text = "> [$id] $name"
                } else {
                    $text = "  [$id] $name"
                }
                $text = $text.PadRight($consoleWidth)
                if ($text.Length -gt $consoleWidth) { $text = $text.Substring(0, $consoleWidth) }

                if ($itemIndex -eq $script:menuSelected) {
                    Write-Host $text -ForegroundColor Green -NoNewline
                } else {
                    Write-Host $text -NoNewline
                }
            } else {
                Write-Host (" " * $consoleWidth) -NoNewline
            }
            $lineNum++
        }

        # Bottom scroll indicator
        [Console]::SetCursorPosition(0, $startY + $lineNum)
        $remaining = $total - $script:menuViewportStart - $viewportSize
        if ($remaining -gt 0) {
            $text = "  v jos $remaining ispod"
        } else {
            $text = ""
        }
        $text = $text.PadRight($consoleWidth)
        if ($text.Length -gt $consoleWidth) { $text = $text.Substring(0, $consoleWidth) }
        if ($remaining -gt 0) {
            Write-Host $text -ForegroundColor Cyan -NoNewline
        } else {
            Write-Host $text -NoNewline
        }
        $lineNum++

        # Move cursor to end
        [Console]::SetCursorPosition(0, $startY + $lineNum)
    }

    Draw-Menu

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { # Up arrow
                if ($script:menuSelected -gt 0) { $script:menuSelected-- }
                Draw-Menu
            }
            40 { # Down arrow
                if ($script:menuSelected -lt ($total - 1)) { $script:menuSelected++ }
                Draw-Menu
            }
            13 { # Enter
                [Console]::CursorVisible = $true
                Write-Host ""
                $result = $script:menuSelected
                # Clean up script-level variables
                Remove-Variable -Name menuSelected -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name menuViewportStart -Scope Script -ErrorAction SilentlyContinue
                return $result
            }
        }
    }
}

# Download PDFs from results
function Get-PdfsFromResults {
    param(
        [string]$ResponseFile,
        [string]$StationId,
        [string]$StationName
    )

    $pdfCount = 0

    try {
        $json = Get-Content $ResponseFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $minuteHtml = $json.minute_from_election_station

        if (-not $minuteHtml) { return 0 }

        # Extract PDF URLs from HTML
        $pdfMatches = [regex]::Matches($minuteHtml, "href='([^']*\.pdf)'")

        foreach ($match in $pdfMatches) {
            $pdfPath = $match.Groups[1].Value
            $pdfFilename = Split-Path $pdfPath -Leaf
            $outputPdf = Join-Path $PDF_DIR "${StationId}_${pdfFilename}"
            $fullUrl = "${BASE_URL}${pdfPath}"

            try {
                $headers = @{
                    "Referer" = "$BASE_URL/"
                    "User-Agent" = $USER_AGENT
                }
                Invoke-WebRequest -Uri $fullUrl -Headers $headers -OutFile $outputPdf -UseBasicParsing
                if (Test-Path $outputPdf) { $pdfCount++ }
            }
            catch {
                # Ignore download errors
            }
        }
    }
    catch {
        # Ignore JSON parsing errors
    }

    return $pdfCount
}

# Extract metadata from results
function Get-ResultsMetadata {
    param([object]$Json)

    $metadata = @{
        Registered = "N/A"
        Voted = "N/A"
        Invalid = "N/A"
        Valid = "N/A"
    }

    if ($Json.stat_sum_numbers) {
        $metadata.Registered = $Json.stat_sum_numbers.total_voters
        $metadata.Voted = $Json.stat_sum_numbers.available
        if ($Json.sum_config.data.datasets[0].data) {
            $metadata.Valid = $Json.sum_config.data.datasets[0].data[0]
            $metadata.Invalid = $Json.sum_config.data.datasets[0].data[1]
        }
    }

    return $metadata
}

# Parse party results
function Get-PartyResults {
    param([object]$Json)

    $results = @()

    if ($Json.table_data) {
        foreach ($item in $Json.table_data) {
            $results += [PSCustomObject]@{
                Name = Convert-CyrillicToLatin $item.list_name
                Votes = $item.won_number
                Percent = $item.won_percent
            }
        }
    }
    elseif ($Json.results) {
        foreach ($item in $Json.results) {
            # PowerShell 5.1 compatible null coalescing
            $name = if ($item.party_name) { $item.party_name } elseif ($item.name) { $item.name } else { $item.naziv }
            $votes = if ($null -ne $item.votes) { $item.votes } elseif ($null -ne $item.glasovi) { $item.glasovi } else { 0 }
            $pct = if ($item.percentage) { $item.percentage } elseif ($item.procenat) { $item.procenat } else { "0" }
            $results += [PSCustomObject]@{
                Name = Convert-CyrillicToLatin $name
                Votes = $votes
                Percent = $pct
            }
        }
    }

    return $results
}

# Step 1: Choose election type
function Select-ElectionType {
    Show-Step 1 "Odabir tipa izbora"
    Write-Info "Odaberite tip izbora:"
    Write-Host ""

    $typeIds = @(2, 3, 7)
    $typeNames = @("Parlamentarni", "Lokalni", "Pokrajinski")

    $selectedIndex = Select-FromMenu -Ids $typeIds -Names $typeNames

    $script:ELECTION_TYPE = $typeIds[$selectedIndex]
    $script:ELECTION_TYPE_NAME = $typeNames[$selectedIndex]

    Write-Host ""
    Write-Success "Izabran tip izbora: [$ELECTION_TYPE] $ELECTION_TYPE_NAME"
}

# Step 2: Choose election round
function Select-ElectionRound {
    Show-Step 2 "Odabir izbornog kruga"
    Write-Info "Ucitavam dostupne izborne krugove..."
    Write-Host ""

    $url = "$BASE_URL/get-elections/"
    $responseFile = Join-Path $TMP_DIR ("elections_response_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $data = "election_type=$ELECTION_TYPE"

    $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

    if ($httpCode -ne 200) {
        Write-Err "Greska pri ucitavanju izbornih krugova (HTTP: $httpCode)"
        exit 1
    }

    $json = Get-Content $responseFile -Raw -Encoding UTF8 | ConvertFrom-Json

    $roundIds = @()
    $roundNames = @()

    if ($json.rounds) {
        $json.rounds.PSObject.Properties | ForEach-Object {
            $roundIds += $_.Name
            $roundNames += Convert-CyrillicToLatin $_.Value
        }
    }

    if ($roundIds.Count -eq 0) {
        Write-Err "Nema dostupnih izbornih krugova za izabrani tip izbora."
        exit 1
    }

    Write-Success "Ucitano $($roundIds.Count) izbornih krugova"
    Write-Host ""
    Write-Info "Odaberite izborni krug:"
    Write-Host ""

    $selectedIndex = Select-FromMenu -Ids $roundIds -Names $roundNames

    $script:ELECTION_ROUND = $roundIds[$selectedIndex]
    $script:ELECTION_ROUND_NAME = $roundNames[$selectedIndex]

    Write-Host ""
    Write-Success "Izabran izborni krug: [$ELECTION_ROUND] $ELECTION_ROUND_NAME"
}

# Step 3: Choose region
function Select-Region {
    Show-Step 3 "Odabir regiona"
    Write-Info "Ucitavam dostupne regione..."
    Write-Host ""

    $url = "$BASE_URL/get-regions/"
    $responseFile = Join-Path $TMP_DIR ("regions_response_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $data = "election_type=$ELECTION_TYPE&election_round=$ELECTION_ROUND"

    $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

    if ($httpCode -ne 200) {
        Write-Err "Greska pri ucitavanju regiona (HTTP: $httpCode)"
        exit 1
    }

    $json = Get-Content $responseFile -Raw -Encoding UTF8 | ConvertFrom-Json

    $regionIds = @()
    $regionNames = @()

    if ($json.regions) {
        $json.regions.PSObject.Properties | ForEach-Object {
            $regionIds += $_.Name
            $regionNames += Convert-CyrillicToLatin $_.Value
        }
    }

    if ($regionIds.Count -eq 0) {
        Write-Err "Nema dostupnih regiona za izabrani izborni krug."
        exit 1
    }

    Write-Success "Ucitano $($regionIds.Count) regiona"
    Write-Host ""
    Write-Info "Odaberite region:"
    Write-Host ""

    $selectedIndex = Select-FromMenu -Ids $regionIds -Names $regionNames

    $script:REGION_ID = $regionIds[$selectedIndex]
    $script:REGION_NAME = $regionNames[$selectedIndex]

    Write-Host ""
    Write-Success "Izabran region: [$REGION_ID] $REGION_NAME"
}

# Step 4: Choose municipality
function Select-Municipality {
    Show-Step 4 "Odabir opstine / grada"
    Write-Info "Ucitavam dostupne opstine/gradove..."
    Write-Host ""

    $url = "$BASE_URL/get-municipalities/"
    $responseFile = Join-Path $TMP_DIR ("municipalities_response_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $data = "election_type=$ELECTION_TYPE&election_round=$ELECTION_ROUND&election_region=$REGION_ID"

    $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

    if ($httpCode -ne 200) {
        Write-Err "Greska pri ucitavanju opstina/gradova (HTTP: $httpCode)"
        exit 1
    }

    $content = Get-Content $responseFile -Raw -Encoding UTF8

    $municipalityIds = @()
    $municipalityNames = @()

    # Parse HTML options: <option value="26">Ada</option>
    $valueMatches = [regex]::Matches($content, 'value="([^"]*)"')
    $nameMatches = [regex]::Matches($content, '>([^<]+)</option>')

    for ($i = 0; $i -lt $valueMatches.Count; $i++) {
        $municipalityIds += $valueMatches[$i].Groups[1].Value
        if ($i -lt $nameMatches.Count) {
            $municipalityNames += Convert-CyrillicToLatin $nameMatches[$i].Groups[1].Value
        }
    }

    if ($municipalityIds.Count -eq 0) {
        Write-Err "Nema dostupnih opstina/gradova za izabrani region."
        exit 1
    }

    Write-Success "Ucitano $($municipalityIds.Count) opstina/gradova"
    Write-Host ""
    Write-Info "Odaberite opstinu/grad:"
    Write-Host ""

    $selectedIndex = Select-FromMenu -Ids $municipalityIds -Names $municipalityNames

    $script:MUNICIPALITY_ID = $municipalityIds[$selectedIndex]
    $script:MUNICIPALITY_NAME = $municipalityNames[$selectedIndex]

    Write-Host ""
    Write-Success "Izabrana opstina/grad: [$MUNICIPALITY_ID] $MUNICIPALITY_NAME"
}

# Step 5: Get election stations
function Get-ElectionStations {
    Show-Step 5 "Ucitavanje birackih mesta"
    Write-Info "Ucitavam dostupna biracka mesta..."
    Write-Host ""

    $url = "$BASE_URL/get-election-stations/"
    $responseFile = Join-Path $TMP_DIR ("stations_response_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $data = "election_type=$ELECTION_TYPE&election_round=$ELECTION_ROUND&election_region=$REGION_ID&election_municipality=$MUNICIPALITY_ID"

    $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

    if ($httpCode -ne 200) {
        Write-Err "Greska pri ucitavanju birackih mesta (HTTP: $httpCode)"
        exit 1
    }

    $json = Get-Content $responseFile -Raw -Encoding UTF8 | ConvertFrom-Json

    $script:stationIds = @()
    $script:stationNames = @()

    if ($json.election_stations) {
        $json.election_stations.PSObject.Properties | ForEach-Object {
            $script:stationIds += $_.Name
            $script:stationNames += Convert-CyrillicToLatin $_.Value
        }
    }

    if ($stationIds.Count -eq 0) {
        Write-Err "Nema dostupnih birackih mesta za izabranu opstinu/grad."
        exit 1
    }

    Write-Success "Ucitano $($stationIds.Count) birackih mesta"
    Write-Host ""
}

# Step 6: Get results from all stations
function Get-AllResults {
    Show-Step 6 "Ucitavanje rezultata sa svih birackih mesta"
    Write-Info "Ucitavam rezultate glasanja sa svih birackih mesta..."
    Write-Host ""

    $totalStations = $stationIds.Count
    $url = "$BASE_URL/get_results/"

    $safeRegionName = $REGION_NAME -replace '[^a-zA-Z0-9]', '_'
    $safeMunicipalityName = $MUNICIPALITY_NAME -replace '[^a-zA-Z0-9]', '_'

    $combinedCsv = Join-Path $OUTPUT_DIR "rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_${safeRegionName}_${safeMunicipalityName}.csv"
    $metadataCsv = Join-Path $OUTPUT_DIR "metadata_${ELECTION_TYPE}_${ELECTION_ROUND}_${safeRegionName}_${safeMunicipalityName}.csv"

    # Initialize CSV files with BOM for Excel compatibility
    [System.IO.File]::WriteAllText($combinedCsv, "`"Biracko mesto ID`",`"Biracko mesto`",`"Stranka/Lista`",`"Broj glasova`",`"Procenat`"`r`n", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($metadataCsv, "`"Biracko mesto ID`",`"Biracko mesto`",`"Upisanih biraca`",`"Glasalo`",`"Nevazecih`",`"Vazecih`"`r`n", [System.Text.Encoding]::UTF8)

    Write-Info "Ukupno birackih mesta: $totalStations"
    Write-Host ""

    for ($i = 0; $i -lt $totalStations; $i++) {
        $stationId = $stationIds[$i]
        $stationName = $stationNames[$i]

        $progress = "[{0}/{1}]" -f ($i + 1), $totalStations
        Write-Host "  $progress Ucitavam BM ID ${stationId}: $stationName..." -NoNewline

        $data = "type=$ELECTION_TYPE&election_round=$ELECTION_ROUND&region=$REGION_ID&municipality=$MUNICIPALITY_ID&election_station=$stationId&should_update_pies=1"
        $responseFile = Join-Path $TMP_DIR "results_${stationId}.json"

        $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

        if ($httpCode -ne 200) {
            Write-Host " GRESKA (HTTP: $httpCode)" -ForegroundColor Red
            continue
        }

        try {
            $json = Get-Content $responseFile -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Host " GRESKA (Nevazeci JSON)" -ForegroundColor Red
            continue
        }

        # Extract metadata
        $metadata = Get-ResultsMetadata -Json $json

        # Write metadata
        $metadataLine = "`"$stationId`",`"$stationName`",`"$($metadata.Registered)`",`"$($metadata.Voted)`",`"$($metadata.Invalid)`",`"$($metadata.Valid)`"`r`n"
        [System.IO.File]::AppendAllText($metadataCsv, $metadataLine, [System.Text.Encoding]::UTF8)

        # Parse party results
        $partyResults = Get-PartyResults -Json $json

        foreach ($party in $partyResults) {
            $partyLine = "`"$stationId`",`"$stationName`",`"$($party.Name)`",`"$($party.Votes)`",`"$($party.Percent)`"`r`n"
            [System.IO.File]::AppendAllText($combinedCsv, $partyLine, [System.Text.Encoding]::UTF8)
        }

        # Download PDFs
        $pdfCount = Get-PdfsFromResults -ResponseFile $responseFile -StationId $stationId -StationName $stationName

        if ($pdfCount -gt 0) {
            Write-Host " OK ($($partyResults.Count) stranaka/lista, $pdfCount PDF)" -ForegroundColor Green
        }
        else {
            Write-Host " OK ($($partyResults.Count) stranaka/lista)" -ForegroundColor Green
        }

        # Small delay
        Start-Sleep -Milliseconds 300
    }

    Write-Host ""
    $totalRecords = (Get-Content $combinedCsv | Measure-Object -Line).Lines - 1
    $totalPdfs = (Get-ChildItem -Path $PDF_DIR -Filter "*.pdf" -ErrorAction SilentlyContinue | Measure-Object).Count

    Write-Success "Zavrseno! Ukupno zapisa: $totalRecords"
    Write-Success "Kombinovani fajl rezultata: $combinedCsv"
    Write-Success "Metadata fajl: $metadataCsv"
    if ($totalPdfs -gt 0) {
        Write-Success "PDF zapisnici ($totalPdfs fajlova): $PDF_DIR"
    }
}

# Ask user for download option
function Get-DownloadOption {
    Write-Host ""
    Write-Host "Da li zelite da preuzmete rezultate za SVA biracka mesta u opstini/gradu?" -ForegroundColor White
    Write-Host "  [Y] Da - preuzmi rezultate za sva biracka mesta"
    Write-Host "  [N] Ne - izaberi pojedinacno biracko mesto"
    Write-Host ""

    $choice = Read-Host "Vas izbor (Y/n)"

    return ($choice -ne 'n' -and $choice -ne 'N')
}

# Choose single station
function Select-SingleStation {
    Write-Info "Odaberite biracko mesto:"
    Write-Host ""

    $selectedIndex = Select-FromMenu -Ids $stationIds -Names $stationNames

    $script:SELECTED_STATION_ID = $stationIds[$selectedIndex]
    $script:SELECTED_STATION_NAME = $stationNames[$selectedIndex]

    Write-Host ""
    Write-Success "Izabrano biracko mesto: [$SELECTED_STATION_ID] $SELECTED_STATION_NAME"
}

# Get results for single station
function Get-SingleStationResults {
    Show-Step 6 "Ucitavanje rezultata za izabrano biracko mesto"
    Write-Info "Ucitavam rezultate glasanja..."
    Write-Host ""

    $url = "$BASE_URL/get_results/"
    $safeStationName = $SELECTED_STATION_NAME -replace '[^a-zA-Z0-9]', '_'
    $stationCsv = Join-Path $OUTPUT_DIR "rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_${SELECTED_STATION_ID}_${safeStationName}.csv"
    $responseFile = Join-Path $TMP_DIR "results_${SELECTED_STATION_ID}.json"

    $data = "type=$ELECTION_TYPE&election_round=$ELECTION_ROUND&region=$REGION_ID&municipality=$MUNICIPALITY_ID&election_station=$SELECTED_STATION_ID&should_update_pies=1"

    Write-Host "  Ucitavam rezultate za BM $SELECTED_STATION_ID : $SELECTED_STATION_NAME..." -NoNewline

    $httpCode = Invoke-ApiRequest -Url $url -Body $data -OutputFile $responseFile

    if ($httpCode -ne 200) {
        Write-Host " GRESKA (HTTP: $httpCode)" -ForegroundColor Red
        exit 1
    }

    try {
        $json = Get-Content $responseFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Host " GRESKA (Nevazeci JSON)" -ForegroundColor Red
        exit 1
    }

    Write-Host " OK" -ForegroundColor Green

    # Extract and display metadata
    $metadata = Get-ResultsMetadata -Json $json

    Write-Host ""
    Write-Info "Podaci o birackom mestu:"
    Write-Host "  Upisanih biraca: $($metadata.Registered)"
    Write-Host "  Glasalo: $($metadata.Voted)"
    Write-Host "  Nevazecih: $($metadata.Invalid)"
    Write-Host "  Vazecih: $($metadata.Valid)"
    Write-Host ""

    # Write CSV with BOM
    [System.IO.File]::WriteAllText($stationCsv, "`"Stranka/Lista`",`"Broj glasova`",`"Procenat`"`r`n", [System.Text.Encoding]::UTF8)

    # Parse and write party results
    $partyResults = Get-PartyResults -Json $json

    foreach ($party in $partyResults) {
        $line = "`"$($party.Name)`",`"$($party.Votes)`",`"$($party.Percent)`"`r`n"
        [System.IO.File]::AppendAllText($stationCsv, $line, [System.Text.Encoding]::UTF8)
    }

    Write-Success "Ucitano $($partyResults.Count) stranaka/lista"
    Write-Success "Rezultati sacuvani u: $stationCsv"

    # Download PDFs
    Write-Info "Preuzimam PDF zapisnike..."
    $pdfCount = Get-PdfsFromResults -ResponseFile $responseFile -StationId $SELECTED_STATION_ID -StationName $SELECTED_STATION_NAME

    if ($pdfCount -gt 0) {
        Write-Success "Preuzeto $pdfCount PDF fajlova u: $PDF_DIR"
    }
    else {
        Write-Warn "Nema dostupnih PDF zapisnika za ovo biracko mesto"
    }
}

# Main execution
function Main {
    Clear-Host
    Show-Banner

    Write-Host "Ova skripta pomaze da se dobiju podaci"
    Write-Host "o izbornim rezultatima iz RIK-a."
    Write-Host ""

    Initialize-Directories

    Select-ElectionType
    Select-ElectionRound
    Select-Region
    Select-Municipality
    Get-ElectionStations

    $downloadAll = Get-DownloadOption

    if ($downloadAll) {
        Get-AllResults
    }
    else {
        Select-SingleStation
        Get-SingleStationResults
    }

    Write-Host ""
    Write-Info "Svi podaci su sacuvani u: $OUTPUT_DIR"
    Write-Host ""
    Write-Info "Takodje mozete pregledati sirove JSON odgovore u: $TMP_DIR"
}

# Run
Main