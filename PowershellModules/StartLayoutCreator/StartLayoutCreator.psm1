<#
    -----------------------------------------------------------------------------
    Arrowhead Dental Lab admin_scripts
    Script Name: StartLayoutCreator
    Original Author: JJ Fullmer
    Created Date: 2017-10-04
    Version: 1.0
    -----------------------------------------------------------------------------
#>
function New-StartLayout {
    <#
    .SYNOPSIS
    Create a new start layout object from legacy start menu folders
    
    .DESCRIPTION
    Goes through the current user's or a given path of shortcuts and creates a layout with groups and sub groups based on 
    folders and subfolders.
    After creating a startlayout you can export-startlayoutxml and then set-startlayout 
    Currently only supports tiles of 2x2 (medium) size. Could be made to work with small tiles, but wide size tiles might be trickier.
    
    .PARAMETER startMenuPath
    the path to the shortcut files desired to become a start layout
    
    .PARAMETER width
    The width of the layout, defaults to 6. Suggest keeping at 6 as 8 can cause issues with applying
    
    .PARAMETER overrideOptions
    The options such as the default 'LayoutCustomizationRestrictionType="OnlySpecifiedGroups"' that makes it so only
    the groups in this layout can't be edited when applied via group policy. Other things can be pinned in custom groups
    
    .PARAMETER startFormat
    The startStr of the xml format for a later to string variable
    
    .PARAMETER endFormat
    The ending strings of the xml format
    
    .PARAMETER groups
    The custom object created by the function that is a list of start group psobjects from Get-StartGroup
    
    .EXAMPLE
    Create a new layout, export it to the default 'C:\startLayoutFromStartMenu.xml' and set it via gpo
    New-StartLayout -startMenuPath "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs" | Export-StartLayoutXml | Set-StartLayout -gpo;
    
    #>
    [CmdletBinding()]
    param (
        [string]$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        [int32]$width = 6,
        $overrideOptions = 'LayoutCustomizationRestrictionType="OnlySpecifiedGroups"',
        $startFormat = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupCellWidth="$width" />
    <DefaultLayoutOverride $overrideOptions>
         <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="$width">
"@,
        $endFormat = @"
            </defaultlayout:StartLayout>
        </StartLayoutCollection>
    </DefaultLayoutOverride>
</LayoutModificationTemplate>
"@,
        [System.Collections.Generic.List[PSCustomObject]]$groups
    )
    
    begin {
        $groups = New-Object System.Collections.Generic.List[PSCustomObject];
        Write-Verbose 'Creating Layout object...';
        $Layout = [PSCustomObject]@{
            width = $width
            overrideOptions = $overrideOptions
            groups = $groups
            startStr = $startFormat
            endStr = $endFormat
        }
    }
    
    process {
        # get start groups
        Write-Verbose "Searching $startMenuPath for start group folders..."
        (Get-ChildItem -Path $startMenuPath).ForEach({
            if ($_.Attributes -match 'Directory') {
                if ($_.name -ne 'Startup') {
                    Write-Verbose "Getting start group from folder $($_.FullName)...";
                    $Layout.groups.Add($(Get-StartGroup -pth $_.FullName -width $width));
                }
            }
        });
    }
    
    end {
        Write-Verbose "Layout object $($layout) created";
        return $Layout;
    }
}

