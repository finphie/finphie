param(
    [Parameter(Mandatory)]
    [string]$login,
    [Parameter(Mandatory)]
    [string]$token,
    [string]$path = '.'
)

function Get-GitHubStats
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$login,
        [Parameter(Mandatory)]
        [string]$token
    )

    $uri = 'https://api.github.com/graphql'
    $headers = @{
        'Authorization' = "bearer $token"
    }

    $after = 'null'
    $languages = [System.Collections.ArrayList]@()
    $count = 0
    $maxCount = 10

    do {
        $body = @"
        {
            "query":
                "query {
                    user(login: \"$login\") {
                        repositories(ownerAffiliations: OWNER, isFork: false, first: 100, after: $after) {
                            pageInfo {
                                hasNextPage
                                endCursor
                            }
                            nodes {
                                languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
                                    edges {
                                        size
                                        node {
                                            name
                                            color
                                        }
                                    }
                                }
                            }
                        }
                    }
                }"
        }
"@.Replace(' ', '').Replace("`r", '').Replace("`n", ' ')

        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType 'application/json'

        $hasNextPage = $response.Data.User.Repositories.PageInfo.HasNextPage
        $after = "\`"$($response.Data.User.Repositories.PageInfo.EndCursor)\`""

        $language = $response.Data.User.Repositories.Nodes |
            ForEach-Object { $_.Languages.Edges } |
            Select-Object * -ExcludeProperty Node -ExpandProperty Node

        $languages.AddRange($language)
    } while ($hasNextPage -And ($count++ -lt $maxCount))

    $result = $languages |
        Group-Object Name |
        Select-Object Name, @{Name='Color'; Expression={($_.Group | Select-Object Color -First 1).Color}}, @{Name='Size'; Expression={($_.Group | Measure-Object Size -Sum).Sum}} |
        Sort-Object Size -Descending
    Write-Information "languages: $($result.Count)" -InformationAction Continue

    return $result
}

function ConvertTo-Svg
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$languages
    )

    $totalSize = ($languages | Measure-Object Size -Sum).Sum
    $progressWidth = 200
    $progressHeight = 8
    $darkModeBackgroundColor = '#0d1117'
    $progressColor = '#e1e4e8'
    $darkModeprogressColor = '#21262d'
    $fontSize = 12
    $fontColor = '#586069'
    $darkModeFontColor = '#8b949e'
    $topMargin = 10
    $leftMargin = 20
    $topPadding = 5
    $leftPadding = 10
    $width = 300
    $height = $languages.Length * ($fontSize + $progressHeight + $topMargin) + $topPadding + $fontSize

    $svg = @"
<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 $width $height`">
<style>
text{fill:$fontColor}
path{fill:$progressColor}
@media(prefers-color-scheme:dark){
svg{background-color:$darkModeBackgroundColor}
text{fill:$darkModeFontColor}
path{fill:$darkModeprogressColor}
}
</style>
"@
    $y = $topMargin + $fontSize

    foreach ($language in $languages) {
        $percentage = $language.Size / $totalSize
        $languageWidth = [Math]::Ceiling($progressWidth * $percentage)

        $svg += @"
<text x="$leftMargin" y="$y" font-size="$fontSize">$($language.Name)</text>
<text x="$($progressWidth + $leftMargin + $leftPadding)" y="$($y + $fontSize + 2)" font-size="$fontSize">$($percentage.ToString("0.00%"))</text>
<path d="M$leftMargin $($y + $topPadding)h${progressWidth}v${progressHeight}H$leftMargin"/>
<path style="fill:$($language.Color)" d="M$leftMargin $($y + $topPadding)h${languageWidth}v${progressHeight}H$leftMargin"/>
"@

        $y += $topMargin + $fontSize + $progressHeight
    }

    $svg += '</svg>'
    $svg = $svg.Replace("`r", '').Replace("`n", '')

    return $svg
}

try {
    $json = Get-GitHubStats $login $token
} catch {
    throw
    exit -1
}

if (!(Test-Path $path))
{
    New-Item $path -ItemType Directory | Out-Null
}

$file = Join-Path $path language.svg
ConvertTo-Svg $json | Out-File -FilePath $file -NoNewLine