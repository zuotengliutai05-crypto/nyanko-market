# Market dashboard updater.
# Downloads prices (Yahoo Finance) and news headlines (RSS), then writes data.js next to this file.
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 misreads non-ASCII text without a BOM).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Get-Text([string]$url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    $bytes = $wc.DownloadData($url)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

$items = @(
    @{ id = 'n225';   symbol = '^N225' },
    @{ id = 'sp500';  symbol = '^GSPC' },
    @{ id = 'acwi';   symbol = 'ACWI' },
    @{ id = 'dow';    symbol = '^DJI' },
    @{ id = 'usdjpy'; symbol = 'USDJPY=X' },
    @{ id = 'eurjpy'; symbol = 'EURJPY=X' },
    @{ id = 'gold';   symbol = 'GC=F' },
    @{ id = 'btc';    symbol = 'BTC-JPY' }
)

$feeds = @(
    @{ source = 'nhk';   url = 'https://www.nhk.or.jp/rss/news/cat5.xml' },
    @{ source = 'yahoo'; url = 'https://news.yahoo.co.jp/rss/topics/business.xml' }
)

$epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
$series = [ordered]@{}
$errors = New-Object System.Collections.ArrayList

foreach ($it in $items) {
    try {
        $url = 'https://query1.finance.yahoo.com/v8/finance/chart/' + [uri]::EscapeDataString($it.symbol) + '?range=1y&interval=1d'
        $r = ((Get-Text $url) | ConvertFrom-Json).chart.result[0]
        $ts = $r.timestamp
        $cl = $r.indicators.quote[0].close
        $off = [int]$r.meta.gmtoffset
        $dates = New-Object System.Collections.ArrayList
        $closes = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $ts.Count; $i++) {
            if ($null -eq $cl[$i]) { continue }
            $d = $epoch.AddSeconds([double]$ts[$i] + $off).ToString('yyyy-MM-dd', $inv)
            $v = [math]::Round([double]$cl[$i], 3)
            if ($dates.Count -gt 0 -and $dates[$dates.Count - 1] -eq $d) {
                $closes[$closes.Count - 1] = $v
            } else {
                [void]$dates.Add($d)
                [void]$closes.Add($v)
            }
        }
        if ($dates.Count -lt 2) { throw 'not enough data' }
        $series[$it.id] = [ordered]@{
            symbol   = $it.symbol
            currency = [string]$r.meta.currency
            dates    = @($dates)
            closes   = @($closes)
        }
        Write-Host ('  OK   ' + $it.symbol + '  (' + $dates.Count + ' days)')
    } catch {
        [void]$errors.Add($it.id)
        Write-Host ('  FAIL ' + $it.symbol + '  ' + $_.Exception.Message)
    }
}

$news = New-Object System.Collections.ArrayList
foreach ($f in $feeds) {
    try {
        [xml]$x = Get-Text $f.url
        $count = 0
        foreach ($n in $x.SelectNodes('//channel/item')) {
            if ($count -ge 8) { break }
            $title = $n.SelectSingleNode('title').InnerText.Trim()
            $link = $n.SelectSingleNode('link').InnerText.Trim()
            $date = ''
            $pd = $n.SelectSingleNode('pubDate')
            if ($pd) {
                try { $date = [DateTimeOffset]::Parse($pd.InnerText, $inv).ToLocalTime().ToString('yyyy-MM-ddTHH:mm:sszzz', $inv) } catch { $date = '' }
            }
            if ($link -notmatch '^https?://') { continue }
            [void]$news.Add([ordered]@{ source = $f.source; title = $title; link = $link; date = $date })
            $count++
        }
        Write-Host ('  OK   news:' + $f.source + '  (' + $count + ' items)')
    } catch {
        [void]$errors.Add('news-' + $f.source)
        Write-Host ('  FAIL news:' + $f.source + '  ' + $_.Exception.Message)
    }
}

if ($series.Count -eq 0) {
    Write-Host 'No price data could be downloaded. data.js was NOT changed. Check the internet connection.'
    exit 1
}

$data = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz', $inv)
    series      = $series
    news        = @($news)
    errors      = @($errors)
}
$json = $data | ConvertTo-Json -Depth 6 -Compress
$out = Join-Path $here 'data.js'
$text = 'window.MARKET_DATA = ' + $json + ';'
$saved = $false
# Retry a few times: OneDrive can briefly lock files while syncing.
for ($try = 1; $try -le 5 -and -not $saved; $try++) {
    try {
        [System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding($false)))
        $saved = $true
    } catch {
        Write-Host ('  save failed (try ' + $try + '): ' + $_.Exception.Message)
        Start-Sleep -Seconds 2
    }
}
if (-not $saved) {
    Write-Host 'Could not save data.js.'
    exit 1
}
Write-Host ('Saved: ' + $out)