function Export-StartLayoutXml {
    <#
    .SYNOPSIS
    A modified version of microsoft's Export-startlayout that uses a custom object made by New-StartLayout
    
    .DESCRIPTION
    A toString kind of function that creates a properly formatted start layout xml and utilizes the desktopapplicationID's or metro app ID's found
    when the object is creating using New-StartLayout.
    The formatting is done with a here-string to make it simple to see what it's doing and easy to edit later when microsoft ineveitably changes the format again
    
    .PARAMETER layout
    The custom ps object that can be passed in the pipeline. Is created by New-StartLayout
    
    .PARAMETER xmlFile
    The path and name of the exported xml, defaults to $xmlFile = 'C:\startLayoutFromStartMenu.xml'
    This path string is the return value of this function and can be passed through the pip to set-startlayout
    
    .EXAMPLE
    # export a new layout from the current user's start menu to the default location and set the layout to the default profile 
    Export-StartLayoutXml -layout $(New-StartLayout) | Set-StartLayout;
    
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)
        ]
        [PSCustomObject]$layout,
        
        [Parameter(
            Position = 1, 
            Mandatory = $false)
        ]
        [string]
        $xmlFile = 'C:\startLayoutFromStartMenu.xml'
    )
    
    begin {
        if ($layout -eq $null) {
            $layout = New-StartLayout;
        }
        Write-Verbose "Exporting $($layout) to $xmlFile";
    }
    
    process {
        $cnt=1;
        $xml = 
@"
$($layout.startStr)
$($layout.groups | ForEach-Object {
"                <start:Group Name=`"$($_.Name)`">`n"
                    $($_.Folders | ForEach-Object {
"                   <start:Folder Size=`"$($_.Size)`" Column=`"$($_.Column)`" Row=`"$($_.Row)`">`n"
                        $($_.Tiles | ForEach-Object { "                       $(Get-TileString -Tile $_)"})
"                   </start:Folder>`n"})
                    $($_.Tiles | ForEach-Object {"                   $(Get-TileString -Tile $_)"})
"                 </start:Group>"  
$(if($cnt -lt $layout.groups.Count) { $cnt++; "`n" })})
$($layout.endStr)
"@
    }
    
    end {
        Out-File -FilePath $xmlFile -Encoding oem -InputObject $xml;
        Write-Verbose "Exported to xml file $xmlFile...";
        return $xmlFile;
    }
}

function Set-StartLayout {
    <#
    .SYNOPSIS
    Set the layout xml file as the start layout via default profile or local gpo
    
    .DESCRIPTION
    uses PolicyFileEntry module for gpos and import-startlayout for profile level
    
    .PARAMETER xmlFile
    The xmlfile to set
    
    .PARAMETER regPol
    the location of the machine pol group policies file, defaults to the default
    $regPol = 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol',
    
    .PARAMETER winPol
    The path to the policy key containing the start layout policy, set as default
    $winPol = 'Software\Policies\Microsoft\Windows\Explorer',
    
    .PARAMETER gpt
    the path to the gpt.ini file to increment the version when updating local gpo
    $gpt = 'C:\WINDOWS\system32\grouppolicy\gpt.ini',
    
    .PARAMETER gpo
    switch param to set via local gpo, defaults to false
    
    .EXAMPLE
    #use import-startlayout
    Set-StartLayout -xmlFile C:\startLayout.xml
    #use local gpo
    Set-StartLayout -xmlFile C:\startLayout.xml -gpo
    
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)
        ]
        [string]
        $xmlFile,
        $regPol = 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol',
        $winPol = 'Software\Policies\Microsoft\Windows',
        $gpt = 'C:\WINDOWS\system32\grouppolicy\gpt.ini',
        [switch]$gpo
    )
    
    begin {
        Write-Verbose "setting $xmlFile to be the computer's start layout";
        (Get-ChildItem $xmlFile).LastWriteTime = Get-Date;        
        if ($gpo) { 
            Install-Module -Module PolicyFileEditor -Force;
            Import-Module PolicyFileEditor -Global -Force;
        }
    }
    
    process {
        if($gpo) {
            Write-Verbose 'setting start layout group policy...';
            Set-PolicyFileEntry $regPol -Key "$winPol\Explorer" -ValueName StartLayoutFile -Data $xmlFile
        }
        else {
            Write-Verbose 'Importing startlayout to default profile for new users...';
            Set-Location -Path 'C:\';
            Import-StartLayout -LayoutLiteralPath $xmlFile -MountLiteralPath $env:SystemDrive;
        }
    }
    
    end {
        (Get-ChildItem $xmlFile).LastWriteTime = Get-Date; #update date time stamp on file
        Update-GptIniVersion $gpt -PolicyType Machine;
        Write-Verbose "$xmlFile set as start layout for all users on this computer";
    }
}

