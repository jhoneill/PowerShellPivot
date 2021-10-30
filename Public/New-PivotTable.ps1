function New-PSPivotTable {
    param(
        [string[]]$index,
        [string[]]$values,
        [string[]]$ExcludeValues,
        [string[]]$column,
        [Parameter(ValueFromPipeline)]
        $InputObject,
        [ValidateScript( { $_ -in (Get-AggregateFunctionNames) })]
        [object[]]$aggregateFunction = 'Average',
        $MissingValueText = '[missing]',
        [double]$Fill = [double]::NaN,
        [Switch]$PrettyPrint,
        [Switch]$Raw
    )

    Process {
        if ($null -ne $InputObject) {
            $data += @($InputObject)
        }
    } 
    
    End {
        $boundParameters = @{} + $PSBoundParameters    
        if ($index.Count -ge 2) {
            "Multiple indexes not yet implemented"
            return $null
        }

        if ($column) {
            "Column dimensions not yet implemented"
            return $null
        }

        if ($boundParameters.Keys.Count -eq 1 -and $boundParameters.Contains("InputObject")) { return $null }
        if ($null -eq $data) { return $null }

        $propertyNames = $data[0].psobject.properties.name
        [System.Collections.ArrayList]$values = $values

        for ($idx = $values.Count - 1; $idx -gt -1; $idx--) {
            $propertyName = $values[$idx]
            if (($propertyNames -eq $propertyName).Count -eq 0) {
                Write-Warning "Property [$propertyName] not found, and is removed from the measure calculations"
                $values.RemoveAt($idx)        
            }
        }

        if ($aggregateFunction -eq 'AllStats') {
            $aggregateFunction = "Min", "Max", "Average", "STD", "Sum", "Count"
        }

        $aggregateFunction = [string[]]$aggregateFunction
        if ($index.Count -eq 1 -and $null -eq $values) {
            $numberProperties = Get-AllDataTypes $data | Where-Object { $_.DataType -match '^(int|float|double)$' } 
            $values = @($numberProperties.Name)
        }

        if ($ExcludeValues) {
            for ($idx = $values.Count - 1; $idx -gt -1; $idx--) {
                $propertyName = $values[$idx]
                if (($ExcludeValues -eq $propertyName).Count -eq 1) {
                    $values.RemoveAt($idx)        
                }
            }
        }

        if ($column) {
            $index += @($column)
        }

        $result = [ordered]@{}
        foreach ($record in $data) {
            $currentKey = $null
            for ($idx = 0; $idx -lt $index.Count; $idx++) {
                $key = $record.($index[$idx])
            
                if ([string]::IsNullOrEmpty($key)) {
                    $key = $MissingValueText
                }

                if ($null -eq $currentKey) {
                    if (!$result["$key"]) {
                        $result["$key"] = [Ordered]@{}
                    }
                    $currentKey = $result["$key"]
                }
                else {
                    if (!$currentKey["$key"]) {
                        $currentKey["$key"] = [Ordered]@{}
                    }
                    $currentKey = $currentKey["$key"]
                }
            }

            foreach ($propertyName in $values) {
                
                foreach ($aggregation in $aggregateFunction) {
                    $pn = "$($aggregation)_$($propertyName)"
                    $measure = $record.$propertyName
                    
                    if ([string]::IsNullOrEmpty($measure)) {
                        $measure = $Fill
                    }

                    if ($null -eq $currentKey.$pn) {
                        $measure = ConvertFrom-IntPtr $measure
                        $currentKey.$pn = New-Object $aggregation -ArgumentList $measure
                    }
                    else {
                        $measure = ConvertFrom-IntPtr $measure
                        $currentKey.$pn.AddToMeasure($measure)
                    }
                }
            }
        }
    
        if ($PrettyPrint) {
            PrettyPrint $result
            return
        }

        if ($Raw -or $index.Count -gt 1) {
            $result.metaData = [ordered]@{
                "index"             = $index                
                "values"            = $values
                "excludeValues"     = $ExcludeValues
                "column"            = $column
                "aggregateFunction" = $aggregateFunction
                "missingValueText"  = $MissingValueText
            }

            $result
        } 
        else {        
            doFmt $result
        }
    }
}

function ConvertFrom-IntPtr {
    param(
        [Parameter(Mandatory)]
        $measure
    )

    if ($measure -is [IntPtr]) {
        $measure.ToInt32() -as [double]
    }
    else {
        $measure
    }
}