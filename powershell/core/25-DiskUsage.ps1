# Directory Disk Usage (High-Speed Multi-Threaded Robocopy Engine)
function dirsize {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = ".",
        [Parameter(Position = 1)]
        [int]$Top = 0
    )

    $targetPath = $Path
    if ($Path -match '^[0-9]+$' -and $Top -eq 0) {
        $Top = [int]$Path
        $targetPath = "."
    }

    $targetDir = try {
        if (Test-Path -LiteralPath $targetPath) {
            (Resolve-Path -LiteralPath $targetPath -ErrorAction Stop).Path
        } else {
            (Resolve-Path -Path $targetPath -ErrorAction Stop).Path
        }
    } catch {
        Write-Error "Directory not found: $targetPath"
        return
    }

    $subDirs = @(Get-ChildItem -LiteralPath $targetDir -Directory -Force -ErrorAction SilentlyContinue)
    if ($subDirs.Count -eq 0) {
        Write-Host "No subdirectories found in '$targetDir'." -ForegroundColor Yellow
        return
    }

    $results = if ($PSVersionTable.PSVersion.Major -ge 7) {
        $subDirs | ForEach-Object -Parallel {
            $dirPath = $_.FullName.TrimEnd('\')
            $raw = robocopy $dirPath NULL /L /S /NFL /NDL /NJH /NC /NP /BYTES /XJ /R:0 /W:0 2>$null
            $bytes = 0L
            $text = $raw -join "`n"
            if ($text -match 'Bytes\s*:\s*(\d+)') {
                $bytes = [int64]$Matches[1]
            }

            $human = switch ($bytes) {
                { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
                { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
                { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
                default        { "$_ B" }
            }

            [PSCustomObject]@{
                Folder     = $_.Name
                Size       = $human
                GB         = [math]::Round($bytes / 1GB, 3)
                TotalBytes = $bytes
            }
        } -ThrottleLimit 8
    } else {
        foreach ($d in $subDirs) {
            $dirPath = $d.FullName.TrimEnd('\')
            $raw = robocopy $dirPath NULL /L /S /NFL /NDL /NJH /NC /NP /BYTES /XJ /R:0 /W:0 2>$null
            $bytes = 0L
            $text = $raw -join "`n"
            if ($text -match 'Bytes\s*:\s*(\d+)') {
                $bytes = [int64]$Matches[1]
            }

            $human = switch ($bytes) {
                { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
                { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
                { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
                default        { "$_ B" }
            }

            [PSCustomObject]@{
                Folder     = $d.Name
                Size       = $human
                GB         = [math]::Round($bytes / 1GB, 3)
                TotalBytes = $bytes
            }
        }
    }

    $sorted = $results | Sort-Object TotalBytes -Descending
    if ($Top -gt 0) {
        $sorted = $sorted | Select-Object -First $Top
    }

    $sorted
}

Set-Alias -Name dus -Value dirsize -ErrorAction SilentlyContinue