function Get-TileString {
    [CmdletBinding()]
    param (
        [PSCustomObject]$Tile,
        $type = $Tile.type,
        $Size = $Tile.Size,
        $col = $Tile.Column,
        $row = $Tile.Row,
        $id = $Tile.id,
        $idType
    )

    begin {
        if($type -eq 'start:Tile') {
            $idType = 'AppUserModelID';            
        }
        else {
            $idType = 'DesktopApplicationID';
        }
    }
    
    process {
        $tileStr ="<$type Size=`"$Size`" Column=`"$col`" Row=`"$row`" $idType=`"$id`" />`n";
    }
    
    end {
        return $tileStr;
    }
}

function Get-StartGroup {
    [CmdletBinding()]
    param (
        # start:DesktopApplicationTile Size="2x2" Column="4" Row="0" DesktopApplicationLinkPath
        $pth,
        [int32]$width = 6,
        $Tile = [PSCustomObject]@{
            type = 'start:DesktopApplicationTile'
            Size = '2x2'
            Column = 0
            Row = 0
            id = ''
        },
        $Folder = [PSCustomObject]@{
            Size = '2x2'
            Column = 0
            Row = 0
            Tiles = New-Object System.Collections.Generic.List[PSCustomObject]            
        },
        $group = [PSCustomObject]@{
            Name = Split-Path -Path $pth -Leaf
            Folders = New-Object System.Collections.Generic.List[PSCustomObject]
            Tiles = New-Object System.Collections.Generic.List[PSCustomObject]
        },
        $colCnt,
        $rowCnt
    )
    
    begin {
        $items = Get-ChildItem -Path $pth;
        $colCnt = 0;
        $rowCnt = 0;
    }
    
    process {
        Write-Verbose "Parsing the path $pth for shortcuts to go in the group $($group.Name)...";
        $items.ForEach({
            if ($_.Attributes -match 'Directory') {
                Write-Verbose "$_ is a directory, creating folder tile...";
                $group.Folders.Add($(Get-FolderTile -pth $_.FullName -col $colCnt -row $rowCnt));
                $cnts = Set-Counts -rowCnt $rowCnt -colCnt $colCnt -width $width; $rowCnt = $cnts.rows; $colCnt = $cnts.cols;                    
            }
            else {
                Write-Verbose "$_ is a link, creating normal tile...";
                $tile = Get-Tile -pth $_.FullName -col $colCnt -row $rowCnt;
                if($tile -ne $null) {
                    $group.Tiles.Add($tile);
                    $cnts = Set-Counts -rowCnt $rowCnt -colCnt $colCnt -width $width; $rowCnt = $cnts.rows; $colCnt = $cnts.cols;
                }
            }
        });
    }
    
    end {
        Write-Verbose "Got group $($group.Name)";
        return $group;
    }
}

function Set-Counts {
    <#
    .SYNOPSIS
    increment row/col count

    .EXAMPLE
    $cnts = Set-Counts -rowCnt $rowCnt -colCnt $colCnt -width $width; $rowCnt = $cnts.rows; $colCnt = $cnts.cols;
    
    .NOTES
    May be a better way to pass references of variables and change them instead of this method.
    #>
    [CmdletBinding()]
    param (
        $rowCnt,
        $colCnt,
        $width
    )
        
    begin {
        $counts = [PSCustomObject]@{
            rows = $rowCnt
            cols = $colCnt
        };
    }
    
    process {
        Write-Verbose "incrementing row/col counters...";
        if (($counts.cols + 2) -lt $width) {
            $counts.cols += 2;
        }
        else {
            $counts.rows += 2;
            $counts.cols = 0;
        }
    }
    
    end {
        return $counts;
    }
}

