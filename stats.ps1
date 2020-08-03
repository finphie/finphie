param(
    [Parameter(Mandatory)]
    [string]$login,
    [Parameter(Mandatory)]
    [string]$token
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
    $body = @"
    {
        "query":
            "query {
                user(login: \"$login\") {
                    repositories(ownerAffiliations: OWNER, isFork: false, first: 100) {
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

    $languages = $response.Data.User.Repositories.Nodes |
    ForEach-Object { $_.Languages.Edges } |
    Select-Object * -ExcludeProperty Node -ExpandProperty Node |
    Group-Object Name |
    Select-Object Name, @{Name='Color'; Expression={($_.Group | Select-Object Color -First 1).Color}}, @{Name='Size'; Expression={($_.Group | Measure-Object Size -Sum).Sum}} |
    Sort-Object Size -Descending

    return $languages
}

function New-Svg
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$languages
    )

    $totalSize = ($languages | Measure-Object Size -Sum).Sum
    $progressWidth = 200
    $progressHeight = 8
    $progressColor = '#e1e4e8'
    $fontSize = 12
    $fontColor = '#586069'
    $topMargin = 10
    $leftMargin = 20
    $topPadding = 5
    $leftPadding = 10
    $width = 300
    $height = $languages.Length * ($fontSize + $topPadding + $progressHeight + $topMargin) + 15

    $svg = "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 $width $height`">"
    $y = $topMargin + $fontSize

    foreach ($language in $languages) {
        $percentage = $language.Size / $totalSize
        $languageWidth = [Math]::Ceiling($progressWidth * $percentage)

        $svg += @"
<text x="$leftMargin" y="$y" font-size="$fontSize" fill="$fontColor">$($language.Name)</text>
<text x="$($progressWidth + $leftMargin + $leftPadding)" y="$($y + $fontSize + 2)" font-size="$fontSize" fill="$fontColor">$($percentage.ToString("0.00%"))</text>
<path fill="$progressColor" d="M$leftMargin $($y + $topPadding)h${progressWidth}v${progressHeight}H$leftMargin"/>
<path fill="$($language.Color)" d="M$leftMargin $($y + $topPadding)h${languageWidth}v${progressHeight}H$leftMargin"/>
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

$path = 'image'
if (!(Test-Path $path))
{
    New-Item $path -ItemType Directory | Out-Null
}

New-Svg $json | Out-File -FilePath "$path/language.svg" -NoNewLine