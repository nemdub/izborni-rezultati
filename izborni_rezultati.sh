#!/bin/bash

# ============================================================================
# Izborni Rezultati - RIK
# ============================================================================
# Ova skripta koristi zvanični veb servis Republičke izborne komisije za
# učitavanje podataka o izbornim rezultatima:
# https://www.rik.parlament.gov.rs
#
# Skripta vodi korisnika kroz proces odabira tipa izbora, izbornog kruga,
# regiona, opštine i biračkih mesta, zatim učitava rezultate glasanja
# i snima ih u CSV fajlove.
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
BASE_URL="https://www.rik.parlament.gov.rs"
OUTPUT_DIR="./output"
TMP_DIR="./output/tmp"
PDF_DIR="./output/pdf"

# Common curl headers
USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36'

# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                   Izborni Rezultati - RIK                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print step header
print_step() {
    local step_num=$1
    local step_title=$2
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}Korak ${step_num}: ${step_title}${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Print info message
info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Print success message
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print warning message
warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print error message
error() {
    echo -e "${RED}✗${NC} $1"
}

# Convert Cyrillic to Latin characters
cyrillic_to_latin() {
    local text="$1"
    echo "$text" | sed \
        -e 's/А/A/g' -e 's/а/a/g' \
        -e 's/Б/B/g' -e 's/б/b/g' \
        -e 's/В/V/g' -e 's/в/v/g' \
        -e 's/Г/G/g' -e 's/г/g/g' \
        -e 's/Д/D/g' -e 's/д/d/g' \
        -e 's/Ђ/Đ/g' -e 's/ђ/đ/g' \
        -e 's/Е/E/g' -e 's/е/e/g' \
        -e 's/Ж/Ž/g' -e 's/ж/ž/g' \
        -e 's/З/Z/g' -e 's/з/z/g' \
        -e 's/И/I/g' -e 's/и/i/g' \
        -e 's/Ј/J/g' -e 's/ј/j/g' \
        -e 's/К/K/g' -e 's/к/k/g' \
        -e 's/Л/L/g' -e 's/л/l/g' \
        -e 's/Љ/Lj/g' -e 's/љ/lj/g' \
        -e 's/М/M/g' -e 's/м/m/g' \
        -e 's/Н/N/g' -e 's/н/n/g' \
        -e 's/Њ/Nj/g' -e 's/њ/nj/g' \
        -e 's/О/O/g' -e 's/о/o/g' \
        -e 's/П/P/g' -e 's/п/p/g' \
        -e 's/Р/R/g' -e 's/р/r/g' \
        -e 's/С/S/g' -e 's/с/s/g' \
        -e 's/Т/T/g' -e 's/т/t/g' \
        -e 's/Ћ/Ć/g' -e 's/ћ/ć/g' \
        -e 's/У/U/g' -e 's/у/u/g' \
        -e 's/Ф/F/g' -e 's/ф/f/g' \
        -e 's/Х/H/g' -e 's/х/h/g' \
        -e 's/Ц/C/g' -e 's/ц/c/g' \
        -e 's/Ч/Č/g' -e 's/ч/č/g' \
        -e 's/Џ/Dž/g' -e 's/џ/dž/g' \
        -e 's/Ш/Š/g' -e 's/ш/š/g'
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    for cmd in curl jq sed grep; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Nedostajući programi: ${missing_deps[*]}"
        echo ""
        echo "Molimo instalirajte ih na jedan od sledećih načina:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        echo "  macOS:         brew install ${missing_deps[*]}"
        echo "  Fedora:        sudo dnf install ${missing_deps[*]}"
        exit 1
    fi

    success "Svi neophodni programi su već instalirani"
}

# Create output directory
setup_directories() {
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TMP_DIR"
    mkdir -p "$PDF_DIR"
    success "Kreiran izlazni direktorijum: $OUTPUT_DIR"
}

# Extract and download PDF files from results JSON
# Usage: download_pdfs_from_results response_file station_id station_name
download_pdfs_from_results() {
    local response_file=$1
    local station_id=$2
    local station_name=$3

    # Extract minute_from_election_station field
    local minute_html
    minute_html=$(jq -r '.minute_from_election_station // ""' "$response_file" 2>/dev/null)

    if [[ -z "$minute_html" || "$minute_html" == "null" ]]; then
        return 0
    fi

    # Extract all PDF URLs from the HTML
    local pdf_urls
    pdf_urls=$(echo "$minute_html" | grep -oE "href='[^']*\.pdf'" | sed "s/href='//;s/'$//" || true)

    if [[ -z "$pdf_urls" ]]; then
        return 0
    fi

    local pdf_count=0
    local safe_station_name
    safe_station_name=$(echo "$station_name" | sed 's/[^a-zA-Z0-9а-яА-ЯčćžšđČĆŽŠĐ]/_/g')

    while IFS= read -r pdf_path; do
        if [[ -z "$pdf_path" ]]; then
            continue
        fi

        # Get filename from path
        local pdf_filename
        pdf_filename=$(basename "$pdf_path")

        # Create unique filename with station ID
        local output_pdf="${PDF_DIR}/${station_id}_${pdf_filename}"

        # Download the PDF
        local full_url="${BASE_URL}${pdf_path}"

        curl -s \
            -H "Referer: ${BASE_URL}/" \
            -H "User-Agent: ${USER_AGENT}" \
            -o "$output_pdf" \
            "$full_url"

        if [[ -f "$output_pdf" && -s "$output_pdf" ]]; then
            ((pdf_count++))
        fi
    done <<< "$pdf_urls"

    echo "$pdf_count"
}

# Make API request with common headers
api_request() {
    local url=$1
    local data=$2
    local output_file=$3

    curl -s -w "%{http_code}" \
        -X POST \
        -H "Referer: ${BASE_URL}/" \
        -H "User-Agent: ${USER_AGENT}" \
        -H "Origin: ${BASE_URL}" \
        -H "Accept: application/json, text/javascript, */*; q=0.01" \
        -H "Accept-Encoding: gzip, deflate, br, zstd" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "Sec-Fetch-Site: same-origin" \
        -H "Sec-Fetch-Mode: cors" \
        -H "Sec-Fetch-Dest: empty" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=utf-8" \
        -d "$data" \
        --compressed \
        -o "$output_file" \
        "${url}"
}

# Interactive arrow-key menu selector with scrolling viewport
# Usage: select_from_menu ids_array_name names_array_name
# Returns: Sets MENU_SELECTED_INDEX to the chosen index
select_from_menu() {
    local ids_name=$1
    local names_name=$2

    # Copy arrays using eval (compatible with bash 3.x)
    eval "menu_ids=(\"\${${ids_name}[@]}\")"
    eval "menu_names=(\"\${${names_name}[@]}\")"

    local total=${#menu_ids[@]}
    local selected=0
    local viewport_size=15
    local viewport_start=0
    local key
    local i
    local display_count

    # Adjust viewport size if total items is smaller
    if [[ $total -lt $viewport_size ]]; then
        viewport_size=$total
    fi
    display_count=$viewport_size

    info "Koristite strelice GORE/DOLE za navigaciju, ENTER za potvrdu izbora"
    echo ""

    # Hide cursor
    tput civis 2>/dev/null || true

    # Draw menu with scrolling viewport
    _draw_menu() {
        local redraw=$1
        local clear_line

        # Get clear-to-end-of-line sequence
        clear_line=$(tput el 2>/dev/null || printf "\033[K")

        # Adjust viewport to keep selected item visible
        if [[ $selected -lt $viewport_start ]]; then
            viewport_start=$selected
        elif [[ $selected -ge $((viewport_start + viewport_size)) ]]; then
            viewport_start=$((selected - viewport_size + 1))
        fi

        # Calculate how many lines to draw
        display_count=$viewport_size
        if [[ $((viewport_start + viewport_size)) -gt $total ]]; then
            display_count=$((total - viewport_start))
        fi

        # Move cursor up to redraw
        if [[ $redraw -eq 1 ]]; then
            tput cuu $((viewport_size + 2)) 2>/dev/null || printf "\033[%dA" $((viewport_size + 2))
        fi

        # Show scroll indicator at top
        if [[ $viewport_start -gt 0 ]]; then
            printf "%s${CYAN}  ▲ još %d iznad${NC}\n" "$clear_line" "$viewport_start"
        else
            printf "%s\n" "$clear_line"
        fi

        # Draw visible items
        for ((i=viewport_start; i<viewport_start+viewport_size && i<total; i++)); do
            if [[ $i -eq $selected ]]; then
                printf "%s${GREEN}> [%s] %s${NC}\n" "$clear_line" "${menu_ids[$i]}" "${menu_names[$i]}"
            else
                printf "%s  [%s] %s\n" "$clear_line" "${menu_ids[$i]}" "${menu_names[$i]}"
            fi
        done

        # Pad with empty lines if needed
        for ((i=display_count; i<viewport_size; i++)); do
            printf "%s\n" "$clear_line"
        done

        # Show scroll indicator at bottom
        local remaining=$((total - viewport_start - viewport_size))
        if [[ $remaining -gt 0 ]]; then
            printf "%s${CYAN}  ▼ još %d ispod${NC}\n" "$clear_line" "$remaining"
        else
            printf "%s\n" "$clear_line"
        fi
    }

    _draw_menu 0

    while true; do
        IFS= read -rsn1 key

        if [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 1 key
            case "$key" in
                '[A') ((selected > 0)) && ((selected--)) ;;
                '[B') ((selected < total - 1)) && ((selected++)) ;;
            esac
            _draw_menu 1
        elif [[ $key == "" ]]; then
            break
        fi
    done

    tput cnorm 2>/dev/null || true

    MENU_SELECTED_INDEX=$selected
}

# Step 1: Choose election type
choose_election_type() {
    print_step 1 "Odabir tipa izbora"
    info "Odaberite tip izbora:"
    echo ""

    local type_ids=(2 3 7)
    local type_names=(
        "Parlamentarni"
        "Lokalni"
        "Pokrajinski"
    )

    select_from_menu type_ids type_names

    ELECTION_TYPE="${type_ids[$MENU_SELECTED_INDEX]}"
    ELECTION_TYPE_NAME="${type_names[$MENU_SELECTED_INDEX]}"
    export ELECTION_TYPE ELECTION_TYPE_NAME

    echo ""
    success "Izabran tip izbora: [${ELECTION_TYPE}] ${ELECTION_TYPE_NAME}"
}

# Step 2: Choose election round
choose_election_round() {
    print_step 2 "Odabir izbornog kruga"
    info "Učitavam dostupne izborne krugove..."
    echo ""

    local url="${BASE_URL}/get-elections/"
    local response_file="${TMP_DIR}/elections_response_$(date +%Y%m%d_%H%M%S).json"
    local data="election_type=${ELECTION_TYPE}"

    local http_code
    http_code=$(api_request "$url" "$data" "$response_file")

    if [[ "$http_code" != "200" ]]; then
        error "Greška pri učitavanju izbornih krugova (HTTP: $http_code)"
        exit 1
    fi

    # Parse JSON response - handle multiple response formats
    election_round_ids=()
    election_round_names=()

    # Check response structure type
    local has_rounds has_data is_array
    has_rounds=$(jq 'has("rounds")' "$response_file" 2>/dev/null || echo "false")

    if [[ "$has_rounds" == "true" ]]; then
        # Handle {"rounds": {"id1": "name1", "id2": "name2"}} format
        while IFS= read -r line; do
            election_round_ids+=("$line")
        done < <(jq -r '.rounds | keys[]' "$response_file" 2>/dev/null)

        while IFS= read -r id; do
            local name
            name=$(jq -r --arg id "$id" '.rounds[$id]' "$response_file" 2>/dev/null)
            # Convert Cyrillic to Latin
            name=$(cyrillic_to_latin "$name")
            election_round_names+=("$name")
        done < <(jq -r '.rounds | keys[]' "$response_file" 2>/dev/null)
    fi

    local total=${#election_round_ids[@]}

    if [[ $total -eq 0 ]]; then
        error "Nema dostupnih izbornih krugova za izabrani tip izbora."
        warn "Proverite sadržaj odgovora: $response_file"
        exit 1
    fi

    success "Učitano $total izbornih krugova"
    echo ""
    info "Odaberite izborni krug:"
    echo ""

    select_from_menu election_round_ids election_round_names

    ELECTION_ROUND="${election_round_ids[$MENU_SELECTED_INDEX]}"
    ELECTION_ROUND_NAME="${election_round_names[$MENU_SELECTED_INDEX]}"
    export ELECTION_ROUND ELECTION_ROUND_NAME

    echo ""
    success "Izabran izborni krug: [${ELECTION_ROUND}] ${ELECTION_ROUND_NAME}"
}

# Step 3: Choose region
choose_region() {
    print_step 3 "Odabir regiona"
    info "Učitavam dostupne regione..."
    echo ""

    local url="${BASE_URL}/get-regions/"
    local response_file="${TMP_DIR}/regions_response_$(date +%Y%m%d_%H%M%S).json"
    local data="election_type=${ELECTION_TYPE}&election_round=${ELECTION_ROUND}"

    local http_code
    http_code=$(api_request "$url" "$data" "$response_file")

    if [[ "$http_code" != "200" ]]; then
        error "Greška pri učitavanju regiona (HTTP: $http_code)"
        exit 1
    fi

    # Parse JSON response - handle multiple response formats
    region_ids=()
    region_names=()

    # Check response structure type
    local has_regions has_data is_array
    has_regions=$(jq 'has("regions")' "$response_file" 2>/dev/null || echo "false")

    if [[ "$has_regions" == "true" ]]; then
        # Handle {"regions": {"id1": "name1", "id2": "name2"}} format
        while IFS= read -r line; do
            region_ids+=("$line")
        done < <(jq -r '.regions | keys[]' "$response_file" 2>/dev/null)

        while IFS= read -r id; do
            local name
            name=$(jq -r --arg id "$id" '.regions[$id]' "$response_file" 2>/dev/null)
            # Convert Cyrillic to Latin
            name=$(cyrillic_to_latin "$name")
            region_names+=("$name")
        done < <(jq -r '.regions | keys[]' "$response_file" 2>/dev/null)
    fi

    local total=${#region_ids[@]}

    if [[ $total -eq 0 ]]; then
        error "Nema dostupnih regiona za izabrani izborni krug."
        warn "Proverite sadržaj odgovora: $response_file"
        exit 1
    fi

    success "Učitano $total regiona"
    echo ""
    info "Odaberite region:"
    echo ""

    select_from_menu region_ids region_names

    REGION_ID="${region_ids[$MENU_SELECTED_INDEX]}"
    REGION_NAME="${region_names[$MENU_SELECTED_INDEX]}"
    export REGION_ID REGION_NAME

    echo ""
    success "Izabran region: [${REGION_ID}] ${REGION_NAME}"
}

# Step 4: Choose municipality
choose_municipality() {
    print_step 4 "Odabir opštine / grada"
    info "Učitavam dostupne opštine/gradove..."
    echo ""

    local url="${BASE_URL}/get-municipalities/"
    local response_file="${TMP_DIR}/municipalities_response_$(date +%Y%m%d_%H%M%S).json"
    local data="election_type=${ELECTION_TYPE}&election_round=${ELECTION_ROUND}&election_region=${REGION_ID}"

    local http_code
    http_code=$(api_request "$url" "$data" "$response_file")

    if [[ "$http_code" != "200" ]]; then
        error "Greška pri učitavanju opština/gradova (HTTP: $http_code)"
        exit 1
    fi

    # Parse response - handle multiple formats (JSON or HTML options)
    municipality_ids=()
    municipality_names=()

    # Handle HTML <option> format: <option data-id="80012" value="26">Ада</option>
    # Extract value attribute as ID
    while IFS= read -r line; do
        municipality_ids+=("$line")
    done < <(grep -oE 'value="[^"]*"' "$response_file" | sed 's/value="//;s/"//')

    # Extract text content between > and </option>
    while IFS= read -r line; do
        line=$(cyrillic_to_latin "$line")
        municipality_names+=("$line")
    done < <(grep -oE '>[^<]+</option>' "$response_file" | sed 's/>//;s/<\/option>//')

    local total=${#municipality_ids[@]}

    if [[ $total -eq 0 ]]; then
        error "Nema dostupnih opština/gradova za izabrani region."
        warn "Proverite sadržaj odgovora: $response_file"
        exit 1
    fi

    success "Učitano $total opština/gradova"
    echo ""
    info "Odaberite opštinu/grad:"
    echo ""

    select_from_menu municipality_ids municipality_names

    MUNICIPALITY_ID="${municipality_ids[$MENU_SELECTED_INDEX]}"
    MUNICIPALITY_NAME="${municipality_names[$MENU_SELECTED_INDEX]}"
    export MUNICIPALITY_ID MUNICIPALITY_NAME

    echo ""
    success "Izabrana opština/grad: [${MUNICIPALITY_ID}] ${MUNICIPALITY_NAME}"
}

# Step 5: Get election stations
get_election_stations() {
    print_step 5 "Učitavanje biračkih mesta"
    info "Učitavam dostupna biračka mesta..."
    echo ""

    local url="${BASE_URL}/get-election-stations/"
    local response_file="${TMP_DIR}/stations_response_$(date +%Y%m%d_%H%M%S).json"
    local data="election_type=${ELECTION_TYPE}&election_round=${ELECTION_ROUND}&election_region=${REGION_ID}&election_municipality=${MUNICIPALITY_ID}"

    local http_code
    http_code=$(api_request "$url" "$data" "$response_file")

    if [[ "$http_code" != "200" ]]; then
        error "Greška pri učitavanju biračkih mesta (HTTP: $http_code)"
        exit 1
    fi

    # Parse JSON response - handle multiple response formats
    station_ids=()
    station_names=()

    # Check response structure type
    local has_election_stations has_data is_array
    has_election_stations=$(jq 'has("election_stations")' "$response_file" 2>/dev/null || echo "false")

    if [[ "$has_election_stations" == "true" ]]; then
        # Handle {"election_stations": {"id1": "name1", "id2": "name2"}} format
        while IFS= read -r line; do
            station_ids+=("$line")
        done < <(jq -r '.election_stations | keys[]' "$response_file" 2>/dev/null)

        while IFS= read -r id; do
            local name
            name=$(jq -r --arg id "$id" '.election_stations[$id]' "$response_file" 2>/dev/null)
            # Convert Cyrillic to Latin
            name=$(cyrillic_to_latin "$name")
            station_names+=("$name")
        done < <(jq -r '.election_stations | keys[]' "$response_file" 2>/dev/null)
    fi

    local total=${#station_ids[@]}

    if [[ $total -eq 0 ]]; then
        error "Nema dostupnih biračkih mesta za izabranu opštinu/grad."
        warn "Proverite sadržaj odgovora: $response_file"
        exit 1
    fi

    success "Učitano $total biračkih mesta"
    echo ""
}

# Extract metadata from results JSON response
# Usage: extract_results_metadata response_file
# Sets global variables: RESULT_REGISTERED, RESULT_VOTED, RESULT_INVALID, RESULT_VALID
extract_results_metadata() {
    local response_file=$1

    # Try new format first (stat_sum_numbers), then fall back to old format
    if jq -e '.stat_sum_numbers' "$response_file" >/dev/null 2>&1; then
        RESULT_REGISTERED=$(jq -r '.stat_sum_numbers.total_voters // "N/A"' "$response_file" 2>/dev/null)
        RESULT_VOTED=$(jq -r '.stat_sum_numbers.available // "N/A"' "$response_file" 2>/dev/null)
        # Extract valid/invalid from sum_config pie chart data
        RESULT_VALID=$(jq -r '.sum_config.data.datasets[0].data[0] // "N/A"' "$response_file" 2>/dev/null)
        RESULT_INVALID=$(jq -r '.sum_config.data.datasets[0].data[1] // "N/A"' "$response_file" 2>/dev/null)
    else
        RESULT_REGISTERED=$(jq -r '.upisanih // .registered // .total_voters // "N/A"' "$response_file" 2>/dev/null)
        RESULT_VOTED=$(jq -r '.glasalo // .voted // .turnout // "N/A"' "$response_file" 2>/dev/null)
        RESULT_INVALID=$(jq -r '.nevazecih // .invalid // "N/A"' "$response_file" 2>/dev/null)
        RESULT_VALID=$(jq -r '.vazecih // .valid // "N/A"' "$response_file" 2>/dev/null)
    fi
}

# Parse party results from JSON and write to CSV
# Usage: parse_party_results response_file output_csv
# Returns: party count via RESULT_PARTY_COUNT global variable
parse_party_results() {
    local response_file=$1
    local output_csv=$2

    RESULT_PARTY_COUNT=0

    # Try new format first (table_data), then fall back to old formats
    if jq -e '.table_data' "$response_file" >/dev/null 2>&1; then
        # New format: table_data array with list_name, won_number, won_percent
        while IFS= read -r line; do
            local list_name won_number won_percent
            list_name=$(echo "$line" | jq -r '.list_name')
            list_name=$(cyrillic_to_latin "$list_name")
            won_number=$(echo "$line" | jq -r '.won_number')
            won_percent=$(echo "$line" | jq -r '.won_percent')
            echo "\"$list_name\",\"$won_number\",\"$won_percent\"" >> "$output_csv"
        done < <(jq -c '.table_data[]' "$response_file" 2>/dev/null)
        RESULT_PARTY_COUNT=$(jq '.table_data | length' "$response_file" 2>/dev/null || echo 0)
    elif jq -e '.results' "$response_file" >/dev/null 2>&1; then
        jq -r '.results[] | [(.party_name // .name // .naziv), (.votes // .glasovi // 0), (.percentage // .procenat // "0")] | @csv' "$response_file" >> "$output_csv" 2>/dev/null
        RESULT_PARTY_COUNT=$(jq '.results | length' "$response_file" 2>/dev/null || echo 0)
    elif jq -e '.data' "$response_file" >/dev/null 2>&1; then
        jq -r '.data[] | [(.party_name // .name // .naziv), (.votes // .glasovi // 0), (.percentage // .procenat // "0")] | @csv' "$response_file" >> "$output_csv" 2>/dev/null
        RESULT_PARTY_COUNT=$(jq '.data | length' "$response_file" 2>/dev/null || echo 0)
    elif jq -e '.parties' "$response_file" >/dev/null 2>&1; then
        jq -r '.parties[] | [(.party_name // .name // .naziv), (.votes // .glasovi // 0), (.percentage // .procenat // "0")] | @csv' "$response_file" >> "$output_csv" 2>/dev/null
        RESULT_PARTY_COUNT=$(jq '.parties | length' "$response_file" 2>/dev/null || echo 0)
    elif jq -e 'if type == "array" then true else false end' "$response_file" >/dev/null 2>&1; then
        jq -r '.[] | [(.party_name // .name // .naziv), (.votes // .glasovi // 0), (.percentage // .procenat // "0")] | @csv' "$response_file" >> "$output_csv" 2>/dev/null
        RESULT_PARTY_COUNT=$(jq 'length' "$response_file" 2>/dev/null || echo 0)
    fi
}

# Step 6: Get results from all stations
get_results() {
    print_step 6 "Učitavanje rezultata sa svih biračkih mesta"
    info "Učitavam rezultate glasanja sa svih biračkih mesta..."
    echo ""

    local total_stations=${#station_ids[@]}
    local url="${BASE_URL}/get_results/"

    # Create safe filename from names
    local safe_region_name=$(echo "$REGION_NAME" | sed 's/[^a-zA-Z0-9а-яА-ЯčćžšđČĆŽŠĐ]/_/g')
    local safe_municipality_name=$(echo "$MUNICIPALITY_NAME" | sed 's/[^a-zA-Z0-9а-яА-ЯčćžšđČĆŽŠĐ]/_/g')

    local combined_csv="${OUTPUT_DIR}/rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_${safe_region_name}_${safe_municipality_name}.csv"
    local metadata_csv="${OUTPUT_DIR}/metadata_${ELECTION_TYPE}_${ELECTION_ROUND}_${safe_region_name}_${safe_municipality_name}.csv"
    local i

    # Initialize combined CSV with header
    echo "Biračko mesto ID,Biračko mesto,Stranka/Lista,Broj glasova,Procenat" > "$combined_csv"

    # Initialize metadata CSV with header (for station-level data like total voters, turnout, etc.)
    echo "Biračko mesto ID,Biračko mesto,Upisanih birača,Glasalo,Nevažećih,Važećih" > "$metadata_csv"

    info "Ukupno biračkih mesta: $total_stations"
    echo ""

    for ((i=0; i<total_stations; i++)); do
        local station_id="${station_ids[$i]}"
        local station_name="${station_names[$i]}"

        printf "  [%d/%d] Učitavam BM ID %s: %s..." "$((i+1))" "$total_stations" "$station_id" "$station_name"

        # Fetch results from API
        local data="type=${ELECTION_TYPE}&election_round=${ELECTION_ROUND}&region=${REGION_ID}&municipality=${MUNICIPALITY_ID}&election_station=${station_id}&should_update_pies=1"
        local response_file="${TMP_DIR}/results_${station_id}.json"
        local station_csv="${OUTPUT_DIR}/rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_${station_id}.csv"

        local http_code
        http_code=$(api_request "$url" "$data" "$response_file")

        if [[ "$http_code" != "200" ]]; then
            echo -e " ${RED}GREŠKA (HTTP: $http_code)${NC}"
            continue
        fi

        # Check if response is valid JSON
        if ! jq empty "$response_file" 2>/dev/null; then
            echo -e " ${RED}GREŠKA (Nevažeći JSON)${NC}"
            continue
        fi

        # Extract metadata using helper function
        extract_results_metadata "$response_file"

        # Write metadata
        echo "\"$station_id\",\"$station_name\",\"$RESULT_REGISTERED\",\"$RESULT_VOTED\",\"$RESULT_INVALID\",\"$RESULT_VALID\"" >> "$metadata_csv"

        # Write individual station CSV header
        echo "Stranka/Lista,Broj glasova,Procenat" > "$station_csv"

        # Parse party results using helper function
        parse_party_results "$response_file" "$station_csv"

        # Append to combined CSV with station info
        tail -n +2 "$station_csv" 2>/dev/null | while IFS= read -r line; do
            echo "\"$station_id\",\"$station_name\",$line" >> "$combined_csv"
        done

        # Download PDFs from this station
        local pdf_downloaded
        pdf_downloaded=$(download_pdfs_from_results "$response_file" "$station_id" "$station_name")

        if [[ "$pdf_downloaded" -gt 0 ]]; then
            echo -e " ${GREEN}OK${NC} ($RESULT_PARTY_COUNT stranaka/lista, $pdf_downloaded PDF)"
        else
            echo -e " ${GREEN}OK${NC} ($RESULT_PARTY_COUNT stranaka/lista)"
        fi

        # Small delay to avoid overwhelming the server
        sleep 0.3
    done

    echo ""
    local total_records
    total_records=$(($(wc -l < "$combined_csv") - 1))
    local total_pdfs
    total_pdfs=$(find "${PDF_DIR}" -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
    success "Završeno! Ukupno zapisa: $total_records"
    success "Kombinovani fajl rezultata: $combined_csv"
    success "Metadata fajl: $metadata_csv"
    success "Pojedinačni fajlovi: ${OUTPUT_DIR}/rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_*.csv"
    if [[ "$total_pdfs" -gt 0 ]]; then
        success "PDF zapisnici ($total_pdfs fajlova): ${PDF_DIR}/"
    fi
}

# Option: Download all results for all stations in municipality
download_all_option() {
    echo ""
    echo -e "${BOLD}Da li želite da preuzmete rezultate za SVA biračka mesta u opštini/gradu?${NC}"
    echo "  [Y] Da - preuzmi rezultate za sva biračka mesta"
    echo "  [n] Ne - izaberi pojedinačno biračko mesto"
    echo ""
    read -r -n 1 choice
    echo ""

    case "$choice" in
        [nN])
            DOWNLOAD_ALL=0
            ;;
        *)
            DOWNLOAD_ALL=1
            ;;
    esac

    export DOWNLOAD_ALL
}

# Step 5b: Choose single station (if not downloading all)
choose_single_station() {
    info "Odaberite biračko mesto:"
    echo ""

    select_from_menu station_ids station_names

    SELECTED_STATION_ID="${station_ids[$MENU_SELECTED_INDEX]}"
    SELECTED_STATION_NAME="${station_names[$MENU_SELECTED_INDEX]}"
    export SELECTED_STATION_ID SELECTED_STATION_NAME

    echo ""
    success "Izabrano biračko mesto: [${SELECTED_STATION_ID}] ${SELECTED_STATION_NAME}"
}

# Get results for single station
get_single_station_results() {
    print_step 6 "Učitavanje rezultata za izabrano biračko mesto"
    info "Učitavam rezultate glasanja..."
    echo ""

    local url="${BASE_URL}/get_results/"
    local safe_station_name=$(echo "$SELECTED_STATION_NAME" | sed 's/[^a-zA-Z0-9а-яА-ЯčćžšđČĆŽŠĐ]/_/g')
    local station_csv="${OUTPUT_DIR}/rezultati_${ELECTION_TYPE}_${ELECTION_ROUND}_${SELECTED_STATION_ID}_${safe_station_name}.csv"
    local response_file="${TMP_DIR}/results_${SELECTED_STATION_ID}.json"

    local data="type=${ELECTION_TYPE}&election_round=${ELECTION_ROUND}&region=${REGION_ID}&municipality=${MUNICIPALITY_ID}&election_station=${SELECTED_STATION_ID}&should_update_pies=1"

    printf "  Učitavam rezultate za BM %s: %s..." "$SELECTED_STATION_ID" "$SELECTED_STATION_NAME"

    local http_code
    http_code=$(api_request "$url" "$data" "$response_file")

    if [[ "$http_code" != "200" ]]; then
        echo -e " ${RED}GREŠKA (HTTP: $http_code)${NC}"
        exit 1
    fi

    # Check if response is valid JSON
    if ! jq empty "$response_file" 2>/dev/null; then
        echo -e " ${RED}GREŠKA (Nevažeći JSON)${NC}"
        exit 1
    fi

    # Extract metadata using helper function
    extract_results_metadata "$response_file"

    # Display metadata
    echo ""
    echo ""
    info "Podaci o biračkom mestu:"
    echo "  Upisanih birača: $RESULT_REGISTERED"
    echo "  Glasalo: $RESULT_VOTED"
    echo "  Nevažećih: $RESULT_INVALID"
    echo "  Važećih: $RESULT_VALID"
    echo ""

    # Write CSV header
    echo "Stranka/Lista,Broj glasova,Procenat" > "$station_csv"

    # Parse party results using helper function
    parse_party_results "$response_file" "$station_csv"

    success "Učitano $RESULT_PARTY_COUNT stranaka/lista"
    success "Rezultati sačuvani u: $station_csv"

    # Download PDFs from this station
    info "Preuzimam PDF zapisnike..."
    local pdf_downloaded
    pdf_downloaded=$(download_pdfs_from_results "$response_file" "$SELECTED_STATION_ID" "$SELECTED_STATION_NAME")

    if [[ "$pdf_downloaded" -gt 0 ]]; then
        success "Preuzeto $pdf_downloaded PDF fajlova u: ${PDF_DIR}/"
    else
        warn "Nema dostupnih PDF zapisnika za ovo biračko mesto"
    fi
}

# Cleanup function
cleanup() {
    echo ""
    warn "Skripta je prekinuta..."
    tput cnorm 2>/dev/null || true
    exit 1
}

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM

# Main execution
main() {
    clear
    print_banner

    echo "Ova skripta pomaže da se dobiju podaci"
    echo "o izbornim rezultatima iz RIK-a."
    echo ""

    # Check dependencies
    check_dependencies
    setup_directories

    # Main flow
    choose_election_type
    choose_election_round
    choose_region
    choose_municipality
    get_election_stations

    # Ask user if they want all stations or single
    download_all_option

    if [[ "$DOWNLOAD_ALL" -eq 1 ]]; then
        get_results
    else
        choose_single_station
        get_single_station_results
    fi

    echo ""
    info "Svi podaci su sačuvani u: $OUTPUT_DIR"
    echo ""
    info "Takođe možete pregledati sirove JSON odgovore u: $TMP_DIR"
}

# Run main function
main "$@"