function Get-Tile {
    [CmdletBinding()]
    param (
        $pth,
        $name,
        $col,
        $row,
        $size = '2x2',
        $Tile = [PSCustomObject]@{
            type = 'start:DesktopApplicationTile'
            Size = $size
            Column = $col
            Row = $row
            id = ''
        }
    )
    
    begin {
        $name = (Split-Path -Path $pth -Leaf).Replace('.lnk','');
        Write-Verbose "creating tile for $name...";
    }
    
    process {
        Write-Verbose "getting id...";
        $Tile.id = (Get-StartApps | Where-Object Name -eq $name).AppID;
        if ($Tile.id -match '!App') {
            Write-Verbose 'Adding uwa tile change type...'
            $Tile.type = 'start:Tile';   
        }
        Write-Verbose "tile id is $($Tile.id)";
    }
    
    end {
        Write-Verbose "Tile created for $name... $Tile"
        if ($Tile.id -eq $null -OR $Tile.id -eq "") {
            Write-Verbose 'Tile has no id, cant be pinned, return null';
            return $null; 
        }
        return $Tile;
    }
}

function Get-FolderTile {
    [CmdletBinding()]
    param (
        $pth,
        $col,
        $row,
        $Tile = [PSCustomObject]@{
            type = 'start:DesktopApplicationTile'
            Size = '2x2'
            Column = 0
            Row = 0
            id = ''
        },
        $Folder = [PSCustomObject]@{
            Size = '2x2'
            Column = $col
            Row = $row
            Tiles = New-Object System.Collections.Generic.List[PSCustomObject]            
        },
        $colCnt,
        $rowCnt
    )
    
    begin {
        Write-Verbose "Creating start folder from $pth....";
        $items = Get-ChildItem -Path $pth -Recurse;
        $colCnt = 0;
        $rowCnt = 0;
    }
    
    process {
        Write-Verbose "Parsing $items for start folder...";
        $items.ForEach({       
            if ($_.Attributes -notmatch 'Directory') {
                Write-Debug "StartFolder tile is $($_.FullName)";
                $tile = Get-Tile -pth $_.FullName -col $colCnt -row $rowCnt;
                if($tile -ne $null){
                    $Folder.Tiles.Add($tile);
                    $cnts = Set-Counts -rowCnt $rowCnt -colCnt $colCnt -width $width; $rowCnt = $cnts.rows; $colCnt = $cnts.cols;
                }
            }
        });
    }
    
    end {
        Write-Verbose "Folder created, contents are $Folder";
        return $Folder
    }
}

Export-ModuleMember -Function *;
return;

