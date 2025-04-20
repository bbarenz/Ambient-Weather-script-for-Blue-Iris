 # === Configuration ===
$ApiKey = 'e05b8c2fa67045d4a7686fb44a8032fd0b4958bf19664644a0608aa8f03ef2a5'
$AppKey = 'c80c52ef168346d996990050c7f350f0cb1b640dd26e4374b6fdcc13843cc9ea'
$OutFile = 'C:\BlueIris\weather\fullwx.txt'
$UseCelsius = $false       # Set to $true for °C
$UseCardinal = 2           # 0 = degrees only, 1 = cardinal only, 2 = both

$uri = "https://api.ambientweather.net/v1/devices?" +
       "applicationKey=$AppKey&apiKey=$ApiKey&limit=1"

function ToC($f) { return [math]::Round((($f - 32) * 5 / 9), 1) }
function R1($v) { return [math]::Round($v, 1) }

function Get-CardinalDirection($deg) {
    $dirs = @('N  ','NE ','E  ','SE ','S  ','SW ','W  ','NW ')
    $i = [math]::Round(($deg % 360) / 45) % 8
    return $dirs[$i]
}

try {
    $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 10
    if (-not $resp) { throw "Empty response" }

    $data = $resp[0].lastData

    # === STEP 1: Create fullwx.txt ===
    $lines = ($data | Get-Member -MemberType NoteProperty).Name |
             Sort-Object |
             ForEach-Object { "$_=$($data.$_)" }

    $tmp = [IO.Path]::GetTempFileName()
    $lines | Set-Content -Path $tmp -Encoding UTF8
    Move-Item $tmp $OutFile -Force

    # === STEP 2: Create userwx.txt ===
    $userOutFile = [System.IO.Path]::Combine((Split-Path $OutFile), 'userwx.txt')
    $raw = @{}
    Get-Content $OutFile | ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) { $raw[$parts[0]] = $parts[1] }
    }

    $fieldMap = @(
      #  @{ Key = 'tempinf';        Label = 'Inside Temp';        Suffix = '°F' },  # Indoor temperature
      #  @{ Key = 'feelsLikein';    Label = 'Feels Like In';      Suffix = '°F' },  # Perceived indoor temp
        @{ Key = 'tempf';          Label = 'Outside Temp';       Suffix = '°F' },  # Outdoor temperature
        @{ Key = 'feelsLike';      Label = 'Feels Like Out';     Suffix = '°F' },  # Heat Index or Wind Chill
      #  @{ Key = 'humidityin';     Label = 'Humidity In';        Suffix = '%' },   # Indoor humidity
        @{ Key = 'humidity';       Label = 'Humidity Out';       Suffix = '%' },   # Outdoor humidity
      #  @{ Key = 'dewPointin';     Label = 'Dew Point In';       Suffix = '°F' },  # Indoor dew point
      #  @{ Key = 'dewPoint';       Label = 'Dew Point Out';      Suffix = '°F' },  # Outdoor dew point
        @{ Key = 'windspeedmph';   Label = 'Wind Speed';         Suffix = 'mph' }, # Wind speed
        @{ Key = 'windgustmph';    Label = 'Wind Gust';          Suffix = 'mph' }, # Wind gust
        @{ Key = 'winddir';        Label = 'Wind Direction';     Suffix = '°' },   # Wind direction
      #  @{ Key = 'lightning_distance'; Label = 'Lightning Distance'; Suffix = 'mi' }, # Nearest lightning
       @{ Key = 'dailyrainin';    Label = 'Daily Rain';         Suffix = 'in' },  # Rainfall today
	  #  @{ Key = 'eventrainin';    Label = 'Event Rain';         Suffix = 'in' },  # Rainfall Event	  
      #  @{ Key = 'solarradiation'; Label = 'Solar Radiation';    Suffix = 'W/m²' },# Solar radiation
      #  @{ Key = 'uv';             Label = 'UV Index';           Suffix = '' },    # UV Index
      #  @{ Key = 'pm25_in';        Label = 'Indoor PM2.5';       Suffix = 'µg/m³' },# Indoor air quality
      #  @{ Key = 'pm25';           Label = 'Outdoor Air Quality';      Suffix = 'µg/m³' },# Outdoor air quality
      #  @{ Key = 'aqi_pm25_in';    Label = 'Indoor AQI';         Suffix = '' },    # Indoor Air quality Index
        @{ Key = 'aqi_pm25';       Label = 'Outdoor AQI';        Suffix = '' }    # Outdoor Air quality Index
      #  @{ Key = 'battin';         Label = 'Indoor Battery';     Suffix = '' },    # Indoor battery
      #  @{ Key = 'battout';        Label = 'Outdoor Battery';    Suffix = '' },    # Outdoor battery
      #  @{ Key = 'batt_lightning'; Label = 'Lightning Battery';  Suffix = '' },    # Lightning sensor battery
      #  @{ Key = 'battrain';       Label = 'Rain Gauge Battery'; Suffix = '' },    # Rain gauge battery
      #  @{ Key = 'batt_25';        Label = 'PM2.5 Battery';      Suffix = '' },    # PM2.5 sensor battery
      #  @{ Key = 'batt_25in';      Label = 'Indoor PM2.5 Batt';  Suffix = '' },    # Indoor PM2.5 battery
      #  @{ Key = 'date';           Label = 'Timestamp';          Suffix = '' }     # Sample timestamp
    )

    $output = @()

    foreach ($field in $fieldMap) {
        if ($raw.ContainsKey($field.Key)) {
            $value = $raw[$field.Key]

            # Special handling for wind direction
            if ($field.Key -eq 'winddir') {
                $deg = R1($value)
                $card = Get-CardinalDirection($deg)

                switch ($UseCardinal) {
                    0 { $value = "$deg°" }
                    1 { $value = "$card" }
                    2 { $value = "$card$deg°" }
                    default { $value = "$deg°" }
                }

                $output += "$($field.Label): $value"
                continue
            }

            # Numeric rounding & Celsius conversion
            if ($value -match '^\d+(\.\d+)?$') {
                $value = R1($value)
                if ($UseCelsius -and $field.Suffix -eq '°F') {
                    $value = ToC($value)
                    $field.Suffix = '°C'
                }
            }

            $output += "$($field.Label): $value$($field.Suffix)"
        }
    }

    # === Battery check ===
    $batteryKeys = @(
        'battin', 'battout', 'batt_lightning', 'battrain', 'batt_25', 'batt_25in'
    )

    $lowCount = 0
    foreach ($key in $batteryKeys) {
        if ($raw.ContainsKey($key)) {
            if ($raw[$key] -eq '1') { $lowCount++ }  # 1 = LOW
        }
    }

    $battOverall = if ($lowCount -gt 0) { 'CHECK' } else { 'OK' }
    $output += "Batteries: $battOverall"

    $tmpUser = [IO.Path]::GetTempFileName()
    $output | Set-Content -Path $tmpUser -Encoding UTF8
    Move-Item $tmpUser $userOutFile -Force
}
catch {
    Write-Warning "Ambient fetch failed: $_"
}
