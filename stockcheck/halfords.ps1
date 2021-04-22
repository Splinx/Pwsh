#Requires -Modules Selenium
#Requires -Module PoshGram

##########################################################################################################

#Quick and Dirty script to notify on halfords restocking

##########################################################################################################

#PoshGram Module
#https://www.powershellgallery.com/packages/PoshGram/1.16.0
#https://www.techthoughts.info/poshgram-powershell-module-for-telegram/#Code_Examples

##########################################################################################################

Param(
   [Parameter(Mandatory=$true)]  [string]$postcode,
   [Parameter(Mandatory=$true)] [string]$url,
   [Parameter(Mandatory=$false)] [int]$maxRetry = 3,
   [Parameter(Mandatory=$false)] [int]$retrySeconds = 10,
   [Parameter(Mandatory=$false)] [string]$telegramBotToken, #https://api.telegram.org/bot{telegramBotToken}/getUpdates
   [Parameter(Mandatory=$false)] [string]$telegramGroupChat,
   [Parameter(Mandatory=$false)] [bool]$telegramEnabled = 1, #Enabvled by default, disabled anyway if token/chatid not supplied
   [Parameter(Mandatory=$false)] [bool]$telegramNotInStock = 0 #by default, do not send a telegram when the item is NO IN STOCK
)

function get_dateString {
    return Get-Date -UFormat '+%Y-%m-%dT%H:%M:%S'
}

##########################################################################################################

#BIKE WE WANT
#https://www.halfords.com/bikes/kids-bikes/apollo-craze-junior-mountain-bike---24in-wheel-400484.html
#IN STOCK TESTS
#https://www.halfords.com/bikes/kids-bikes/carrera-luna-mountain-bike---24in-wheel-400542.html

##########################################################################################################

$checkInstall = $true
$binaries = 'C:\selenium'

if ($telegramBotToken.Trim() -eq "" -or $telegramGroupChat.Trim() -eq ""){
    $telegramEnabled = $false
}

##########################################################################################################

#https://stackoverflow.com/questions/817198/how-can-i-get-the-current-powershell-executing-file
$logName = get-date -format yyyyMMdd
$ScriptFullPath = Split-Path $MyInvocation.MyCommand.Definition -Parent
# Start logging stdout and stderr to file
Start-Transcript -Path "$($ScriptFullPath)\logs\$($logName).log" -Append -UseMinimalHeader

if ($checkInstall) {

    if (-not (Get-Module Selenium)) {
        write-host "Selenium Module not available, installing..."
        Install-Module -Name Selenium -AllowPrerelease -Force
    }
    else {
        write-host "Selenium Module available"

    }

    if (-not (Get-Module PoshGram)) {
        write-host "PoshGram Module not available, installing..."
        Install-Module -Name PoshGram -MinimumVersion 1.16.0
    }
    else {
        write-host "PoshGram Module available"
    }

}

##########################################################################################################

#If you have problems specifically targetting web driver then you can manually target the file in binaries
#import-Module $binaries\WebDriver.dll -Verbose:$false  #Version: 4.0.0

##########################################################################################################

$ChromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
$ChromeOptions.AddArguments(@(
        "--headless",
        "--window-size=1920x1080",
        "--disable-gpu",
        "--disable-extensions",
        "--log-level=3",
        "--safebrowsing-disable-download-protection",
        "--safebrowsing-disable-extension-blacklist",
        "--disable-download-protection",
        "--disable-notifications",
        "--ignore-certificate-errors"
    ))


# Search for postive, negative or unknown (x times) until we get a result
$result = $false
$thisTry = 0

do {

    Write-Host "Searching for item in postcode: $($postcode).  Attempt: $($thisTry+1)"

    # Create a new ChromeDriver Object instance.
    $ChromeDriver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($binaries, $ChromeOptions)

    # Launch a browser and go to URL
    $ChromeDriver.Navigate().GoToURL($url)
    Start-Sleep -Seconds 2

    $ChromeDriver.ExecuteScript("window.scrollTo(0, 1000)")
    $location = $ChromeDriver.FindElementByXPath("//input[@placeholder='Postcode / Town']")
    $location.SendKeys($postcode)

    Start-Sleep -Seconds 1
    $location.Submit()
    Start-Sleep -Seconds 2

    $collectionWraps = $ChromeDriver.FindElementsByClassName("b-product-collect-item__wrap")

    Write-Host "Location count = $($collectionWraps.Count)" 

    if ($collectionWraps.Count -gt 0) {

        Write-Host "Found at least one in stock location! Location count: $($collectionWraps.Count)" -ForegroundColor Green

        if ( $ChromeDriver.FindElementsByXPath("//*[contains(@class, 'b-product-location__link') and contains(@title, 'Show more store')]").Count -gt 0) {
            $moreLocations = $ChromeDriver.FindElementByXPath("//*[contains(@class, 'b-product-location__link') and contains(@title, 'Show more store')]")  
            $moreLocations.Click()
            
            Start-Sleep -Seconds 1

            Write-Host "Found more locations..."

            $collectionWraps = $ChromeDriver.FindElementsByClassName("b-product-collect-item__wrap")
            Write-Host "Stock location count: $($collectionWraps.Count)" -ForegroundColor Green         
        }

        $tmpMsg = "item is in stock $($url)`n" + "$($collectionWraps[0].Text)" 

        Write-Host $tmpMsg -ForegroundColor Green

        if ($telegramEnabled){
            Send-TelegramTextMessage -BotToken $telegramBotToken -ChatID $telegramGroupChat -Message $tmpMsg
        }

        $result = $true

    }
    elseif ( $ChromeDriver.FindElementsByClassName("b-product-home__error").Count -gt 0) {
        $tmpMsg = "Item not available for purchase at $($postcode).`n$($url)" 
        Write-Host  $tmpMsg  -ForegroundColor Red    

        if ($telegramEnabled -and $telegramNotInStock) {
            Send-TelegramTextMessage -BotToken $telegramBotToken -ChatID $telegramGroupChat -Message $tmpMsg
        }

        $result = $true
    }
    else {        
        if ($thisTry -eq ($maxRetry-1)){
            $result = $true

            $tmpMsg = "Purchase availability unknown`n$($url)`nAttempt $($thisTry + 1) of $($maxRetry). Tried over $($retrySeconds * $maxRetry ) seconds."

            Write-Host $tmpMsg -ForegroundColor Yellow 

            if ($telegramEnabled){
                Send-TelegramTextMessage -BotToken $telegramBotToken -ChatID $telegramGroupChat -Message $tmpMsg -disablenotification
            }

        } else { 
            $tmpMsg = "Purchase availability unknown:`n$($url)`nAttempt $($thisTry + 1) of $($maxRetry). Trying again in $retrySeconds seconds." 
            Write-Host $tmpMsg -ForegroundColor Yellow 
            $thisTry = $thisTry + 1

            Start-Sleep -Seconds $retrySeconds
        }
    }

    $ChromeDriver.Close()
    $ChromeDriver.Quit()

} while ($result -eq $false)

Write-Host "$(get_dateString): Complete"

# Stop logging to file
Stop-Transcript