# SIG # Begin signature block
# MIIRDAYJKoZIhvcNAQcCoIIQ/TCCEPkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2Jg8PdantMHyVFWy7Cwt7kMs
# wC+ggg1zMIIFiTCCA3GgAwIBAgIQN1osf+GqS6BH6tcXABgA1DANBgkqhkiG9w0B
# AQsFADBLMRMwEQYKCZImiZPyLGQBGRYDY29tMR8wHQYKCZImiZPyLGQBGRYPYXJy
# b3doZWFkZGVudGFsMRMwEQYDVQQDEwpBcnJvd1NlY0NhMB4XDTE3MDIwNzIxNTg1
# MFoXDTIyMDIwNzIyMDg0MlowSzETMBEGCgmSJomT8ixkARkWA2NvbTEfMB0GCgmS
# JomT8ixkARkWD2Fycm93aGVhZGRlbnRhbDETMBEGA1UEAxMKQXJyb3dTZWNDYTCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMhkMlfIR+4RxhLYnlPRHxIp
# NDa2/xRM1tlJM9EH+4+OuMO0EQMFZyYQOBCoJtsEgwGAPQ8sakSeYNE2Tjt4Tyou
# abr6kOHdY6OIQPEf5cIqoTi2unlQLWnC/2tx5MBXmKFZV2ZkPeZRghJwnHByZXFn
# bX31f+BRk3Bx+/PPW7h7oJTwufLo7uJAoRNJkKfTsgijyASiVqmkh5C0Vg5o5C9G
# gv9DAMarhcSa1+ShF+EtxKWM4m3/MloAhb/rNPZUCUuyjqFEDQV8PdBrQh56oBZL
# Q+If2pYoPPxxn8H+WPJfVTj9lkZG0IJe2ca6hmBa7dymYjQSUIBEQFC8tK2bE2er
# 1vj61rORZPoxargJXTaF0SV+Hq0frPBD4GkIOQWGKbuaCfIo6nVnrPZuQ7trEAvN
# 4S2mvzHvJ+nwX1CQhwcCsRW0GaLXxrfyeBsfZW67UgHcGK1tXV5h6+DR0bSPFPaa
# l3kI+8rf+9NVyDAZrCm2i0Lw4NW4cxL6JBKPQPKtFV3UouwWOac9MEoqibbpYVJ3
# rYcNyNeps1oekiVKN8jydfZ3AqKXQfLzqTJdB16YWbFYs5Yn1liiJfAWT7AaxfAE
# HJ67Oqr9IzGxGEM//IxqBJQeIf5/5CcMJH2UeksHZ3z3wR6VpkA/v/1rJEDfgKY/
# GJPDMv8GPbCDu3ElADbpAgMBAAGjaTBnMBMGCSsGAQQBgjcUAgQGHgQAQwBBMA4G
# A1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRRWTnftW/d
# bLIOrwmI+JciijhD5TAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQsFAAOC
# AgEAw8bm2JLVfX4caZHQ52YZB5Td/6XAoznPTAmdycOTyvCmTyUjv9A8Ftc1OexN
# v2IPFRD7bL95Ms3mBfE2IBWpk/h5Mm/8ZN+6AuLXkc6200zhgbMnjvGb5s8YgSUM
# nPNHnyFBA1V+P66HBc5emJKLHY50aHyI+vk0udaMHYNrfMvlopvUzpMiumWSgp3M
# Y9GfiMmC2h3tjJ7E8JwNh+FSqUi63kZLqaK0B/mjtBG4DXaWLk5kSXxnntgX9oLs
# 3iX9U/I0rolonjt3UVOJeRPOGiRqcCH376lgkI/FRf4aFAKf3H6WHAqgbyx+vN2h
# e1uwbMQdX0gl3mok5aZoSI9znJbVIjBsZrjglvd3fXyPGbMUWCRVmOSlFwDO+zm1
# s8f5cFDtVnzMr8W+TOXd6+oxbplAMJ6XdKQPrvZTBBN55eB3WadXa/BdSXBxnBhn
# SwLq+o0H9W205eXFRZNCnH3KJlnsEIsMvLiNAw9/qVYo+2nU91x4lRrPa19DqmF2
# 5D/Eh0XkubjUa4b954jX+JpffObTyc5CvpL5gUODVlyMX0a40y74zubi7Zq9+xXj
# lOeOnOWpgDmWJD6iJbayIdyfZBlf/B9h3c9eFBWeCyFSuCpu8uBzmHUtem/JjF2t
# MTiJ4Cvmw1eNC8MqQrXDx3s1G5qpVNE3DWNzlCJs+QfHdJIwggfiMIIFyqADAgEC
# AhNdAAAAFUnUWN7n/AV6AAAAAAAVMA0GCSqGSIb3DQEBCwUAMEsxEzARBgoJkiaJ
# k/IsZAEZFgNjb20xHzAdBgoJkiaJk/IsZAEZFg9hcnJvd2hlYWRkZW50YWwxEzAR
# BgNVBAMTCkFycm93U2VjQ2EwHhcNMTcwMjEzMTkyMDUwWhcNMTgwMjEzMTkyMDUw
# WjCBpzETMBEGCgmSJomT8ixkARkWA2NvbTEfMB0GCgmSJomT8ixkARkWD2Fycm93
# aGVhZGRlbnRhbDEWMBQGA1UECwwNTmV0d29ya19Vc2VyczELMAkGA1UECxMCSVQx
# HzAdBgNVBAsTFk90aGVyIFNwZWNpYWwgQWNjb3VudHMxGjAYBgNVBAsTEUlUIEFk
# bWluIEFjY291bnRzMQ0wCwYDVQQDEwRKbWluMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAxMKgM0/bcf8kLuBYTsl7Mxm9bwm77FhLWfut0QSpzj63QwoG
# N0w1NKoKg2WAhs752wgUWOUzYeYuZsN4McO16RsOsr1Bt5J1KpAcIsz31P5vSOsq
# v3PPX8ad9aUrdVqjN36ceEsfxZmr/56x/YAi/laXDzLTyCiYHGyiA9YhdpCFi6KZ
# sMLPaDqbFjFlYIQnZBHRgXBh4t3h3y3rChOrblSrjGYcYMFNXO2Z9lJKVoCgd18n
# epiL5Brue4Wto/5j5pvLgXdkF1ngFm4hyNAsgmPqQiC0P/4/zwFcolZ9gNevQBU3
# TXQ+FZQ55WGxPl1M6rE8snbhb50nxzyyaXi2qxCWmx9s12wwHVesxS/baVEm7run
# stIpbo905A3ynKCFrBJaOhtFJn2IihM8GJ3sjdkzqmaahKDon7QcE/ibKMhqk/bB
# V4KJe/JPTe3PFAKaySsx06OSxPBZULFWqVEgxAdBTpRzW0ssMdrljDGZVceC7nUQ
# Swi7N7YlGHHn6aXSoDvCfy+cIa6hu/s000cIBxpr/v/Z/czWMbb9ZD8mG4k6X3bj
# FpteRvotWcBfKwHO8OU0QsT4nn1DrNES2qNAqXbgma0gXz9CASHz7XRzMylqSzsg
# sX0lAth+hAXOWq0AS0VyXrjHSV4A4MgrvI/hrjfpJtKkzXLk77w09L/o+hUCAwEA
# AaOCAmAwggJcMB0GA1UdDgQWBBROHsNAuH1qE7yu3MLVFpRFPPCq9TAfBgNVHSME
# GDAWgBRRWTnftW/dbLIOrwmI+JciijhD5TCB0QYDVR0fBIHJMIHGMIHDoIHAoIG9
# hoG6bGRhcDovLy9DTj1BcnJvd1NlY0NhLENOPWFycm93c2VjLENOPUNEUCxDTj1Q
# dWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0
# aW9uLERDPWFycm93aGVhZGRlbnRhbCxEQz1jb20/Y2VydGlmaWNhdGVSZXZvY2F0
# aW9uTGlzdD9iYXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIHE
# BggrBgEFBQcBAQSBtzCBtDCBsQYIKwYBBQUHMAKGgaRsZGFwOi8vL0NOPUFycm93
# U2VjQ2EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZp
# Y2VzLENOPUNvbmZpZ3VyYXRpb24sREM9YXJyb3doZWFkZGVudGFsLERDPWNvbT9j
# QUNlcnRpZmljYXRlP2Jhc2U/b2JqZWN0Q2xhc3M9Y2VydGlmaWNhdGlvbkF1dGhv
# cml0eTAlBgkrBgEEAYI3FAIEGB4WAEMAbwBkAGUAUwBpAGcAbgBpAG4AZzAOBgNV
# HQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwMwYDVR0RBCwwKqAoBgor
# BgEEAYI3FAIDoBoMGGptaW5AYXJyb3doZWFkZGVudGFsLmNvbTANBgkqhkiG9w0B
# AQsFAAOCAgEAIfFbeTk08rYqHRhuNXqBVQWZQxU6Yc6DoABXsNS5RKV3ubn9M6w1
# Yj0mW/crMxUorRU+ZrSPqOgLecOoP5eUgULpdX1QXhsDGU6qxreN6yW5FIB1TEQf
# VpnkXhoB9oyoxFrTL23m2Qk9pmuiIrtV4F+E/UHvYZ1nVqpby7UlO6aNH54+A4hS
# O/PMWSS7NWJDakmqKAMrebRtdxYHYoY4qsnXAZx2pdKPg8SFqS54emj4DYKGC+Gf
# a9KE8NUinH6VkGF1gX/Zvz0UOoogCDO+SrrfcwEhclfhLUYHAymO0FFeoT+NPjsS
# sJ+Os7VMW1699M9t0N784/qRIViyDQZPkeGbZyvN3x6+u8xD9L28QQ1phbGsGezZ
# ovf0A7y9E+DJw1H//2z00wC1mLaEZ2rkJbQY3EMLPYgbxJKoPV35xfvALU7sn+c1
# x9KcoevvUfBUcuocLyWPkwErMC/NaDjmHqZ4i+wiHfS6M7uEeXUw6LqzKYn6PrxK
# LHICsjwCj59U0bofY/hNt1vvbZc63tVg09uo2OgIivPSfIWJAG85nEcvtzFCRHBz
# 9EiGW8tL9irYQEGdhuHkotTB3YuRLI0pC3SeqqtVALqmQb75O3d2Dq3qA579z94a
# FfiTdmxUChT4P5bkOs0nnaxqG9/ZVFjNcskMwjkbkcXYFdaD/FmXqn8xggMDMIIC
# /wIBATBiMEsxEzARBgoJkiaJk/IsZAEZFgNjb20xHzAdBgoJkiaJk/IsZAEZFg9h
# cnJvd2hlYWRkZW50YWwxEzARBgNVBAMTCkFycm93U2VjQ2ECE10AAAAVSdRY3uf8
# BXoAAAAAABUwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFKCA76Z3dkd/PYqsoGor2QRDrq7DMA0G
# CSqGSIb3DQEBAQUABIICAG0pGH2EHkgAdxmQ3NPwdTmH7ZT1D9vTYaWQRx2sQ7hH
# 4eu9ran1oXxDsHnkBMOMpDfC7n03KCku7EVCKvsxQJe+s5myPoTFOmxjrYczI1JP
# lVFP5DOYyf+kvmA+3eoJl7n5SOeemKybqv69NKVgqJxt48/R3M2Bo7SDv5agz9qQ
# 4DB/l/BrUtxBPkl+0mEQG8/H29eYd2GFz5APLHhoSe/qTGvrWDUw46eMo87skpUV
# 1iW8urHDUGThLN3YgvmovMDjMfmUB6BkIzy1gjM5vr/z1vWVZmDD4eVc2+EzN4YW
# iNQ5hwJ0w8dljMXy2CnysP6QyBJfq4+j0Txmrslg1WIWLP0YpKVDCZDkJ8x1khXQ
# JjENmkl+ZGStbrsAxBCrU9PDrvc3pW6JtZlcHshpPVSdLc9NhGwzgMOl1KBqSg4D
# /+WbJkrlhhjnmkZ74pkCr0eV+hrpk/I3mmppV+J3XDnILF12Emz8p3dnxt0Wrdw7
# edfhHplqb9vRDmjqDbn5/zVhD3ghdBkN3PO4j2Rk5SOt+iDi2nW2YO4cH3oPhN4X
# EagbiOwm3d9DV7GaDa1hjpLFeJ9fsEJFbsVN94iegToQ752KG1F/5IzzEu/r8pE0
# kDJd8CtbNsHAI7lz70sfTe60KZOjvMQeiiowlBX0G3q8jb6LQcQlMs/KkeLpqGjs
# SIG # End signature block
